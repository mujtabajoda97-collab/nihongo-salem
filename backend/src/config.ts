import type { PersonaKey, TtsProvider } from './types.ts';
import { PERSONA_KEYS } from './types.ts';
import { DEFAULT_OPENAI_VOICES } from './personas.ts';

export interface Config {
  port: number;
  host: string;
  anthropicApiKey: string;
  openaiApiKey: string;
  elevenlabsApiKey: string;
  anthropicModel: string;
  anthropicMaxTokens: number;
  whisperModel: string;
  openaiTtsModel: string;
  openaiVoices: Record<PersonaKey, string>;
  elevenlabsModel: string;
  /** Per-persona ElevenLabs voice ids; each falls back to ELEVENLABS_VOICE_ID. */
  elevenlabsVoices: Record<PersonaKey, string>;
  /** Used when the app does not send tts_provider. */
  defaultTtsProvider: TtsProvider;
  audioDelivery: 'url' | 'base64';
  /** e.g. https://my-app.onrender.com (needed behind some proxies for audio_url). */
  publicBaseUrl: string;
  /** If set, requests must send the header `x-app-key`. */
  appApiKey: string;
  rateLimitPerMinute: number;
  maxAudioBytes: number;
  maxTextChars: number;
  promptsDir: string;
  sessionTtlMs: number;
  maxHistoryMessages: number;
  audioTtlMs: number;
  llmTimeoutMs: number;
  sttTimeoutMs: number;
  ttsTimeoutMs: number;
  retryDelayMs: number;
  logLevel: string;
}

type Env = Record<string, string | undefined>;

function int(env: Env, key: string, fallback: number): number {
  const raw = env[key];
  if (raw === undefined || raw.trim() === '') return fallback;
  const n = Number.parseInt(raw, 10);
  if (!Number.isFinite(n) || n < 0) throw new Error(`${key} must be a non-negative integer`);
  return n;
}

function str(env: Env, key: string, fallback = ''): string {
  const v = env[key];
  return v === undefined || v.trim() === '' ? fallback : v.trim();
}

/** Reads and validates the environment. Throws one readable message listing every problem. */
export function loadConfig(env: Env = process.env, opts: { promptsDir?: string } = {}): Config {
  const problems: string[] = [];
  const anthropicApiKey = str(env, 'ANTHROPIC_API_KEY');
  const openaiApiKey = str(env, 'OPENAI_API_KEY');
  if (!anthropicApiKey) problems.push('ANTHROPIC_API_KEY is required (Claude replies)');
  if (!openaiApiKey) problems.push('OPENAI_API_KEY is required (Whisper speech-to-text)');

  const defaultTtsProvider = str(env, 'DEFAULT_TTS_PROVIDER', 'openai');
  if (defaultTtsProvider !== 'openai' && defaultTtsProvider !== 'elevenlabs') {
    problems.push('DEFAULT_TTS_PROVIDER must be "openai" or "elevenlabs"');
  }
  const audioDelivery = str(env, 'AUDIO_DELIVERY', 'url');
  if (audioDelivery !== 'url' && audioDelivery !== 'base64') {
    problems.push('AUDIO_DELIVERY must be "url" or "base64"');
  }
  if (problems.length > 0) {
    throw new Error(`Invalid configuration:\n - ${problems.join('\n - ')}`);
  }

  const openaiVoices = {} as Record<PersonaKey, string>;
  const elevenlabsVoices = {} as Record<PersonaKey, string>;
  const elevenDefault = str(env, 'ELEVENLABS_VOICE_ID');
  for (const key of PERSONA_KEYS) {
    const suffix = key.toUpperCase();
    openaiVoices[key] = str(env, `OPENAI_VOICE_${suffix}`, DEFAULT_OPENAI_VOICES[key]);
    elevenlabsVoices[key] = str(env, `ELEVENLABS_VOICE_${suffix}`, elevenDefault);
  }

  return {
    port: int(env, 'PORT', 8080),
    host: str(env, 'HOST', '0.0.0.0'),
    anthropicApiKey,
    openaiApiKey,
    elevenlabsApiKey: str(env, 'ELEVENLABS_API_KEY'),
    anthropicModel: str(env, 'ANTHROPIC_MODEL', 'claude-haiku-5-5'),
    anthropicMaxTokens: int(env, 'ANTHROPIC_MAX_TOKENS', 700),
    whisperModel: str(env, 'WHISPER_MODEL', 'whisper-1'),
    openaiTtsModel: str(env, 'OPENAI_TTS_MODEL', 'gpt-4o-mini-tts'),
    openaiVoices,
    elevenlabsModel: str(env, 'ELEVENLABS_MODEL', 'eleven_multilingual_v2'),
    elevenlabsVoices,
    defaultTtsProvider: defaultTtsProvider as TtsProvider,
    audioDelivery: audioDelivery as 'url' | 'base64',
    publicBaseUrl: str(env, 'PUBLIC_BASE_URL').replace(/\/+$/, ''),
    appApiKey: str(env, 'APP_API_KEY'),
    rateLimitPerMinute: int(env, 'RATE_LIMIT_PER_MINUTE', 40),
    maxAudioBytes: int(env, 'MAX_AUDIO_BYTES', 5 * 1024 * 1024),
    maxTextChars: int(env, 'MAX_TEXT_CHARS', 1000),
    promptsDir: opts.promptsDir ?? str(env, 'PROMPTS_DIR', 'prompts'),
    sessionTtlMs: int(env, 'SESSION_TTL_MINUTES', 120) * 60_000,
    maxHistoryMessages: int(env, 'MAX_HISTORY_MESSAGES', 24),
    audioTtlMs: int(env, 'AUDIO_TTL_MINUTES', 15) * 60_000,
    llmTimeoutMs: int(env, 'LLM_TIMEOUT_MS', 20_000),
    sttTimeoutMs: int(env, 'STT_TIMEOUT_MS', 15_000),
    ttsTimeoutMs: int(env, 'TTS_TIMEOUT_MS', 15_000),
    retryDelayMs: int(env, 'RETRY_DELAY_MS', 700),
    logLevel: str(env, 'LOG_LEVEL', 'info'),
  };
}
