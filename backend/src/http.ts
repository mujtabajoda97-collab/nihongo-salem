/** An upstream provider (Whisper / Claude / TTS) failed. */
export class UpstreamError extends Error {
  service: 'stt' | 'llm' | 'tts';
  status: number;
  constructor(service: 'stt' | 'llm' | 'tts', status: number, message: string) {
    super(message);
    this.name = 'UpstreamError';
    this.service = service;
    this.status = status;
  }
}

export interface RetryOptions {
  service: 'stt' | 'llm' | 'tts';
  timeoutMs: number;
  /** Extra attempts after the first one (only for 429 / 5xx / network errors). */
  retries: number;
  retryDelayMs: number;
}

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * fetch with a timeout and a small retry for transient failures.
 * `makeInit` is called per attempt because a FormData body can be sent only once.
 */
export async function fetchWithRetry(
  url: string,
  makeInit: () => RequestInit,
  opts: RetryOptions,
): Promise<Response> {
  let lastError: UpstreamError | undefined;
  for (let attempt = 0; attempt <= opts.retries; attempt++) {
    if (attempt > 0) await sleep(opts.retryDelayMs * attempt);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), opts.timeoutMs);
    try {
      const res = await fetch(url, { ...makeInit(), signal: controller.signal });
      if (res.ok) return res;
      const body = (await res.text().catch(() => '')).slice(0, 300);
      lastError = new UpstreamError(opts.service, res.status, `${opts.service} HTTP ${res.status}: ${body}`);
      const transient = res.status === 429 || res.status >= 500;
      if (!transient) throw lastError;
    } catch (e) {
      if (e instanceof UpstreamError) {
        if (e.status !== 0 && !(e.status === 429 || e.status >= 500)) throw e;
        lastError = e;
      } else {
        const aborted = e instanceof Error && e.name === 'AbortError';
        lastError = new UpstreamError(
          opts.service,
          0,
          aborted ? `${opts.service} timed out after ${opts.timeoutMs} ms` : `${opts.service} network error`,
        );
      }
    } finally {
      clearTimeout(timer);
    }
  }
  throw lastError ?? new UpstreamError(opts.service, 0, 'unknown upstream failure');
}
