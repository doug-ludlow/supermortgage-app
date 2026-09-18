import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import { z } from 'zod';
import { doorForProvider } from '../auth/firebase.js';
import { requireAuth, type AuthContext } from '../auth/verify.js';
import { transaction, type Db } from '../db/pool.js';
import { clientIp } from '../ip.js';
import { AgentPatch, Me, OnboardingPatch, Problem, type MeShape, type ProviderName } from '../schemas.js';
import type { Deps } from '../server.js';

// /v1/me: the signed-in person's user, household, agent and onboarding (SIGNUP-FOR-REAL.md §4.2).
// Every route verifies the Bearer token first; the uid only ever comes from that token.

interface MeRow {
  user_id: string;
  email: string | null;
  email_verified: boolean;
  display_name: string | null;
  providers: string[];
  user_created_at: Date;
  household_id: string;
  household_created_at: Date;
  agent_name: string | null;
  named_at: Date | null;
  stage: 'know' | 'setup' | 'chat';
  completed_at: Date | null;
}

const ME_SQL = `
  SELECT u.id AS user_id, u.email, u.email_verified, u.display_name, u.providers, u.created_at AS user_created_at,
         h.id AS household_id, h.created_at AS household_created_at,
         a.name AS agent_name, a.named_at,
         o.stage, o.completed_at
  FROM users u
  JOIN household_members hm ON hm.user_id = u.id
  JOIN households h ON h.id = hm.household_id
  JOIN agents a ON a.household_id = h.id
  JOIN onboarding o ON o.user_id = u.id
  WHERE u.firebase_uid = $1 AND u.deleted_at IS NULL
  LIMIT 1`;

async function loadMe(db: Db, uid: string): Promise<MeRow | null> {
  const result = await db.query<MeRow>(ME_SQL, [uid]);
  return result.rows[0] ?? null;
}

function toMe(row: MeRow, signedInWith: ProviderName): MeShape {
  const providers = row.providers.filter((p): p is ProviderName => p === 'apple' || p === 'google' || p === 'email');
  return {
    user: {
      id: row.user_id,
      email: row.email,
      emailVerified: row.email_verified,
      displayName: row.display_name,
      providers,
      signedInWith,
      createdAt: row.user_created_at.toISOString(),
    },
    household: { id: row.household_id, createdAt: row.household_created_at.toISOString() },
    agent: { name: row.agent_name, namedAt: row.named_at ? row.named_at.toISOString() : null },
    onboarding: { stage: row.stage, completedAt: row.completed_at ? row.completed_at.toISOString() : null },
  };
}

/** The door of this session; `custom` is our e-mail code. Unknown providers count as e-mail. */
function sessionDoor(auth: AuthContext): ProviderName {
  return doorForProvider(auth.signInProvider) ?? 'email';
}

export async function meRoutes(app: FastifyInstance, deps: Deps): Promise<void> {
  const routes = app.withTypeProvider<ZodTypeProvider>();
  const verify = requireAuth(deps.admin, deps.config.projectId);
  const security = [{ bearer: [] as string[] }];

  routes.route({
    method: 'POST',
    url: '/v1/me/bootstrap',
    preHandler: verify,
    schema: {
      tags: ['me'],
      summary: 'Create or refresh the user, household, agent and onboarding for the signed-in person',
      security,
      response: { 200: Me, 401: Problem, 409: Problem },
    },
    handler: async (request, reply) => {
      const auth = request.auth as AuthContext;
      const door = sessionDoor(auth);
      const providers = new Set<ProviderName>([door]);
      try {
        const record = await deps.admin.getUser(auth.uid);
        for (const info of record.providerData) {
          const p = doorForProvider(info.providerId);
          if (p) providers.add(p);
        }
      } catch (error) {
        request.log.warn({ err: error }, 'user record not read; providers from the token only');
      }
      const ip = clientIp(request, deps.config.environment);

      try {
        await transaction(deps.db, async (tx) => {
          const upsert = await tx.query<{ id: string }>(
            `INSERT INTO users (firebase_uid, email, email_verified, display_name, providers, last_seen_at)
             VALUES ($1, $2, $3, $4, $5, now())
             ON CONFLICT (firebase_uid) DO UPDATE SET
               email = COALESCE(EXCLUDED.email, users.email),
               email_verified = users.email_verified OR EXCLUDED.email_verified,
               display_name = COALESCE(EXCLUDED.display_name, users.display_name),
               providers = (SELECT array_agg(DISTINCT p) FROM unnest(users.providers || EXCLUDED.providers) AS p),
               last_seen_at = now(),
               deleted_at = NULL
             RETURNING id`,
            [auth.uid, auth.email ?? null, auth.emailVerified, auth.displayName ?? null, [...providers]],
          );
          const userId = upsert.rows[0]?.id;
          if (!userId) throw new Error('user upsert returned no row');
          const membership = await tx.query('SELECT 1 FROM household_members WHERE user_id = $1', [userId]);
          if (membership.rowCount === 0) {
            const household = await tx.query<{ id: string }>(
              'INSERT INTO households (owner_user_id) VALUES ($1) RETURNING id',
              [userId],
            );
            const householdId = household.rows[0]?.id;
            await tx.query(`INSERT INTO household_members (household_id, user_id, role) VALUES ($1, $2, 'owner')`, [householdId, userId]);
            await tx.query('INSERT INTO agents (household_id) VALUES ($1)', [householdId]);
          }
          await tx.query(
            `INSERT INTO onboarding (user_id, stage) VALUES ($1, 'know') ON CONFLICT (user_id) DO NOTHING`,
            [userId],
          );
          await tx.query(`INSERT INTO audit_log (user_id, event, detail, ip) VALUES ($1, 'me.bootstrap', $2, $3::inet)`, [
            userId,
            JSON.stringify({ door }),
            ip,
          ]);
        });
      } catch (error) {
        if ((error as { code?: string }).code === '23505') {
          request.log.warn('bootstrap: e-mail already belongs to another account');
          return reply.code(409).send({ error: 'email_in_use' });
        }
        throw error;
      }

      const row = await loadMe(deps.db, auth.uid);
      if (!row) throw new Error('bootstrap left no readable user');
      return toMe(row, door);
    },
  });

  routes.route({
    method: 'GET',
    url: '/v1/me',
    preHandler: verify,
    schema: {
      tags: ['me'],
      summary: 'The signed-in person',
      security,
      response: { 200: Me, 401: Problem, 404: Problem },
    },
    handler: async (request, reply) => {
      const auth = request.auth as AuthContext;
      const row = await loadMe(deps.db, auth.uid);
      if (!row) return reply.code(404).send({ error: 'not_bootstrapped' });
      await deps.db.query('UPDATE users SET last_seen_at = now() WHERE id = $1', [row.user_id]);
      return toMe(row, sessionDoor(auth));
    },
  });

  routes.route({
    method: 'PATCH',
    url: '/v1/me/agent',
    preHandler: verify,
    schema: {
      tags: ['me'],
      summary: 'Name the agent; completes onboarding',
      security,
      body: AgentPatch,
      response: { 200: Me, 400: Problem, 401: Problem, 404: Problem },
    },
    handler: async (request, reply) => {
      const auth = request.auth as AuthContext;
      const name = request.body.name;
      const row = await loadMe(deps.db, auth.uid);
      if (!row) return reply.code(404).send({ error: 'not_bootstrapped' });
      await transaction(deps.db, async (tx) => {
        await tx.query('UPDATE agents SET name = $2, named_at = now() WHERE household_id = $1', [row.household_id, name]);
        await tx.query('UPDATE onboarding SET completed_at = COALESCE(completed_at, now()) WHERE user_id = $1', [row.user_id]);
        await tx.query(`INSERT INTO audit_log (user_id, event) VALUES ($1, 'agent.named')`, [row.user_id]);
      });
      const updated = await loadMe(deps.db, auth.uid);
      if (!updated) return reply.code(404).send({ error: 'not_bootstrapped' });
      return toMe(updated, sessionDoor(auth));
    },
  });

  routes.route({
    method: 'PATCH',
    url: '/v1/me/onboarding',
    preHandler: verify,
    schema: {
      tags: ['me'],
      summary: 'Record the onboarding stage',
      security,
      body: OnboardingPatch,
      response: { 200: Me, 400: Problem, 401: Problem, 404: Problem },
    },
    handler: async (request, reply) => {
      const auth = request.auth as AuthContext;
      const row = await loadMe(deps.db, auth.uid);
      if (!row) return reply.code(404).send({ error: 'not_bootstrapped' });
      await deps.db.query('UPDATE onboarding SET stage = $2 WHERE user_id = $1', [row.user_id, request.body.stage]);
      const updated = await loadMe(deps.db, auth.uid);
      if (!updated) return reply.code(404).send({ error: 'not_bootstrapped' });
      return toMe(updated, sessionDoor(auth));
    },
  });

  routes.route({
    method: 'DELETE',
    url: '/v1/me',
    preHandler: verify,
    schema: {
      tags: ['me'],
      summary: 'Delete the account: rows, then the Identity Platform user',
      security,
      response: { 204: z.undefined().describe('Deleted'), 401: Problem },
    },
    handler: async (request, reply) => {
      const auth = request.auth as AuthContext;
      const ip = clientIp(request, deps.config.environment);
      await transaction(deps.db, async (tx) => {
        const user = await tx.query<{ id: string; email: string | null }>(
          'SELECT id, email FROM users WHERE firebase_uid = $1 AND deleted_at IS NULL FOR UPDATE',
          [auth.uid],
        );
        const row = user.rows[0];
        if (!row) return;
        if (row.email) await tx.query('DELETE FROM email_codes WHERE email = $1', [row.email]);
        await tx.query('DELETE FROM onboarding WHERE user_id = $1', [row.id]);
        await tx.query('DELETE FROM households WHERE owner_user_id = $1', [row.id]);
        await tx.query('DELETE FROM household_members WHERE user_id = $1', [row.id]);
        await tx.query(
          `UPDATE users SET deleted_at = now(), email = NULL, display_name = NULL, providers = '{}' WHERE id = $1`,
          [row.id],
        );
        await tx.query(`INSERT INTO audit_log (user_id, event, ip) VALUES ($1, 'me.delete', $2::inet)`, [row.id, ip]);
      });
      try {
        await deps.admin.deleteUser(auth.uid);
      } catch (error) {
        if ((error as { code?: string }).code !== 'auth/user-not-found') throw error;
      }
      return reply.code(204).send();
    },
  });
}
