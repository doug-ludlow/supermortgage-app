import type { FastifyInstance } from 'fastify';
import type { Auth } from 'firebase-admin/auth';
import type pg from 'pg';
import { createAdminAuth } from '../src/auth/firebase.js';
import type { Config } from '../src/config.js';
import { createPool } from '../src/db/pool.js';
import { StubSender } from '../src/mail/sender.js';
import { buildServer } from '../src/server.js';
import { EMULATOR_HOST, PEPPER, PROJECT_ID, TEST_DATABASE_URL } from './env.js';

export interface TestApp {
  app: FastifyInstance;
  db: pg.Pool;
  admin: Auth;
  stub: StubSender;
  close(): Promise<void>;
}

export const testConfig: Config = {
  port: 0,
  databaseUrl: TEST_DATABASE_URL,
  projectId: PROJECT_ID,
  environment: 'test',
  mailFrom: 'Supermortgage <code@mail.supermortgage.com>',
  mailStub: true,
  pepper: PEPPER,
  authEmulatorHost: EMULATOR_HOST,
  logLevel: 'silent',
  version: 'test',
};

export async function startApp(): Promise<TestApp> {
  process.env.FIREBASE_AUTH_EMULATOR_HOST = EMULATOR_HOST;
  const db = createPool(TEST_DATABASE_URL);
  const admin = createAdminAuth(PROJECT_ID);
  const stub = new StubSender(() => undefined);
  const app = await buildServer({ config: testConfig, db, admin, mail: stub });
  await app.ready();
  return {
    app,
    db,
    admin,
    stub,
    close: async () => {
      await app.close();
      await db.end();
    },
  };
}

/** Empties every table and every emulator account. */
export async function resetState(db: pg.Pool): Promise<void> {
  await db.query('TRUNCATE audit_log, email_codes, onboarding, agents, household_members, households, users RESTART IDENTITY CASCADE');
  const response = await fetch(`http://${EMULATOR_HOST}/emulator/v1/projects/${PROJECT_ID}/accounts`, { method: 'DELETE' });
  if (!response.ok) throw new Error(`emulator reset failed: ${response.status}`);
}

const IDENTITY = `http://${EMULATOR_HOST}/identitytoolkit.googleapis.com/v1`;

async function identity<T>(method: string, body: Record<string, unknown>): Promise<T> {
  const response = await fetch(`${IDENTITY}/${method}?key=fake-api-key`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json = (await response.json()) as T & { error?: { message?: string } };
  if (!response.ok) throw new Error(`emulator ${method}: ${json.error?.message ?? response.status}`);
  return json;
}

/** An e-mail+password user in the emulator (the provider is disabled in the cloud; fine for tests). */
export async function emulatorSignUp(email: string): Promise<{ idToken: string; uid: string }> {
  const r = await identity<{ idToken: string; localId: string }>('accounts:signUp', {
    email,
    password: 'correct-horse-battery',
    returnSecureToken: true,
  });
  return { idToken: r.idToken, uid: r.localId };
}

/** A federated sign-in the emulator accepts without a real IdP: an unsigned JSON id_token. */
export async function emulatorSignInWithIdp(
  providerId: 'google.com' | 'apple.com',
  sub: string,
  email: string,
): Promise<{ idToken: string; uid: string }> {
  const idToken = JSON.stringify({ sub, email, email_verified: true });
  const r = await identity<{ idToken: string; localId: string }>('accounts:signInWithIdp', {
    postBody: `id_token=${encodeURIComponent(idToken)}&providerId=${providerId}`,
    requestUri: 'http://localhost',
    returnSecureToken: true,
    returnIdpCredential: true,
  });
  return { idToken: r.idToken, uid: r.localId };
}

export async function emulatorSignInWithCustomToken(token: string): Promise<{ idToken: string; uid: string }> {
  const r = await identity<{ idToken: string; localId?: string }>('accounts:signInWithCustomToken', {
    token,
    returnSecureToken: true,
  });
  const payload = JSON.parse(Buffer.from(r.idToken.split('.')[1] ?? '', 'base64url').toString('utf8')) as { user_id?: string; sub?: string };
  return { idToken: r.idToken, uid: r.localId ?? payload.user_id ?? payload.sub ?? '' };
}

/** An unsigned JWT with arbitrary claims — the emulator's own tokens are unsigned too. */
export function unsignedToken(claims: Record<string, unknown>): string {
  const encode = (obj: unknown) => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({ iat: now, exp: now + 3600, auth_time: now, ...claims })}.`;
}

export function bearer(idToken: string): Record<string, string> {
  return { authorization: `Bearer ${idToken}` };
}

export const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
