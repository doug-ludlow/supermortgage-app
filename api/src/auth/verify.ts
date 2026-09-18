import type { FastifyReply, FastifyRequest } from 'fastify';
import type { Auth } from 'firebase-admin/auth';

// Bearer → verifyIdToken(token, checkRevoked) → project check → request.auth.
// A uid only ever comes from the verified token, never from a body.

export interface AuthContext {
  uid: string;
  email?: string;
  emailVerified: boolean;
  displayName?: string;
  /** `firebase.sign_in_provider`: apple.com, google.com or custom (the e-mail code). */
  signInProvider: string;
}

declare module 'fastify' {
  interface FastifyRequest {
    auth?: AuthContext;
  }
}

export function requireAuth(admin: Auth, projectId: string) {
  const issuer = `https://securetoken.google.com/${projectId}`;
  return async function verifyBearer(request: FastifyRequest, reply: FastifyReply): Promise<void> {
    const header = request.headers.authorization;
    if (typeof header !== 'string' || !header.startsWith('Bearer ')) {
      await reply.code(401).send({ error: 'unauthorized' });
      return;
    }
    const token = header.slice('Bearer '.length).trim();
    try {
      const decoded = await admin.verifyIdToken(token, true);
      if (decoded.aud !== projectId || decoded.iss !== issuer) {
        throw new Error('token is for another project');
      }
      request.auth = {
        uid: decoded.uid,
        email: decoded.email,
        emailVerified: decoded.email_verified === true,
        displayName: typeof decoded.name === 'string' ? decoded.name : undefined,
        signInProvider: decoded.firebase?.sign_in_provider ?? 'unknown',
      };
    } catch (error) {
      request.log.info({ reason: String((error as Error).message).slice(0, 120) }, 'bearer token rejected');
      await reply.code(401).send({ error: 'unauthorized' });
    }
  };
}
