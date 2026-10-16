import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { AudioStore } from '../src/audioStore.ts';
import { fillTemplate, loadPrompts } from '../src/prompts.ts';
import { SessionStore } from '../src/sessions.ts';
import { loadConfig } from '../src/config.ts';

describe('SessionStore', () => {
  it('keeps pairs, always starting with a user message, within the window', () => {
    const s = new SessionStore(60_000, 6);
    for (let i = 0; i < 5; i++) s.append('a', `u${i}`, `a${i}`);
    const h = s.get('a');
    assert.equal(h.length, 6);
    assert.equal(h[0]!.role, 'user');
    assert.equal(h[0]!.content, 'u2');
    assert.equal(h.at(-1)!.content, 'a4');
  });

  it('forgets idle sessions and isolates ids', () => {
    let t = 0;
    const s = new SessionStore(1000, 10, 100, () => t);
    s.append('a', 'u', 'a');
    s.append('b', 'u2', 'a2');
    assert.equal(s.get('b')[0]!.content, 'u2');
    t = 5000;
    assert.deepEqual(s.get('a'), []);
  });

  it('caps the number of sessions', () => {
    const s = new SessionStore(60_000, 4, 3);
    for (const id of ['1', '2', '3', '4']) s.append(id, 'u', 'a');
    assert.equal(s.size, 3);
    assert.deepEqual(s.get('1'), []);
  });
});

describe('AudioStore', () => {
  it('serves, expires, and reuses by key', () => {
    let t = 0;
    const a = new AudioStore(10 * 60_000, 1_000_000, 10, () => t);
    const key = AudioStore.keyFor('openai', 'x');
    const id = a.put(new Uint8Array([1, 2]), 'audio/mpeg', key);
    assert.match(id, /^[0-9a-f]{32}$/);
    assert.equal(a.find(key), id);
    assert.deepEqual([...a.get(id)!.data], [1, 2]);
    t = 9.5 * 60_000; // < 60 s left: not reused any more, still downloadable
    assert.equal(a.find(key), undefined);
    assert.ok(a.get(id));
    t = 11 * 60_000;
    assert.equal(a.get(id), undefined);
  });

  it('evicts the oldest clip when over the byte budget', () => {
    const a = new AudioStore(60_000, 10, 10);
    const first = a.put(new Uint8Array(6), 'audio/mpeg');
    const second = a.put(new Uint8Array(6), 'audio/mpeg');
    assert.equal(a.get(first), undefined);
    assert.ok(a.get(second));
  });
});

describe('prompt templates', () => {
  const cfg = loadConfig({ ANTHROPIC_API_KEY: 'a', OPENAI_API_KEY: 'b' }, {
    promptsDir: new URL('../prompts', import.meta.url).pathname,
  });
  const prompts = loadPrompts(cfg.promptsDir);

  it('fills every placeholder of the lesson prompt (variables the Flutter app sends)', () => {
    const out = fillTemplate(prompts.tutor, {
      TONE: 'strict_tsundere', EPISODE_ID: '3', EPISODE_TITLE_AR: 'عنوان', EPISODE_SCENARIO: 'SCENARIO-TEXT',
      INITIAL_AI_MESSAGE: 'いらっしゃいませ', EPISODE_VOCAB: 'えき = محطة', EPISODE_GRAMMAR: '〜へ 行きます', USER_NAME: 'サーレム',
    });
    assert.ok(!out.includes('{{'), 'no placeholder left');
    assert.ok(out.includes('SCENARIO-TEXT') && out.includes('strict_tsundere'));
  });

  it('fills every placeholder of the free-talk prompt', () => {
    const out = fillTemplate(prompts.freeTalk, {
      PERSONA: 'kansai', USER_NAME: 'サーレム', USER_PROGRESS: '14', KNOWN_VOCAB: 'ねこ、いぬ',
      LOCAL_TIME: '08:15', IS_FIRST_TURN: 'true',
    });
    assert.ok(!out.includes('{{'));
    assert.ok(out.includes('Current persona: kansai'));
  });

  it('cannot be tricked by placeholders or $ patterns inside values', () => {
    const out = fillTemplate('A {{X}} B {{Y}}', { X: '{{Y}} $& $1', Y: 'safe' });
    assert.equal(out, 'A Y $& $1 B safe');
  });
});

describe('loadConfig', () => {
  it('lists every problem at once', () => {
    assert.throws(() => loadConfig({ DEFAULT_TTS_PROVIDER: 'x' }), (e: Error) =>
      /ANTHROPIC_API_KEY/.test(e.message) && /OPENAI_API_KEY/.test(e.message) && /DEFAULT_TTS_PROVIDER/.test(e.message));
  });

  it('applies defaults and per-persona voice overrides', () => {
    const c = loadConfig({ ANTHROPIC_API_KEY: 'a', OPENAI_API_KEY: 'b', OPENAI_VOICE_KANSAI: 'verse', ELEVENLABS_VOICE_ID: 'EL' });
    assert.equal(c.whisperModel, 'whisper-1');
    assert.equal(c.openaiTtsModel, 'gpt-4o-mini-tts');
    assert.equal(c.openaiVoices.kansai, 'verse');
    assert.equal(c.elevenlabsVoices.tsundere, 'EL');
    assert.equal(c.audioDelivery, 'url');
  });
});
