import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { Auth } from 'firebase-admin/auth';
import type pg from 'pg';
import { stringify } from 'yaml';
import { StubSender } from '../mail/sender.js';
import { buildServer } from '../server.js';

// Writes api/openapi.yaml from the route schemas. Runs at build (`npm run build`) and on demand
// (`npm run openapi`); the iOS types are generated from the result (gen-swift.ts).
const target = fileURLToPath(new URL('../../openapi.yaml', import.meta.url));

const app = await buildServer({
  config: {
    port: 0,
    databaseUrl: 'postgresql://unused',
    projectId: 'spec',
    environment: 'spec',
    mailFrom: 'unused',
    mailStub: false,
    pepper: 'unused-unused-unused',
    logLevel: 'silent',
    version: 'spec',
  },
  db: {} as pg.Pool,
  admin: {} as Auth,
  mail: new StubSender(() => undefined),
});
await app.ready();
const document = app.swagger();
writeFileSync(target, `# Generated from the route schemas by src/tools/openapi-write.ts. Do not edit.\n${stringify(document, { lineWidth: 0 })}`);
await app.close();
console.log(`wrote ${target}`);
