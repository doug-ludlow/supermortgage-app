import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { extractCode } from '../src/mail/sender.js';
import { bearer, emulatorSignInWithCustomToken, resetState, startApp, type TestApp } from './helpers.js';

const start = (t: TestApp, email: string, remoteAddress = '127.0.0.1') =>
  t.app.inject({ method: 'POST', url: '/v1/auth/email/start', payload: { email }, remoteAddress });
const verify = (t: TestApp, email: string, code: string) =>
  t.app.inject({ method: 'POST', url: '/v1/auth/email/verify', payload: { email, code } });
const lastCode = (t: TestApp, email: string) => extractCode(t.stub.last(email)?.text ?? '') ?? '';

describe('the e-mail door', () => {
  let t: TestApp;
  beforeAll(async () => {
    t = await startApp();
  });
  afterAll(async () => {
    await t.close();
  });
  beforeEach(async () => {
    await resetState(t.db);
    t.stub.outbox.length = 0;
  });

  it('start → verify → custom token → bootstrap: the account exists with the e-mail provider', async () => {
    const res = await start(t, '  Doug@Example.com ');
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({});
    const mail = t.stub.last('doug@example.com');
    expect(mail?.subject).toBe('Your Supermortgage code');
    const code = extractCode(mail?.text ?? '');
    expect(code).toMatch(/^\d{6}$/);
    expect(mail?.text).toBe(`Your Supermortgage code is ${code}. It expires in 10 minutes. If you didn’t ask for it, ignore this e-mail.`);

    const ok = await verify(t, 'doug@example.com', code as string);
    expect(ok.statusCode).toBe(200);
    const { customToken } = ok.json() as { customToken: string };
    expect(customToken).toBeTruthy();

    const session = await emulatorSignInWithCustomToken(customToken);
    const me = await t.app.inject({ method: 'POST', url: '/v1/me/bootstrap', headers: bearer(session.idToken) });
    expect(me.statusCode).toBe(200);
    const body = me.json();
    expect(body.user.email).toBe('doug@example.com');
    expect(body.user.emailVerified).toBe(true);
    expect(body.user.providers).toEqual(['email']);
    expect(body.user.signedInWith).toBe('email');
    expect(body.agent).toEqual({ name: null, namedAt: null });
    expect(body.onboarding).toEqual({ stage: 'know', completedAt: null });

    const codes = await t.db.query('SELECT consumed_at FROM email_codes');
    expect(codes.rows).toHaveLength(1);
    expect(codes.rows[0].consumed_at).not.toBeNull();
    const audit = await t.db.query(`SELECT event FROM audit_log ORDER BY created_at`);
    expect(audit.rows.map((r) => r.event)).toEqual(['email.start', 'signin.email', 'me.bootstrap']);

    // The same address again is the same account.
    await start(t, 'doug@example.com');
    const again = await verify(t, 'doug@example.com', lastCode(t, 'doug@example.com'));
    const session2 = await emulatorSignInWithCustomToken((again.json() as { customToken: string }).customToken);
    expect(session2.uid).toBe(session.uid);
  });

  it('a wrong code is 400 and the fifth miss burns the code', async () => {
    await start(t, 'five@example.com');
    const code = lastCode(t, 'five@example.com');
    const wrong = code === '000000' ? '000001' : '000000';
    for (let i = 1; i <= 4; i += 1) {
      const res = await verify(t, 'five@example.com', wrong);
      expect(res.statusCode).toBe(400);
      expect(res.json()).toEqual({ error: 'code_invalid' });
      const row = await t.db.query('SELECT attempts, consumed_at FROM email_codes');
      expect(row.rows[0].attempts).toBe(i);
      expect(row.rows[0].consumed_at).toBeNull();
    }
    const fifth = await verify(t, 'five@example.com', wrong);
    expect(fifth.statusCode).toBe(410);
    expect(fifth.json()).toEqual({ error: 'code_expired_or_burned' });
    // Even the right code is useless now.
    const right = await verify(t, 'five@example.com', code);
    expect(right.statusCode).toBe(400);
  });

  it('an expired code is 410', async () => {
    await start(t, 'late@example.com');
    const code = lastCode(t, 'late@example.com');
    await t.db.query(`UPDATE email_codes SET expires_at = now() - interval '1 second'`);
    const res = await verify(t, 'late@example.com', code);
    expect(res.statusCode).toBe(410);
    expect(res.json()).toEqual({ error: 'code_expired_or_burned' });
  });

  it('a new start invalidates the earlier code', async () => {
    await start(t, 'twice@example.com');
    const first = lastCode(t, 'twice@example.com');
    await start(t, 'twice@example.com');
    const second = lastCode(t, 'twice@example.com');
    expect(second).not.toBe(first);
    expect((await verify(t, 'twice@example.com', first)).statusCode).toBe(400);
    expect((await verify(t, 'twice@example.com', second)).statusCode).toBe(200);
  });

  it('rejects malformed codes and addresses without touching the database', async () => {
    expect((await verify(t, 'x@example.com', '12ab')).statusCode).toBe(400);
    expect((await verify(t, 'not-an-address', '123456')).statusCode).toBe(400);
    expect((await start(t, 'not-an-address')).statusCode).toBe(200);
    const rows = await t.db.query('SELECT count(*)::int AS n FROM email_codes');
    expect(rows.rows[0].n).toBe(0);
    expect((await t.app.inject({ method: 'POST', url: '/v1/auth/email/start', payload: {} })).statusCode).toBe(400);
  });

  it('limits starts to 5 per address per hour, still answering 200', async () => {
    for (let i = 0; i < 5; i += 1) {
      expect((await start(t, 'busy@example.com')).statusCode).toBe(200);
    }
    expect(t.stub.outbox.filter((m) => m.to === 'busy@example.com')).toHaveLength(5);
    const sixth = await start(t, 'busy@example.com');
    expect(sixth.statusCode).toBe(200);
    expect(sixth.json()).toEqual({});
    expect(t.stub.outbox.filter((m) => m.to === 'busy@example.com')).toHaveLength(5);
    expect((await t.db.query('SELECT count(*)::int AS n FROM email_codes')).rows[0].n).toBe(5);
  });

  it('limits starts to 20 per IP per hour, still answering 200', async () => {
    for (let i = 0; i < 20; i += 1) {
      expect((await start(t, `person${i}@example.com`, '203.0.113.9')).statusCode).toBe(200);
    }
    expect(t.stub.outbox).toHaveLength(20);
    const over = await start(t, 'person21@example.com', '203.0.113.9');
    expect(over.statusCode).toBe(200);
    expect(over.json()).toEqual({});
    expect(t.stub.outbox).toHaveLength(20);
    // Another address from another IP still works.
    expect((await start(t, 'elsewhere@example.com', '198.51.100.4')).statusCode).toBe(200);
    expect(t.stub.outbox).toHaveLength(21);
  });

  it('never reveals whether an address exists', async () => {
    await start(t, 'known@example.com');
    const code = lastCode(t, 'known@example.com');
    const ok = await verify(t, 'known@example.com', code);
    await emulatorSignInWithCustomToken((ok.json() as { customToken: string }).customToken);

    const known = await start(t, 'known@example.com');
    const unknown = await start(t, 'unknown@example.com');
    expect(known.statusCode).toBe(unknown.statusCode);
    expect(known.body).toBe(unknown.body);
    const knownWrong = await verify(t, 'known@example.com', '000000');
    const unknownWrong = await verify(t, 'nobody@example.com', '000000');
    expect(knownWrong.body).toBe(unknownWrong.body);
    expect(knownWrong.statusCode).toBe(unknownWrong.statusCode);
  });
});
