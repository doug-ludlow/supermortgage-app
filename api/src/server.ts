import { randomUUID } from 'node:crypto';
import swagger from '@fastify/swagger';
import Fastify, { LogController, type FastifyError, type FastifyInstance } from 'fastify';
import {
  hasZodFastifySchemaValidationErrors,
  isResponseSerializationError,
  jsonSchemaTransform,
  jsonSchemaTransformObject,
  serializerCompiler,
  validatorCompiler,
  type ZodTypeProvider,
} from 'fastify-type-provider-zod';
import type { Auth } from 'firebase-admin/auth';
import type pg from 'pg';
import { z } from 'zod';
import { emailRoutes } from './auth/email.js';
import type { Config } from './config.js';
import { StubSender, extractCode, type MailSender } from './mail/sender.js';
import { meRoutes } from './me/routes.js';
import { Health, Problem, StubMail } from './schemas.js';

export interface Deps {
  config: Config;
  db: pg.Pool;
  admin: Auth;
  mail: MailSender;
}

// Fastify with zod schemas (validation, serialization and the OpenAPI document), structured JSON
// logs with request id, route, status and latency — never bodies or e-mail addresses.
export async function buildServer(deps: Deps): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: deps.config.logLevel,
      redact: { paths: ['req.headers.authorization', 'req.headers.cookie'], censor: '[redacted]' },
      serializers: {
        req: (req) => ({ id: req.id, method: req.method, url: req.url.split('?')[0] }),
        res: (res) => ({ statusCode: res.statusCode }),
      },
    },
    logController: new LogController({ disableRequestLogging: true }),
    bodyLimit: 16 * 1024,
    genReqId: (req) => {
      const trace = req.headers['x-cloud-trace-context'];
      const id = typeof trace === 'string' ? trace.split('/')[0] : undefined;
      return id && id.length > 0 ? id : randomUUID();
    },
  }).withTypeProvider<ZodTypeProvider>();

  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);

  app.addHook('onResponse', async (request, reply) => {
    request.log.info(
      {
        route: request.routeOptions.url ?? request.url.split('?')[0],
        method: request.method,
        status: reply.statusCode,
        ms: Math.round(reply.elapsedTime),
      },
      'request',
    );
  });

  app.setErrorHandler((error: FastifyError, request, reply) => {
    if (hasZodFastifySchemaValidationErrors(error)) {
      return reply.code(400).send({ error: 'bad_request' });
    }
    if (isResponseSerializationError(error)) {
      request.log.error({ err: error }, 'response did not match its schema');
      return reply.code(500).send({ error: 'internal' });
    }
    const status = typeof error.statusCode === 'number' ? error.statusCode : 500;
    if (status >= 500) {
      request.log.error({ err: error }, 'request failed');
      return reply.code(500).send({ error: 'internal' });
    }
    return reply.code(status).send({ error: 'bad_request' });
  });

  app.setNotFoundHandler((_request, reply) => reply.code(404).send({ error: 'not_found' }));

  await app.register(swagger, {
    openapi: {
      openapi: '3.1.0',
      info: {
        title: 'Supermortgage API',
        description: 'Accounts, households, agents and onboarding. Bearer tokens are Identity Platform ID tokens.',
        version: '1.0.0',
      },
      components: {
        securitySchemes: { bearer: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' } },
      },
    },
    transform: jsonSchemaTransform,
    transformObject: jsonSchemaTransformObject,
  });

  app.route({
    method: 'GET',
    url: '/health',
    schema: { tags: ['ops'], summary: 'Liveness and the database', response: { 200: Health, 503: Health } },
    handler: async (_request, reply) => {
      let db: 'ok' | 'error' = 'ok';
      try {
        await deps.db.query('SELECT 1');
      } catch {
        db = 'error';
      }
      return reply.code(db === 'ok' ? 200 : 503).send({ ok: db === 'ok', version: deps.config.version, db });
    },
  });

  await app.register(emailRoutes, deps);
  await app.register(meRoutes, deps);

  if (deps.config.mailStub && deps.mail instanceof StubSender) {
    const stub = deps.mail;
    app.route({
      method: 'GET',
      url: '/__stub/mail/last',
      schema: {
        hide: true,
        querystring: z.object({ to: z.string().min(1) }),
        response: { 200: StubMail, 404: Problem },
      },
      handler: async (request, reply) => {
        const mail = stub.last(request.query.to.trim().toLowerCase());
        if (!mail) return reply.code(404).send({ error: 'no_mail' });
        return { to: mail.to, subject: mail.subject, text: mail.text, code: extractCode(mail.text) ?? null };
      },
    });
  }

  return app;
}
