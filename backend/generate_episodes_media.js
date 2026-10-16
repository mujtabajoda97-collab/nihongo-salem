#!/usr/bin/env node
/**
 * Generates the fixed lesson audio of the app in one go:
 *   - every dialogue line of the 40 episodes      -> dialogues[].audio_file (e.g. assets/audio/ep01_line_01.mp3)
 *   - every vocabulary word (spoken in kana)      -> vocabulary[].audio     (e.g. assets/audio/ep01_v_01.mp3)
 *
 * No dependencies (Node 20+). Reads the episode JSON files of the Flutter project and writes the mp3 files
 * where the JSON says they must be, so no app code changes are needed.
 *
 *   node --env-file=.env generate_episodes_media.js --dry-run          # count only, spends nothing
 *   node --env-file=.env generate_episodes_media.js --episodes 1-2     # try 2 episodes first
 *   node --env-file=.env generate_episodes_media.js                    # everything (skips files that exist)
 *
 * Options
 *   --provider openai|elevenlabs   default: MEDIA_TTS_PROVIDER or openai
 *   --episodes 1-5,8,12-14          default: all
 *   --only lines|vocab              default: both
 *   --force                         overwrite existing files (default: skip them, so you can resume)
 *   --dry-run                       list what would be generated
 *   --concurrency N                 default 3
 *   --episodes-dir DIR              default: EPISODES_DIR or ../japanese_app/assets/data/episodes
 *   --out-dir DIR                   default: AUDIO_OUT_DIR or ../japanese_app/assets/audio
 *   --voices FILE.json              optional {"ユキ":"nova","店員|موظفة المتجر":"coral"} to pick a voice per speaker
 *
 * Keys (env): OPENAI_API_KEY, or ELEVENLABS_API_KEY + ELEVENLABS_VOICES_MALE / ELEVENLABS_VOICES_FEMALE
 * (comma-separated voice ids; the first male voice is used for the learner, サーレム).
 */
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { mkdir, rename, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';

// ---------------------------------------------------------------- arguments
function parseArgs(argv) {
  const a = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (!t.startsWith('--')) { a._.push(t); continue; }
    const key = t.slice(2);
    if (['force', 'dry-run', 'help'].includes(key)) a[key] = true;
    else a[key] = argv[++i];
  }
  return a;
}

const args = parseArgs(process.argv.slice(2));
if (args.help) {
  console.log(readFileSync(new URL(import.meta.url), 'utf8').split('*/')[0].replace(/^[/ *]+/gm, ''));
  process.exit(0);
}

const env = process.env;
const provider = args.provider ?? env.MEDIA_TTS_PROVIDER ?? 'openai';
const episodesDir = resolve(args['episodes-dir'] ?? env.EPISODES_DIR ?? '../japanese_app/assets/data/episodes');
const outDir = resolve(args['out-dir'] ?? env.AUDIO_OUT_DIR ?? '../japanese_app/assets/audio');
const concurrency = Math.max(1, Number.parseInt(args.concurrency ?? '3', 10) || 3);
const OPENAI_MODEL = env.OPENAI_TTS_MODEL ?? 'gpt-4o-mini-tts';
const ELEVEN_MODEL = env.ELEVENLABS_MODEL ?? 'eleven_multilingual_v2';

if (!['openai', 'elevenlabs'].includes(provider)) fail('--provider must be openai or elevenlabs');
if (!existsSync(episodesDir)) fail(`Episodes folder not found: ${episodesDir}\nPass --episodes-dir.`);

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

function parseRange(spec) {
  if (!spec) return null;
  const set = new Set();
  for (const part of spec.split(',')) {
    const m = part.trim().match(/^(\d+)(?:-(\d+))?$/);
    if (!m) fail(`Bad --episodes value: ${spec}`);
    const from = Number(m[1]);
    const to = Number(m[2] ?? m[1]);
    for (let n = from; n <= to; n++) set.add(n);
  }
  return set;
}

// ------------------------------------------------------------------- voices
const OPENAI_MALE = ['ash', 'onyx', 'echo', 'fable'];
const OPENAI_FEMALE = ['coral', 'nova', 'shimmer', 'sage'];
const FEMALE_NAMES = new Set(['ユキ', 'ミナ', 'アンナ', '田中先生', 'お母さん', '山田さん', 'アナウンス']);
const FEMALE_AR = /(موظفة|بائعة|السيدة|الأستاذة|والدة|مضيفة)/;
const LEARNER = 'サーレム';

const list = (v) => (v ?? '').split(',').map((s) => s.trim()).filter(Boolean);
const elevenMale = list(env.ELEVENLABS_VOICES_MALE);
const elevenFemale = list(env.ELEVENLABS_VOICES_FEMALE);
const customVoices = args.voices ? JSON.parse(readFileSync(resolve(args.voices), 'utf8')) : {};

const hashIndex = (s, n) => createHash('sha1').update(s).digest()[0] % n;

function voiceFor(speakerJp, speakerAr) {
  const custom = customVoices[`${speakerJp}|${speakerAr}`] ?? customVoices[speakerJp];
  if (custom) return custom;
  const female = FEMALE_NAMES.has(speakerJp) || FEMALE_AR.test(speakerAr);
  const pool = provider === 'openai'
    ? (female ? OPENAI_FEMALE : OPENAI_MALE)
    : (female ? elevenFemale : elevenMale);
  if (pool.length === 0) return null;
  if (speakerJp === LEARNER && !female) return pool[0];
  // Everybody else: stable pick, but never the learner's voice when there is another one.
  const others = !female && pool.length > 1 ? pool.slice(1) : pool;
  return others[hashIndex(`${speakerJp}|${speakerAr}`, others.length)];
}

/** The same calm voice for every vocabulary word. */
function vocabVoice() {
  return provider === 'openai' ? 'sage' : (elevenFemale[0] ?? elevenMale[0] ?? null);
}

// --------------------------------------------------------------------- jobs
function toSpeech(text) {
  return text.replace(/^[〜~\s]+/, '').replace(/[「」『』()（）]/g, ' ').replace(/\s+/g, ' ').trim();
}

function collectJobs() {
  const wanted = parseRange(args.episodes);
  const only = args.only;
  if (only && !['lines', 'vocab'].includes(only)) fail('--only must be lines or vocab');
  const files = readdirSync(episodesDir).filter((f) => /^episode_\d+\.json$/.test(f)).sort();
  if (files.length === 0) fail(`No episode_XX.json files in ${episodesDir}`);

  const jobs = [];
  const seen = new Set();
  const add = (job) => {
    if (!job.audioPath || seen.has(job.audioPath)) return;
    seen.add(job.audioPath);
    jobs.push(job);
  };
  const rel = (p) => p.replace(/^assets\/audio\//, '');

  for (const f of files) {
    const ep = JSON.parse(readFileSync(join(episodesDir, f), 'utf8'));
    if (wanted && !wanted.has(ep.episode_id)) continue;
    if (only !== 'vocab') {
      for (const d of ep.dialogues ?? []) {
        add({
          episode: ep.episode_id, kind: 'line', audioPath: rel(d.audio_file), text: toSpeech(d.japanese),
          voice: voiceFor(d.speaker_name_jp, d.speaker_name_ar), speaker: d.speaker_name_jp,
        });
      }
    }
    if (only !== 'lines') {
      for (const v of ep.vocabulary ?? []) {
        add({
          episode: ep.episode_id, kind: 'vocab', audioPath: rel(v.audio), text: toSpeech(v.kana),
          voice: vocabVoice(), speaker: 'vocab',
        });
      }
    }
  }
  return jobs;
}

// ---------------------------------------------------------------------- TTS
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const LINE_STYLE =
  'Speak natural, clear Japanese for beginner learners. Slightly slow, every word articulated, ' +
  'friendly conversational intonation fitting the line. Do not add or skip any words.';
const VOCAB_STYLE =
  'Pronounce this single Japanese word clearly and slowly with natural pitch accent. Say only the word.';

async function requestSpeech(job) {
  if (provider === 'openai') {
    return fetch('https://api.openai.com/v1/audio/speech', {
      method: 'POST',
      headers: { 'content-type': 'application/json', Authorization: `Bearer ${env.OPENAI_API_KEY}` },
      body: JSON.stringify({
        model: OPENAI_MODEL,
        voice: job.voice,
        input: job.text,
        instructions: job.kind === 'vocab' ? VOCAB_STYLE : LINE_STYLE,
        response_format: 'mp3',
      }),
    });
  }
  return fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(job.voice)}?output_format=mp3_44100_128`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'audio/mpeg', 'xi-api-key': env.ELEVENLABS_API_KEY },
      body: JSON.stringify({
        text: job.text,
        model_id: ELEVEN_MODEL,
        voice_settings: { stability: job.kind === 'vocab' ? 0.7 : 0.5, similarity_boost: 0.75, style: 0.15, use_speaker_boost: true },
      }),
    },
  );
}

async function synthesize(job) {
  let lastError = 'unknown error';
  for (let attempt = 1; attempt <= 4; attempt++) {
    try {
      const res = await requestSpeech(job);
      if (res.ok) return Buffer.from(await res.arrayBuffer());
      lastError = `HTTP ${res.status} ${(await res.text()).slice(0, 200)}`;
      if (res.status !== 429 && res.status < 500) break; // 400/401/403: retrying will not help
      const wait = Number(res.headers.get('retry-after')) * 1000 || 2000 * 2 ** (attempt - 1);
      await sleep(wait);
    } catch (e) {
      lastError = String(e?.message ?? e);
      await sleep(2000 * attempt);
    }
  }
  throw new Error(lastError);
}

// --------------------------------------------------------------------- main
const jobs = collectJobs();
const missingVoice = jobs.filter((j) => !j.voice);
if (missingVoice.length > 0) {
  fail(
    provider === 'elevenlabs'
      ? 'ElevenLabs needs ELEVENLABS_VOICES_MALE and ELEVENLABS_VOICES_FEMALE (comma-separated voice ids).'
      : 'No voice found for some speakers.',
  );
}

const isDone = (j) => existsSync(join(outDir, j.audioPath)) && statSync(join(outDir, j.audioPath)).size > 0;
const todo = args.force ? jobs : jobs.filter((j) => !isDone(j));
const chars = todo.reduce((n, j) => n + j.text.length, 0);

console.log(`Provider: ${provider}${provider === 'openai' ? ` (${OPENAI_MODEL})` : ` (${ELEVEN_MODEL})`}`);
console.log(`Episodes folder: ${episodesDir}`);
console.log(`Output folder:   ${outDir}`);
console.log(`Files: ${jobs.length} total, ${jobs.length - todo.length} already exist, ${todo.length} to generate (${chars} characters)`);

if (args['dry-run']) {
  for (const j of todo.slice(0, 15)) console.log(`  ${j.audioPath}  [${j.voice}] ${j.text}`);
  if (todo.length > 15) console.log(`  ... and ${todo.length - 15} more`);
  process.exit(0);
}
if (todo.length === 0) {
  console.log('Nothing to do.');
  process.exit(0);
}
if (provider === 'openai' && !env.OPENAI_API_KEY) fail('OPENAI_API_KEY is not set.');
if (provider === 'elevenlabs' && !env.ELEVENLABS_API_KEY) fail('ELEVENLABS_API_KEY is not set.');

const failures = [];
let done = 0;
let next = 0;

async function worker() {
  while (next < todo.length) {
    const job = todo[next++];
    try {
      const audio = await synthesize(job);
      const target = join(outDir, job.audioPath);
      await mkdir(dirname(target), { recursive: true });
      const tmp = `${target}.part`;
      await writeFile(tmp, audio);
      await rename(tmp, target); // never leaves a half-written mp3
    } catch (e) {
      failures.push({ file: job.audioPath, text: job.text, error: e.message });
    }
    done++;
    if (done % 25 === 0 || done === todo.length) {
      console.log(`  ${done}/${todo.length}  (failed: ${failures.length})`);
    }
  }
}

await Promise.all(Array.from({ length: Math.min(concurrency, todo.length) }, worker));

if (failures.length > 0) {
  const report = resolve('media_failures.json');
  await writeFile(report, JSON.stringify(failures, null, 2));
  console.error(`\n${failures.length} file(s) failed. Details: ${report}`);
  console.error('Run the same command again: finished files are skipped and only the missing ones are retried.');
  process.exit(1);
}
console.log('\nAll audio files generated.');
