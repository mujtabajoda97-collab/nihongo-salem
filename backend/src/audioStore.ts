import { createHash, randomBytes } from 'node:crypto';

interface Item {
  data: Uint8Array;
  mime: string;
  expires: number;
  key: string;
}

/** Short-lived memory store for generated speech, served at GET /v1/audio/:id. */
export class AudioStore {
  private items = new Map<string, Item>();
  private byKey = new Map<string, string>();
  private bytes = 0;
  private ttlMs: number;
  private maxBytes: number;
  private maxItems: number;
  private now: () => number;

  constructor(ttlMs: number, maxBytes = 40 * 1024 * 1024, maxItems = 400, now: () => number = Date.now) {
    this.ttlMs = ttlMs;
    this.maxBytes = maxBytes;
    this.maxItems = maxItems;
    this.now = now;
  }

  /** Stable key for "same text, same voice": avoids paying twice for greetings. */
  static keyFor(...parts: string[]): string {
    return createHash('sha256').update(parts.join('\u0001')).digest('hex');
  }

  /** Id of a still-valid clip made earlier for this key. */
  find(key: string): string | undefined {
    this.prune();
    const id = this.byKey.get(key);
    const it = id ? this.items.get(id) : undefined;
    // Not worth reusing a clip that is about to expire while the app downloads it.
    return id && it && it.expires - this.now() > 60_000 ? id : undefined;
  }

  put(data: Uint8Array, mime: string, key = ''): string {
    this.prune();
    const id = randomBytes(16).toString('hex'); // unguessable
    this.items.set(id, { data, mime, expires: this.now() + this.ttlMs, key });
    if (key) this.byKey.set(key, id);
    this.bytes += data.byteLength;
    while (this.items.size > this.maxItems || this.bytes > this.maxBytes) {
      const oldest = this.items.keys().next().value;
      if (oldest === undefined || oldest === id) break;
      this.drop(oldest);
    }
    return id;
  }

  get(id: string): { data: Uint8Array; mime: string } | undefined {
    this.prune();
    const it = this.items.get(id);
    return it ? { data: it.data, mime: it.mime } : undefined;
  }

  get size(): number {
    return this.items.size;
  }

  private drop(id: string): void {
    const it = this.items.get(id);
    if (!it) return;
    this.items.delete(id);
    this.bytes -= it.data.byteLength;
    if (it.key && this.byKey.get(it.key) === id) this.byKey.delete(it.key);
  }

  private prune(): void {
    const t = this.now();
    for (const [id, it] of this.items) {
      if (it.expires <= t) this.drop(id);
      else break; // inserted in time order
    }
  }
}
