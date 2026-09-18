import { createHash, randomInt, timingSafeEqual } from 'node:crypto';

// The six-digit e-mail code: normalization, generation, hashing and a constant-time compare.

/** trim, NFKC, lowercase — the same address always maps to the same row. */
export function normalizeEmail(raw: string): string {
  return raw.trim().normalize('NFKC').toLowerCase();
}

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function isPlausibleEmail(email: string): boolean {
  return email.length <= 254 && EMAIL.test(email);
}

/** Six digits from a CSPRNG (`randomInt` draws from `randomBytes`), zero-padded. */
export function generateCode(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, '0');
}

export function hashCode(pepper: string, email: string, code: string): string {
  return createHash('sha256').update(`${pepper}${email}${code}`).digest('hex');
}

export function hashesEqual(a: string, b: string): boolean {
  const left = Buffer.from(a, 'utf8');
  const right = Buffer.from(b, 'utf8');
  return left.length === right.length && timingSafeEqual(left, right);
}

export const CODE_TTL_MINUTES = 10;
export const MAX_ATTEMPTS = 5;
export const STARTS_PER_EMAIL_PER_HOUR = 5;
export const STARTS_PER_IP_PER_HOUR = 20;
