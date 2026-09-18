import type { FastifyInstance } from 'fastify';
import type { ZodTypeProvider } from 'fastify-type-provider-zod';
import type { Deps } from '../server.js';
import { transaction } from '../db/pool.js';
import { codeMail } from '../mail/sender.js';
import { Empty, EmailStartRequest, EmailVerifyRequest, EmailVerifyResponse, Problem } from '../schemas.js';
import {
  CODE_TTL_MINUTES,
  MAX_ATTEMPTS,
  STARTS_PER_EMAIL_PER_HOUR,
  STARTS_PER_IP_PER_HOUR,
  generateCode,
  hashCode,
  hashesEqual,
  isPlausibleEmail,
  normalizeEmail,
} from './codes.js';
import { clientIp } from '../ip.js';

// The e-mail door: POST /v1/auth/email/start and /verify (SIGNUP-FOR-REAL.md §4.2).
// `start` always answers 200 {} — for unknown and known addresses, over the limits, and when the
// mail could not be sent — so nothing reveals whether an address exists.

interface CodeRow {
  id: string;
  code_hash: string;
  attempts: number;
  expires_at: Date;
}

export async function emailRoutes(app: FastifyInstance, deps: Deps): Promise<void> {
  const routes = app.withTypeProvider<ZodTypeProvider>();

  routes.route({
    method: 'POST',
    url: '/v1/auth/email/start',
    schema: {
      tags: ['auth'],
      summary: 'Send a six-digit code to an e-mail address',
      body: EmailStartRequest,
      response: { 200: Empty },
    },
    handler: async (request) => {
      const email = normalizeEmail(request.body.email);
      if (!isPlausibleEmail(email)) return {};
      const ip = clientIp(request, deps.config.environment);

      const code = generateCode();
      const stored = await transaction(deps.db, async (tx) => {
        const perEmail = await tx.query<{ n: string }>(
          `SELECT count(*)::text AS n FROM email_codes WHERE email = $1 AND created_at > now() - interval '1 hour'`,
          [email],
        );
        if (Number(perEmail.rows[0]?.n ?? 0) >= STARTS_PER_EMAIL_PER_HOUR) return false;
        const perIp = await tx.query<{ n: string }>(
          `SELECT count(*)::text AS n FROM audit_log WHERE event = 'email.start' AND ip = $1::inet AND created_at > now() - interval '1 hour'`,
          [ip],
        );
        if (Number(perIp.rows[0]?.n ?? 0) >= STARTS_PER_IP_PER_HOUR) return false;
        await tx.query('UPDATE email_codes SET consumed_at = now() WHERE email = $1 AND consumed_at IS NULL', [email]);
        await tx.query(
          `INSERT INTO email_codes (email, code_hash, expires_at) VALUES ($1, $2, now() + ($3 || ' minutes')::interval)`,
          [email, hashCode(deps.config.pepper, email, code), String(CODE_TTL_MINUTES)],
        );
        await tx.query(`INSERT INTO audit_log (event, ip) VALUES ('email.start', $1::inet)`, [ip]);
        return true;
      });

      if (!stored) {
        request.log.info('email start over the limit');
        return {};
      }
      try {
        await deps.mail.send(codeMail(email, code));
      } catch (error) {
        request.log.error({ err: error }, 'code e-mail not sent');
      }
      return {};
    },
  });

  routes.route({
    method: 'POST',
    url: '/v1/auth/email/verify',
    schema: {
      tags: ['auth'],
      summary: 'Exchange the six-digit code for an Identity Platform custom token',
      body: EmailVerifyRequest,
      response: { 200: EmailVerifyResponse, 400: Problem, 410: Problem },
    },
    handler: async (request, reply) => {
      const email = normalizeEmail(request.body.email);
      const code = request.body.code.trim();
      if (!isPlausibleEmail(email) || !/^\d{6}$/.test(code)) {
        return reply.code(400).send({ error: 'code_invalid' });
      }

      const outcome = await transaction(deps.db, async (tx) => {
        const open = await tx.query<CodeRow>(
          `SELECT id, code_hash, attempts, expires_at FROM email_codes
           WHERE email = $1 AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1 FOR UPDATE`,
          [email],
        );
        const row = open.rows[0];
        if (!row) return 'invalid' as const;
        if (row.expires_at.getTime() <= Date.now()) {
          await tx.query('UPDATE email_codes SET consumed_at = now() WHERE id = $1', [row.id]);
          return 'gone' as const;
        }
        if (!hashesEqual(row.code_hash, hashCode(deps.config.pepper, email, code))) {
          const attempts = row.attempts + 1;
          if (attempts >= MAX_ATTEMPTS) {
            await tx.query('UPDATE email_codes SET attempts = $2, consumed_at = now() WHERE id = $1', [row.id, attempts]);
            return 'gone' as const;
          }
          await tx.query('UPDATE email_codes SET attempts = $2 WHERE id = $1', [row.id, attempts]);
          return 'invalid' as const;
        }
        await tx.query('UPDATE email_codes SET consumed_at = now() WHERE id = $1', [row.id]);
        return 'ok' as const;
      });

      if (outcome === 'invalid') return reply.code(400).send({ error: 'code_invalid' });
      if (outcome === 'gone') return reply.code(410).send({ error: 'code_expired_or_burned' });

      const uid = await findOrCreateUser(deps, email);
      const customToken = await deps.admin.createCustomToken(uid);
      const ip = clientIp(request, deps.config.environment);
      await deps.db.query(
        `INSERT INTO audit_log (user_id, event, ip) VALUES ((SELECT id FROM users WHERE firebase_uid = $1), 'signin.email', $2::inet)`,
        [uid, ip],
      );
      return { customToken };
    },
  });
}

async function findOrCreateUser(deps: Deps, email: string): Promise<string> {
  try {
    const existing = await deps.admin.getUserByEmail(email);
    return existing.uid;
  } catch (error) {
    if ((error as { code?: string }).code !== 'auth/user-not-found') throw error;
  }
  const created = await deps.admin.createUser({ email, emailVerified: true });
  return created.uid;
}
