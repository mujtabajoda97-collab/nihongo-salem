import type { Config } from '../config.ts';
import { fetchWithRetry } from '../http.ts';
import { ELEVEN_SETTINGS, openAiInstructions } from '../personas.ts';
import type { Emotion, PersonaKey, TtsProvider } from '../types.ts';

export interface Speech {
  data: Uint8Array;
  mime: string;
  provider: TtsProvider;
}

/** Text-to-speech reads symbols aloud or stumbles on them: keep letters, numbers and Japanese punctuation. */
export function cleanForSpeech(text: string): string {
  return text
    .replace(/[\p{Extended_Pictographic}️‍]/gu, '')
    .replace(/[()（）\[\]【】「」『』<>*_#~〜♪♥★☆]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function providerAvailable(cfg: Config, p: TtsProvider, voice: PersonaKey): boolean {
  return p === 'openai'
    ? cfg.openaiApiKey !== ''
    : cfg.elevenlabsApiKey !== '' && cfg.elevenlabsVoices[voice] !== '';
}

async function openAiSpeech(cfg: Config, text: string, voice: PersonaKey, emotion: Emotion): Promise<Speech> {
  const res = await fetchWithRetry(
    'https://api.openai.com/v1/audio/speech',
    () => ({
      method: 'POST',
      headers: { 'content-type': 'application/json', Authorization: `Bearer ${cfg.openaiApiKey}` },
      body: JSON.stringify({
        model: cfg.openaiTtsModel,
        voice: cfg.openaiVoices[voice],
        input: text,
        instructions: openAiInstructions(voice, emotion),
        response_format: 'mp3',
      }),
    }),
    { service: 'tts', timeoutMs: cfg.ttsTimeoutMs, retries: 1, retryDelayMs: cfg.retryDelayMs },
  );
  return { data: new Uint8Array(await res.arrayBuffer()), mime: 'audio/mpeg', provider: 'openai' };
}

async function elevenLabsSpeech(cfg: Config, text: string, voice: PersonaKey, emotion: Emotion): Promise<Speech> {
  const voiceId = encodeURIComponent(cfg.elevenlabsVoices[voice]);
  const s = ELEVEN_SETTINGS[emotion];
  const res = await fetchWithRetry(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_64`,
    () => ({
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        accept: 'audio/mpeg',
        'xi-api-key': cfg.elevenlabsApiKey,
      },
      body: JSON.stringify({
        text,
        model_id: cfg.elevenlabsModel,
        voice_settings: {
          stability: s.stability,
          similarity_boost: 0.75,
          style: s.style,
          use_speaker_boost: true,
        },
      }),
    }),
    { service: 'tts', timeoutMs: cfg.ttsTimeoutMs, retries: 1, retryDelayMs: cfg.retryDelayMs },
  );
  return { data: new Uint8Array(await res.arrayBuffer()), mime: 'audio/mpeg', provider: 'elevenlabs' };
}

/**
 * Speaks `text` with the preferred engine; if it is not configured or fails, tries the other one.
 * Returns null when no engine worked: the app then just shows the text.
 */
export async function synthesize(
  cfg: Config,
  preferred: TtsProvider,
  text: string,
  voice: PersonaKey,
  emotion: Emotion,
  log: (msg: string) => void = () => {},
): Promise<Speech | null> {
  const clean = cleanForSpeech(text);
  if (clean === '') return null;
  const other: TtsProvider = preferred === 'openai' ? 'elevenlabs' : 'openai';
  for (const p of [preferred, other]) {
    if (!providerAvailable(cfg, p, voice)) continue;
    try {
      return p === 'openai'
        ? await openAiSpeech(cfg, clean, voice, emotion)
        : await elevenLabsSpeech(cfg, clean, voice, emotion);
    } catch (e) {
      log(`tts via ${p} failed: ${e instanceof Error ? e.message : 'unknown error'}`);
    }
  }
  return null;
}
