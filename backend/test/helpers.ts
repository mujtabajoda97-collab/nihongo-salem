import { loadConfig } from '../src/config.ts';
import type { Config } from '../src/config.ts';
import { AudioStore } from '../src/audioStore.ts';
import { loadPrompts } from '../src/prompts.ts';
import { SessionStore } from '../src/sessions.ts';
import type { TurnDeps } from '../src/turn.ts';
import type { AiTurn } from '../src/types.ts';

export function makeConfig(extra: Record<string, string> = {}): Config {
  return loadConfig(
    {
      ANTHROPIC_API_KEY: 'sk-ant-test',
      OPENAI_API_KEY: 'sk-openai-test',
      RETRY_DELAY_MS: '1',
      ...extra,
    },
    { promptsDir: new URL('../prompts', import.meta.url).pathname },
  );
}

export function makeDeps(cfg: Config = makeConfig()): TurnDeps & { sessions: SessionStore; audio: AudioStore } {
  return {
    cfg,
    prompts: loadPrompts(cfg.promptsDir),
    sessions: new SessionStore(cfg.sessionTtlMs, cfg.maxHistoryMessages),
    audio: new AudioStore(cfg.audioTtlMs),
    baseUrl: 'https://api.test',
  };
}

export const aiTurn = (over: Partial<AiTurn> = {}): AiTurn => ({
  correction_ar: 'أحسنت!',
  reply_japanese: 'そうですか。',
  reply_romaji: 'Sō desu ka.',
  reply_arabic: 'حقاً؟',
  emotion_tone: 'happy',
  has_mistake: false,
  conversation_completed: false,
  ...over,
});

export interface Call {
  url: string;
  init: RequestInit;
  json?: any;
  form?: FormData;
}

type Handler = (call: Call) => Response | Promise<Response>;

/** Replaces global fetch with a router. Returns the recorded calls and a restore function. */
export function mockFetch(handler: Handler): { calls: Call[]; restore: () => void } {
  const original = globalThis.fetch;
  const calls: Call[] = [];
  globalThis.fetch = (async (input: any, init: RequestInit = {}) => {
    const call: Call = { url: String(input), init };
    if (typeof init.body === 'string') call.json = JSON.parse(init.body);
    if (init.body instanceof FormData) call.form = init.body;
    calls.push(call);
    return handler(call);
  }) as typeof fetch;
  return { calls, restore: () => (globalThis.fetch = original) };
}

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

export const claudeReply = (turn: unknown) =>
  json({ content: [{ type: 'text', text: typeof turn === 'string' ? turn : JSON.stringify(turn) }] });

export const mp3 = () =>
  new Response(new Uint8Array([0x49, 0x44, 0x33, 1, 2, 3]), { headers: { 'content-type': 'audio/mpeg' } });

/** Standard fake: Whisper -> text, Claude -> turn, TTS -> mp3. */
export function standardRoutes(opts: { transcript?: string; turn?: unknown } = {}): Handler {
  return (c) => {
    if (c.url.includes('/audio/transcriptions')) return json({ text: opts.transcript ?? 'こんにちは' });
    if (c.url.includes('api.anthropic.com')) return claudeReply(opts.turn ?? aiTurn());
    if (c.url.includes('/audio/speech') || c.url.includes('elevenlabs.io')) return mp3();
    return new Response('unexpected', { status: 500 });
  };
}
