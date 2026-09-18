import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import {
  bearer,
  emulatorSignInWithIdp,
  emulatorSignUp,
  resetState,
  sleep,
  startApp,
  unsignedToken,
  type TestApp,
} from './helpers.js';

describe('/v1/me', () => {
  let t: TestApp;
  beforeAll(async () => {
    t = await startApp();
  });
  afterAll(async () => {
    await t.close();
  });
  beforeEach(async () => {
    await resetState(t.db);
  });

  const bootstrap = (idToken: string) => t.app.inject({ method: 'POST', url: '/v1/me/bootstrap', headers: bearer(idToken) });
  const me = (idToken: string) => t.app.inject({ method: 'GET', url: '/v1/me', headers: bearer(idToken) });

  it('bootstrap is idempotent: one user, one household, one agent, one onboarding row', async () => {
    const { idToken, uid } = await emulatorSignInWithIdp('google.com', 'google-sub-1', 'g@example.com');
    const first = await bootstrap(idToken);
    expect(first.statusCode).toBe(200);
    const a = first.json();
    expect(a.user.email).toBe('g@example.com');
    expect(a.user.providers).toEqual(['google']);
    expect(a.user.signedInWith).toBe('google');
    expect(a.household.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(a.onboarding).toEqual({ stage: 'know', completedAt: null });

    const second = await bootstrap(idToken);
    expect(second.statusCode).toBe(200);
    const b = second.json();
    expect(b.user.id).toBe(a.user.id);
    expect(b.household.id).toBe(a.household.id);
    const counts = await t.db.query(
      `SELECT (SELECT count(*) FROM users)::int AS users, (SELECT count(*) FROM households)::int AS households,
              (SELECT count(*) FROM household_members)::int AS members, (SELECT count(*) FROM agents)::int AS agents,
              (SELECT count(*) FROM onboarding)::int AS onboarding`,
    );
    expect(counts.rows[0]).toEqual({ users: 1, households: 1, members: 1, agents: 1, onboarding: 1 });
    const row = await t.db.query('SELECT firebase_uid FROM users');
    expect(row.rows[0].firebase_uid).toBe(uid);
  });

  it('Apple sign-ins land with the apple provider', async () => {
    const { idToken } = await emulatorSignInWithIdp('apple.com', 'apple-sub-1', 'relay@privaterelay.appleid.com');
    const res = await bootstrap(idToken);
    expect(res.statusCode).toBe(200);
    expect(res.json().user.providers).toEqual(['apple']);
    expect(res.json().user.signedInWith).toBe('apple');
    expect(res.json().user.email).toBe('relay@privaterelay.appleid.com');
  });

  it('GET /v1/me is 404 until bootstrap, then the same shape', async () => {
    const { idToken } = await emulatorSignUp('fresh@example.com');
    expect((await me(idToken)).statusCode).toBe(404);
    expect((await me(idToken)).json()).toEqual({ error: 'not_bootstrapped' });
    const created = await bootstrap(idToken);
    const read = await me(idToken);
    expect(read.statusCode).toBe(200);
    expect(read.json()).toEqual(created.json());
  });

  it('names the agent (1–24 characters, trimmed) and completes onboarding', async () => {
    const { idToken } = await emulatorSignUp('name@example.com');
    await bootstrap(idToken);
    const patch = (name: unknown) => t.app.inject({ method: 'PATCH', url: '/v1/me/agent', headers: bearer(idToken), payload: { name } });
    expect((await patch('')).statusCode).toBe(400);
    expect((await patch('   ')).statusCode).toBe(400);
    expect((await patch('x'.repeat(25))).statusCode).toBe(400);
    expect((await patch(42)).statusCode).toBe(400);
    const ok = await patch('  Hazel  ');
    expect(ok.statusCode).toBe(200);
    expect(ok.json().agent.name).toBe('Hazel');
    expect(ok.json().agent.namedAt).toMatch(/^\d{4}-/);
    expect(ok.json().onboarding.completedAt).toMatch(/^\d{4}-/);
    const renamed = await patch('Reed');
    expect(renamed.json().agent.name).toBe('Reed');
    expect(renamed.json().onboarding.completedAt).toBe(ok.json().onboarding.completedAt);
  });

  it('records the onboarding stage', async () => {
    const { idToken } = await emulatorSignUp('stage@example.com');
    await bootstrap(idToken);
    const patch = (stage: string) => t.app.inject({ method: 'PATCH', url: '/v1/me/onboarding', headers: bearer(idToken), payload: { stage } });
    expect((await patch('setup')).json().onboarding.stage).toBe('setup');
    expect((await patch('chat')).json().onboarding.stage).toBe('chat');
    expect((await patch('done')).statusCode).toBe(400);
  });

  it('deletes the account: rows gone, user soft-deleted without PII, Identity Platform user gone', async () => {
    const { idToken, uid } = await emulatorSignUp('bye@example.com');
    await bootstrap(idToken);
    await t.app.inject({ method: 'PATCH', url: '/v1/me/agent', headers: bearer(idToken), payload: { name: 'Hazel' } });
    await t.app.inject({ method: 'POST', url: '/v1/auth/email/start', payload: { email: 'bye@example.com' } });

    const res = await t.app.inject({ method: 'DELETE', url: '/v1/me', headers: bearer(idToken) });
    expect(res.statusCode).toBe(204);
    const counts = await t.db.query(
      `SELECT (SELECT count(*) FROM households)::int AS households, (SELECT count(*) FROM household_members)::int AS members,
              (SELECT count(*) FROM agents)::int AS agents, (SELECT count(*) FROM onboarding)::int AS onboarding,
              (SELECT count(*) FROM email_codes)::int AS codes`,
    );
    expect(counts.rows[0]).toEqual({ households: 0, members: 0, agents: 0, onboarding: 0, codes: 0 });
    const user = await t.db.query('SELECT email, display_name, providers, deleted_at FROM users WHERE firebase_uid = $1', [uid]);
    expect(user.rows[0].email).toBeNull();
    expect(user.rows[0].display_name).toBeNull();
    expect(user.rows[0].providers).toEqual([]);
    expect(user.rows[0].deleted_at).not.toBeNull();
    await expect(t.admin.getUser(uid)).rejects.toMatchObject({ code: 'auth/user-not-found' });
    // The old token no longer opens anything.
    expect((await me(idToken)).statusCode).toBe(401);
    const audit = await t.db.query(`SELECT event FROM audit_log WHERE event = 'me.delete'`);
    expect(audit.rows).toHaveLength(1);
  });

  it('answers 401 for missing, malformed, wrong-project and revoked tokens', async () => {
    expect((await t.app.inject({ method: 'GET', url: '/v1/me' })).statusCode).toBe(401);
    expect((await t.app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: 'Basic abc' } })).statusCode).toBe(401);
    expect((await me('not.a.jwt')).statusCode).toBe(401);
    const otherProject = unsignedToken({
      aud: 'other-project',
      iss: 'https://securetoken.google.com/other-project',
      sub: 'someone',
      user_id: 'someone',
      firebase: { sign_in_provider: 'custom', identities: {} },
    });
    expect((await me(otherProject)).statusCode).toBe(401);

    const { idToken, uid } = await emulatorSignUp('revoked@example.com');
    expect((await bootstrap(idToken)).statusCode).toBe(200);
    await sleep(1100); // tokensValidAfterTime has one-second resolution
    await t.admin.revokeRefreshTokens(uid);
    expect((await me(idToken)).statusCode).toBe(401);
    expect((await me(idToken)).json()).toEqual({ error: 'unauthorized' });
  });
});
