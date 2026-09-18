import { migrate } from '../src/db/migrate.js';
import { createPool } from '../src/db/pool.js';
import { EMULATOR_HOST, TEST_DATABASE_URL } from './env.js';

// Once per test run: a fresh schema in the test database, and a check that the emulator is up.
export default async function setup(): Promise<void> {
  const pool = createPool(TEST_DATABASE_URL);
  try {
    await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
    await migrate(pool);
  } finally {
    await pool.end();
  }
  const probe = await fetch(`http://${EMULATOR_HOST}/`).catch(() => undefined);
  if (!probe) {
    throw new Error(`Firebase Auth emulator not reachable at ${EMULATOR_HOST} — run \`npm run emulator\``);
  }
}
