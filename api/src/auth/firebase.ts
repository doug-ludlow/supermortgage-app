import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth, type Auth } from 'firebase-admin/auth';

// The Admin SDK. On Cloud Run it signs custom tokens through IAM with the service's own account
// (roles/iam.serviceAccountTokenCreator on itself); against the emulator
// (FIREBASE_AUTH_EMULATOR_HOST) tokens are unsigned and no credentials are needed.
export function createAdminAuth(projectId: string): Auth {
  const app = getApps()[0] ?? initializeApp({ projectId });
  return getAuth(app);
}

/** Identity Platform's provider ids → the three doors. */
export function doorForProvider(providerId: string): 'apple' | 'google' | 'email' | undefined {
  switch (providerId) {
    case 'apple.com':
      return 'apple';
    case 'google.com':
      return 'google';
    case 'custom':
    case 'password':
    case 'emailLink':
      return 'email';
    default:
      return undefined;
  }
}
