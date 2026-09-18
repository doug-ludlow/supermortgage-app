import { defineConfig } from 'vitest/config';

// The tests run against a real Postgres and the Firebase Auth emulator (see test/global-setup.ts),
// one file at a time so the shared database and emulator state stay deterministic.
export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    globalSetup: ['./test/global-setup.ts'],
    fileParallelism: false,
    testTimeout: 20_000,
    hookTimeout: 60_000,
  },
});
