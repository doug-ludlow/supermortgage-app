// Where the tests find Postgres and the Firebase Auth emulator. Overridable for CI.
export const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL ?? 'postgresql://app:app@127.0.0.1:5432/app_test';
export const EMULATOR_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';
export const PROJECT_ID = 'demo-supermortgage';
export const PEPPER = 'test-pepper-0123456789abcdef';
