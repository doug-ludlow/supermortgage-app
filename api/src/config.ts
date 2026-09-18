import { z } from 'zod';

// Everything the API reads from its environment, validated once at start.
// Cloud Run sets PORT and K_REVISION; Terraform sets the rest (infra/terraform/run.tf).
const Env = z.object({
  PORT: z.coerce.number().int().positive().default(8080),
  DATABASE_URL: z.string().min(1),
  GOOGLE_CLOUD_PROJECT: z.string().min(1),
  ENVIRONMENT: z.string().min(1).default('local'),
  MAIL_FROM: z.string().min(1).default('Supermortgage <code@mail.supermortgage.com>'),
  EMAIL_API_KEY: z.string().optional(),
  MAIL_STUB: z.string().optional(),
  EMAIL_CODE_PEPPER: z.string().min(16),
  FIREBASE_AUTH_EMULATOR_HOST: z.string().optional(),
  LOG_LEVEL: z.string().default('info'),
  K_REVISION: z.string().optional(),
  npm_package_version: z.string().optional(),
});

export interface Config {
  port: number;
  databaseUrl: string;
  projectId: string;
  environment: string;
  mailFrom: string;
  emailApiKey?: string;
  /** MAIL_STUB=1: log the code instead of sending it, and keep an outbox for tests. Never in prod. */
  mailStub: boolean;
  pepper: string;
  authEmulatorHost?: string;
  logLevel: string;
  /** The Cloud Run revision, or the package version locally. */
  version: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const e = Env.parse(env);
  const mailStub = e.MAIL_STUB === '1' || e.MAIL_STUB === 'true';
  if (mailStub && e.ENVIRONMENT === 'prod') {
    throw new Error('MAIL_STUB is not allowed in prod');
  }
  if (!mailStub && !e.EMAIL_API_KEY) {
    throw new Error('EMAIL_API_KEY is required unless MAIL_STUB=1');
  }
  return {
    port: e.PORT,
    databaseUrl: e.DATABASE_URL,
    projectId: e.GOOGLE_CLOUD_PROJECT,
    environment: e.ENVIRONMENT,
    mailFrom: e.MAIL_FROM,
    emailApiKey: e.EMAIL_API_KEY,
    mailStub,
    pepper: e.EMAIL_CODE_PEPPER,
    authEmulatorHost: e.FIREBASE_AUTH_EMULATOR_HOST,
    logLevel: e.LOG_LEVEL,
    version: e.K_REVISION ?? e.npm_package_version ?? 'dev',
  };
}
