import pg from 'pg';

// One pool per process. DATABASE_URL is either a TCP URL (local, tests) or the Cloud SQL socket
// form Terraform stores in Secret Manager: postgresql://api:…@/app?host=/cloudsql/<connection-name>
export function createPool(databaseUrl: string): pg.Pool {
  return new pg.Pool({ connectionString: databaseUrl, max: 5, idleTimeoutMillis: 30_000 });
}

export type Db = pg.Pool | pg.PoolClient;

/** Runs `body` in a transaction on a dedicated client; rolls back on any throw. */
export async function transaction<T>(pool: pg.Pool, body: (client: pg.PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await body(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}
