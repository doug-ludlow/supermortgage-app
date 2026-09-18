import { createAdminAuth } from './auth/firebase.js';
import { loadConfig } from './config.js';
import { migrate } from './db/migrate.js';
import { createPool } from './db/pool.js';
import { ResendSender, StubSender } from './mail/sender.js';
import { buildServer } from './server.js';

// Start: config → migrations (under an advisory lock) → Admin SDK → the server.
const config = loadConfig();
const db = createPool(config.databaseUrl);
const applied = await migrate(db);
const admin = createAdminAuth(config.projectId);
const mail = config.mailStub
  ? new StubSender((fields, msg) =>
      process.stdout.write(`${JSON.stringify({ level: 30, time: Date.now(), msg, ...fields })}\n`),
    )
  : new ResendSender(config.emailApiKey as string, config.mailFrom);

const app = await buildServer({ config, db, admin, mail });
app.log.info({ applied, environment: config.environment, mailStub: config.mailStub, emulator: config.authEmulatorHost ?? null }, 'starting');
await app.listen({ port: config.port, host: '0.0.0.0' });

const shutdown = async (signal: string) => {
  app.log.info({ signal }, 'stopping');
  await app.close();
  await db.end();
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
