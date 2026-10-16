import type { Config } from '../config.ts';
import { fetchWithRetry } from '../http.ts';
import type { AiTurn, ChatMessage, Emotion } from '../types.ts';
import { EMOTIONS } from '../types.ts';

export class LlmFormatError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LlmFormatError';
  }
}

function asBool(v: unknown): boolean {
  return v === true || (typeof v === 'string' && v.trim().toLowerCase() === 'true');
}

function asString(obj: Record<string, unknown>, key: string, required: boolean): string {
  const v = obj[key];
  if (typeof v === 'string') return v;
  if (required) throw new LlmFormatError(`"${key}" is missing or not a string`);
  return '';
}

/**
 * Reads the model's answer. Tolerates a code fence or stray text around the
 * JSON object, and fixes harmless slips (string booleans, unknown emotion).
 */
export function parseAiTurn(raw: string): AiTurn {
  const start = raw.indexOf('{');
  const end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) throw new LlmFormatError('no JSON object in the answer');
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw.slice(start, end + 1));
  } catch {
    throw new LlmFormatError('answer is not valid JSON');
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw new LlmFormatError('answer is not a JSON object');
  }
  const o = parsed as Record<string, unknown>;
  const reply = asString(o, 'reply_japanese', true).trim();
  if (reply === '') throw new LlmFormatError('"reply_japanese" is empty');
  const emotionRaw = typeof o.emotion_tone === 'string' ? o.emotion_tone.trim().toLowerCase() : '';
  const emotion: Emotion = (EMOTIONS as readonly string[]).includes(emotionRaw)
    ? (emotionRaw as Emotion)
    : 'calm';
  return {
    correction_ar: asString(o, 'correction_ar', true),
    reply_japanese: reply,
    reply_romaji: asString(o, 'reply_romaji', false),
    reply_arabic: asString(o, 'reply_arabic', false),
    emotion_tone: emotion,
    has_mistake: asBool(o.has_mistake),
    conversation_completed: asBool(o.conversation_completed),
  };
}

/** One call to the Claude Messages API. Returns the text of the answer. */
export async function callClaude(cfg: Config, system: string, messages: ChatMessage[]): Promise<string> {
  const makeInit = (): RequestInit => ({
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': cfg.anthropicApiKey,
      'anthropic-version': '2023-06-01',
      ...(cfg.anthropicWorkspaceId ? { 'anthropic-workspace-id': cfg.anthropicWorkspaceId } : {}),
    },
    body: JSON.stringify({
      model: cfg.anthropicModel,
      max_tokens: cfg.anthropicMaxTokens,
      // The long prompt is identical on every turn of a session: let the API cache it.
      system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
      messages,
    }),
  });
  const res = await fetchWithRetry('https://api.anthropic.com/v1/messages', makeInit, {
    service: 'llm',
    timeoutMs: cfg.llmTimeoutMs,
    retries: 1,
    retryDelayMs: cfg.retryDelayMs,
  });
  const body = (await res.json().catch(() => null)) as {
    content?: Array<{ type?: string; text?: string }>;
  } | null;
  const text = body?.content
    ?.filter((b) => b.type === 'text' && typeof b.text === 'string')
    .map((b) => b.text)
    .join('');
  return text ?? '';
}

/** Asks for the next turn; if the answer is not the required JSON, asks once more. */
export async function generateTurn(
  cfg: Config,
  system: string,
  history: ChatMessage[],
  userContent: string,
): Promise<AiTurn> {
  const messages: ChatMessage[] = [...history, { role: 'user', content: userContent }];
  const raw = await callClaude(cfg, system, messages);
  try {
    return parseAiTurn(raw);
  } catch (e) {
    if (!(e instanceof LlmFormatError)) throw e;
  }
  const retry: ChatMessage[] = [
    ...messages,
    { role: 'assistant', content: raw.trim() === '' ? '(empty)' : raw.slice(0, 2000) },
    {
      role: 'user',
      content:
        'Your last message was not the required output. Reply again with exactly ONE JSON object ' +
        'containing the seven required keys, and nothing else.',
    },
  ];
  return parseAiTurn(await callClaude(cfg, system, retry));
}
