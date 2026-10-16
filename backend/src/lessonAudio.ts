import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { Config } from './config.ts';
import { fetchWithRetry } from './http.ts';

/**
 * Fixed lesson audio (dialogue lines + vocabulary), generated the first time the app asks for it and then cached.
 * The app asks for GET /v1/lesson-audio/ep01_line_01.mp3 when the bundled mp3 is missing.
 * Same voice rules as generate_episodes_media.js, so both produce the same voices.
 */

export interface LessonClip {
  file: string; // "ep01_line_01.mp3"
  kind: 'line' | 'vocab';
  text: string;
  voice: string;
}

const OPENAI_MALE = ['ash', 'onyx', 'echo', 'fable'];
const OPENAI_FEMALE = ['coral', 'nova', 'shimmer', 'sage'];
const FEMALE_NAMES = new Set(['ユキ', 'ミナ', 'アンナ', '田中先生', 'お母さん', '山田さん', 'アナウンス']);
const FEMALE_AR = /(موظفة|بائعة|السيدة|الأستاذة|والدة|مضيفة)/;
const LEARNER = 'サーレム';

const LINE_STYLE =
  'Speak natural, clear Japanese for beginner learners. Slightly slow, every word articulated, ' +
  'friendly conversational intonation fitting the line. Do not add or skip any words.';
const VOCAB_STYLE = 'Pronounce this single Japanese word clearly and slowly with natural pitch accent. Say only the word.';

const hashIndex = (s: string, n: number): number => createHash('sha1').update(s).digest()[0]! % n;

export function lessonVoice(speakerJp: string, speakerAr: string): string {
  const female = FEMALE_NAMES.has(speakerJp) || FEMALE_AR.test(speakerAr);
  const pool = female ? OPENAI_FEMALE : OPENAI_MALE;
  if (speakerJp === LEARNER && !female) return pool[0]!;
  const others = !female && pool.length > 1 ? pool.slice(1) : pool;
  return others[hashIndex(`${speakerJp}|${speakerAr}`, others.length)]!;
}

export function toSpeech(text: string): string {
  return text
    .replace(/^[〜~\s]+/, '')
    .replace(/[「」『』()（）]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

interface EpisodeFile {
  dialogues?: { speaker_name_jp?: string; speaker_name_ar?: string; audio_file?: string; japanese?: string }[];
  vocabulary?: { kana?: string; audio?: string }[];
}

const baseName = (p: string): string => p.replace(/^.*\//, '');

interface KanaCourseFile {
  clips?: { file?: string; text?: string }[];
}

/** Reads every episode_XX.json in `dir` and lists the clips the app can ask for. */
export function buildLessonIndex(dir: string): Map<string, LessonClip> {
  const index = new Map<string, LessonClip>();
  if (!existsSync(dir)) return index;
  for (const f of readdirSync(dir).filter((n) => /^episode_\d+\.json$/.test(n)).sort()) {
    const ep = JSON.parse(readFileSync(join(dir, f), 'utf8')) as EpisodeFile;
    for (const d of ep.dialogues ?? []) {
      if (!d.audio_file || !d.japanese) continue;
      const file = baseName(d.audio_file);
      const text = toSpeech(d.japanese);
      if (text === '' || index.has(file)) continue;
      index.set(file, {
        file,
        kind: 'line',
        text,
        voice: lessonVoice(d.speaker_name_jp ?? '', d.speaker_name_ar ?? ''),
      });
    }
    for (const v of ep.vocabulary ?? []) {
      if (!v.audio || !v.kana) continue;
      const file = baseName(v.audio);
      const text = toSpeech(v.kana);
      if (text === '' || index.has(file)) continue;
      index.set(file, { file, kind: 'vocab', text, voice: 'sage' });
    }
  }
  // Beginner course (letters, words, sentences): kana_course.json lists its own clips.
  const kanaFile = join(dir, 'kana_course.json');
  if (existsSync(kanaFile)) {
    const course = JSON.parse(readFileSync(kanaFile, 'utf8')) as KanaCourseFile;
    for (const c of course.clips ?? []) {
      if (!c.file || !c.text) continue;
      const file = baseName(c.file);
      const text = toSpeech(c.text);
      if (text === '' || index.has(file)) continue;
      index.set(file, { file, kind: 'vocab', text, voice: 'sage' });
    }
  }
  return index;
}

export type ClipSynth = (clip: LessonClip) => Promise<Uint8Array>;

export function openAiClipSynth(cfg: Config): ClipSynth {
  return async (clip) => {
    const res = await fetchWithRetry(
      'https://api.openai.com/v1/audio/speech',
      () => ({
        method: 'POST',
        headers: { 'content-type': 'application/json', Authorization: `Bearer ${cfg.openaiApiKey}` },
        body: JSON.stringify({
          model: cfg.openaiTtsModel,
          voice: clip.voice,
          input: clip.text,
          instructions: clip.kind === 'vocab' ? VOCAB_STYLE : LINE_STYLE,
          response_format: 'mp3',
        }),
      }),
      { service: 'tts', timeoutMs: cfg.ttsTimeoutMs, retries: 2, retryDelayMs: cfg.retryDelayMs },
    );
    return new Uint8Array(await res.arrayBuffer());
  };
}

/** Generates a clip once, keeps it on disk (and in memory) and serves it from there afterwards. */
export class LessonAudio {
  private readonly memory = new Map<string, Uint8Array>();
  private readonly inflight = new Map<string, Promise<Uint8Array>>();

  readonly index: Map<string, LessonClip>;
  private readonly synth: ClipSynth;
  private readonly cacheDir: string;
  private readonly maxMemoryClips: number;

  constructor(index: Map<string, LessonClip>, synth: ClipSynth, cacheDir: string, maxMemoryClips = 300) {
    this.index = index;
    this.synth = synth;
    this.cacheDir = cacheDir;
    this.maxMemoryClips = maxMemoryClips;
  }

  has(file: string): boolean {
    return this.index.has(file);
  }

  /** Undefined when `file` is not a known lesson clip. Throws if generation fails. */
  async get(file: string): Promise<Uint8Array | undefined> {
    const clip = this.index.get(file);
    if (!clip) return undefined;
    const cached = this.memory.get(file);
    if (cached) return cached;
    const running = this.inflight.get(file);
    if (running) return running;
    const job = this.load(clip).finally(() => this.inflight.delete(file));
    this.inflight.set(file, job);
    return job;
  }

  private async load(clip: LessonClip): Promise<Uint8Array> {
    const path = join(this.cacheDir, clip.file);
    try {
      const onDisk = await readFile(path);
      if (onDisk.byteLength > 0) return this.remember(clip.file, new Uint8Array(onDisk));
    } catch {
      // not generated yet
    }
    const data = await this.synth(clip);
    if (data.byteLength === 0) throw new Error('empty audio from provider');
    try {
      await mkdir(this.cacheDir, { recursive: true });
      await writeFile(`${path}.part`, data);
      await rename(`${path}.part`, path);
    } catch {
      // the disk cache is best-effort; the clip is still returned and kept in memory
    }
    return this.remember(clip.file, data);
  }

  private remember(file: string, data: Uint8Array): Uint8Array {
    this.memory.set(file, data);
    while (this.memory.size > this.maxMemoryClips) {
      const oldest = this.memory.keys().next().value;
      if (oldest === undefined) break;
      this.memory.delete(oldest);
    }
    return data;
  }
}
