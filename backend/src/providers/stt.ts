import type { Config } from '../config.ts';
import { fetchWithRetry, UpstreamError } from '../http.ts';

/** Things Whisper "hears" in silence or noise. */
const HALLUCINATIONS = new Set([
  'ご視聴ありがとうございました',
  'ご視聴ありがとうございます',
  'チャンネル登録お願いします',
  'チャンネル登録よろしくお願いします',
  'ご清聴ありがとうございました',
]);

/** Returns '' when the text is empty, only punctuation, or a known silence hallucination. */
export function cleanTranscript(text: string): string {
  const t = text.trim();
  const bare = t.replace(/[\s　。、．，.!！?？…・~〜ー-]+/g, '');
  if (bare.length === 0) return '';
  if (HALLUCINATIONS.has(bare)) return '';
  return t;
}

/** OpenAI Whisper, Japanese. Returns the raw transcript text. */
export async function transcribe(cfg: Config, audio: Uint8Array): Promise<string> {
  const makeInit = (): RequestInit => {
    const form = new FormData();
    form.append('file', new Blob([audio as unknown as ArrayBuffer], { type: 'audio/mp4' }), 'turn.m4a');
    form.append('model', cfg.whisperModel);
    form.append('language', 'ja');
    form.append('response_format', 'json');
    form.append('temperature', '0');
    return { method: 'POST', headers: { Authorization: `Bearer ${cfg.openaiApiKey}` }, body: form };
  };
  const res = await fetchWithRetry('https://api.openai.com/v1/audio/transcriptions', makeInit, {
    service: 'stt',
    timeoutMs: cfg.sttTimeoutMs,
    retries: 1,
    retryDelayMs: cfg.retryDelayMs,
  });
  const body = (await res.json().catch(() => null)) as { text?: unknown } | null;
  if (!body || typeof body.text !== 'string') {
    throw new UpstreamError('stt', 502, 'stt returned no text');
  }
  return body.text;
}
