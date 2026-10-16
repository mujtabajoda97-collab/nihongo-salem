import type { Config } from './config.ts';

export interface CheckResult {
  ok: boolean;
  status: number;
  detail: string;
}

export interface SelfTestResult {
  anthropic: CheckResult;
  openai_key: CheckResult;
  openai_tts: CheckResult;
  hint: string;
}

async function timed(url: string, init: RequestInit, ms = 15_000): Promise<CheckResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), ms);
  try {
    const res = await fetch(url, { ...init, signal: controller.signal });
    if (res.ok) return { ok: true, status: res.status, detail: 'ok' };
    // Provider error bodies describe the problem (e.g. "credit balance is too low"); they never contain our keys.
    const body = (await res.text().catch(() => '')).replace(/\s+/g, ' ').slice(0, 220);
    return { ok: false, status: res.status, detail: body };
  } catch (e) {
    const aborted = e instanceof Error && e.name === 'AbortError';
    return { ok: false, status: 0, detail: aborted ? 'timed out' : 'network error' };
  } finally {
    clearTimeout(timer);
  }
}

/** Tiny real calls to Claude and OpenAI, so "is it the key or the credit?" has a definite answer. */
export async function runSelfTest(cfg: Config): Promise<SelfTestResult> {
  const [anthropic, openaiKey, openaiTts] = await Promise.all([
    timed('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': cfg.anthropicApiKey,
        'anthropic-version': '2023-06-01',
        ...(cfg.anthropicWorkspaceId ? { 'anthropic-workspace-id': cfg.anthropicWorkspaceId } : {}),
      },
      body: JSON.stringify({
        model: cfg.anthropicModel,
        max_tokens: 5,
        messages: [{ role: 'user', content: 'Say OK' }],
      }),
    }),
    timed('https://api.openai.com/v1/models', {
      headers: { Authorization: `Bearer ${cfg.openaiApiKey}` },
    }),
    timed('https://api.openai.com/v1/audio/speech', {
      method: 'POST',
      headers: { 'content-type': 'application/json', Authorization: `Bearer ${cfg.openaiApiKey}` },
      body: JSON.stringify({ model: cfg.openaiTtsModel, voice: 'sage', input: 'あ', response_format: 'mp3' }),
    }),
  ]);
  let hint = 'All providers answer: the keys and the credit are fine.';
  if (!anthropic.ok && /workspace/i.test(anthropic.detail)) {
    hint = 'The Claude key is not tied to a workspace: set ANTHROPIC_WORKSPACE_ID (Console > Settings > Workspaces) or create a new key inside a workspace.';
  } else if (!anthropic.ok) hint = `Claude call failed (${anthropic.status}): check ANTHROPIC_API_KEY, the credit balance and ANTHROPIC_MODEL.`;
  else if (!openaiKey.ok) hint = `OpenAI key rejected (${openaiKey.status}): check OPENAI_API_KEY.`;
  else if (!openaiTts.ok) hint = `OpenAI speech failed (${openaiTts.status}): check the OpenAI credit balance / TTS model.`;
  return { anthropic, openai_key: openaiKey, openai_tts: openaiTts, hint };
}
