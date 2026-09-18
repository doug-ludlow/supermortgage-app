import type { FastifyRequest } from 'fastify';

// The client address for the per-IP limit and the audit log. Behind the Google load balancer the
// X-Forwarded-For header ends "<client>, <load balancer>", so the client is the second-to-last
// entry; anything the client itself sent sits before that and is ignored. Locally: the socket.
export function clientIp(request: FastifyRequest, environment: string): string {
  if (environment !== 'local' && environment !== 'test') {
    const header = request.headers['x-forwarded-for'];
    const raw = Array.isArray(header) ? header.join(',') : header;
    if (raw) {
      const parts = raw
        .split(',')
        .map((p) => p.trim())
        .filter(Boolean);
      const client = parts.length >= 2 ? parts[parts.length - 2] : parts[0];
      if (client && isIp(client)) return client;
    }
  }
  return isIp(request.ip) ? request.ip : '0.0.0.0';
}

function isIp(value: string): boolean {
  return /^(\d{1,3}\.){3}\d{1,3}$/.test(value) || /^[0-9a-f:]+$/i.test(value);
}
