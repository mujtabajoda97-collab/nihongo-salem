import type { ChatMessage } from './types.ts';

interface Entry {
  messages: ChatMessage[];
  touched: number;
}

/**
 * Conversation memory per session_id. The app sends only the newest message,
 * so the server keeps the earlier turns. In memory: a restart ends the sessions
 * (the app then simply continues without history).
 */
export class SessionStore {
  private entries = new Map<string, Entry>();
  private ttlMs: number;
  private maxMessages: number;
  private maxSessions: number;
  private now: () => number;

  constructor(ttlMs: number, maxMessages: number, maxSessions = 2000, now: () => number = Date.now) {
    this.ttlMs = ttlMs;
    this.maxMessages = maxMessages;
    this.maxSessions = maxSessions;
    this.now = now;
  }

  get(id: string): ChatMessage[] {
    this.prune();
    const e = this.entries.get(id);
    return e ? [...e.messages] : [];
  }

  /** Stores one finished exchange. The window always starts with a user message. */
  append(id: string, user: string, assistant: string): void {
    this.prune();
    const e = this.entries.get(id) ?? { messages: [], touched: 0 };
    e.messages.push({ role: 'user', content: user }, { role: 'assistant', content: assistant });
    while (e.messages.length > this.maxMessages) e.messages.splice(0, 2);
    e.touched = this.now();
    this.entries.delete(id); // re-insert => most recent last
    this.entries.set(id, e);
    while (this.entries.size > this.maxSessions) {
      const oldest = this.entries.keys().next().value;
      if (oldest === undefined) break;
      this.entries.delete(oldest);
    }
  }

  get size(): number {
    return this.entries.size;
  }

  private prune(): void {
    const cutoff = this.now() - this.ttlMs;
    for (const [id, e] of this.entries) {
      if (e.touched < cutoff) this.entries.delete(id);
      else break; // insertion order == touch order
    }
  }
}
