import { timingSafeEqual } from 'node:crypto';
import multipart from '@fastify/multipart';
import rateLimit from '@fastify/rate-limit';
import Fastify from 'fastify';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { AudioStore } from './audioStore.ts';
import type { Config } from './config.ts';
import { UpstreamError } from './http.ts';
import type { Prompts } from './prompts.ts';
import { SessionStore } from './sessions.ts';
import { RequestError, runTurn, validateRequest } from './turn.ts';

function sameSecret(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

function baseUrlOf(cfg: Config, req: FastifyRequest): string {
  if (cfg.publicBaseUrl) return cfg.publicBaseUrl;
  return `${req.protocol}://${req.host}`;
}

export interface AppDeps {
  cfg: Config;
  prompts: Prompts;
  sessions?: SessionStore;
  audio?: AudioStore;
}

/** The HTTP layer: auth, rate limit, multipart parsing. The real work is in turn.ts. */
export async function buildApp(deps: AppDeps): Promise<FastifyInstance> {
  const { cfg, prompts } = deps;
  const sessions = deps.sessions ?? new SessionStore(cfg.sessionTtlMs, cfg.maxHistoryMessages);
  const audio = deps.audio ?? new AudioStore(cfg.audioTtlMs);

  const app = Fastify({
    logger: { level: cfg.logLevel },
    trustProxy: true, // Render / Cloud Run / Fly put a proxy in front
    bodyLimit: 256 * 1024,
  });

  await app.register(rateLimit, { max: cfg.rateLimitPerMinute, timeWindow: '1 minute' });
  await app.register(multipart, {
    limits: { fileSize: cfg.maxAudioBytes, files: 1, fields: 4, parts: 6 },
  });

  app.get('/health', { config: { rateLimit: false } }, async () => ({ ok: true }));

  // Generated speech (unguessable id, expires after AUDIO_TTL_MINUTES).
  app.get<{ Params: { file: string } }>('/v1/audio/:file', async (req, reply) => {
    const id = req.params.file.replace(/\.mp3$/, '');
    const item = /^[0-9a-f]{32}$/.test(id) ? audio.get(id) : undefined;
    if (!item) return reply.code(404).send({ error: 'not_found' });
    return reply
      .header('content-type', item.mime)
      .header('cache-control', 'private, max-age=600')
      .send(Buffer.from(item.data));
  });

  app.post('/v1/turn', async (req, reply) => {
    if (cfg.appApiKey) {
      const sent = req.headers['x-app-key'];
      if (typeof sent !== 'string' || !sameSecret(sent, cfg.appApiKey)) {
        return reply.code(401).send({ error: 'unauthorized' });
      }
    }

    let payload: unknown;
    let audioBytes: Uint8Array | undefined;
    if (req.isMultipart()) {
      let payloadText = '';
      for await (const part of req.parts()) {
        if (part.type === 'file') {
          if (part.fieldname === 'audio') audioBytes = await part.toBuffer();
          else await part.toBuffer(); // drain unknown files
        } else if (part.fieldname === 'payload' && typeof part.value === 'string') {
          payloadText = part.value;
        }
      }
      try {
        payload = JSON.parse(payloadText);
      } catch {
        throw new RequestError(400, 'bad_payload', 'multipart field "payload" must be JSON');
      }
    } else {
      payload = req.body;
    }

    const request = validateRequest(payload, cfg, audioBytes);
    return runTurn(
      { cfg, prompts, sessions, audio, baseUrl: baseUrlOf(cfg, req), log: (m) => req.log.warn(m) },
      request,
    );
  });

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof RequestError) {
      return reply.code(err.status).send({ error: err.code, message: err.message });
    }
    if (err instanceof UpstreamError) {
      req.log.error({ service: err.service, status: err.status }, err.message);
      return reply.code(502).send({
        error: `${err.service}_failed`,
        message_ar: 'تعذّر الحصول على رد من المعلم الآن. حاول مرة أخرى.',
      });
    }
    const status = (err as { statusCode?: number }).statusCode;
    if (typeof status === 'number' && status >= 400 && status < 500) {
      return reply.code(status).send({ error: (err as { code?: string }).code ?? 'bad_request', message: err.message });
    }
    req.log.error(err);
    return reply.code(500).send({ error: 'internal_error' });
  });

  return app;
}
