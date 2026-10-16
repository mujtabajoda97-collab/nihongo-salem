import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';
import { LessonAudio, buildLessonIndex, lessonVoice, toSpeech } from '../src/lessonAudio.ts';
import type { LessonClip } from '../src/lessonAudio.ts';

const episodesDir = new URL('../episodes', import.meta.url).pathname;

describe('lesson audio index', () => {
  const index = buildLessonIndex(episodesDir);

  it('lists every dialogue line and vocabulary word of the 40 episodes', () => {
    const episodeClips = [...index.keys()].filter((f) => f.startsWith('ep')).length;
    assert.equal(episodeClips, 893);
    assert.equal(index.get('kana_c_001.mp3')?.text, 'あ');
    assert.ok(index.size > 893 + 200);
    assert.equal(index.get('ep01_line_01.mp3')?.kind, 'line');
    assert.equal(index.get('ep01_v_01.mp3')?.text, 'くうこう');
    assert.equal(index.get('ep01_v_01.mp3')?.voice, 'sage');
  });

  it('uses the same voices as generate_episodes_media.js', () => {
    assert.equal(lessonVoice('サーレム', 'سالم'), 'ash');
    assert.ok(['coral', 'nova', 'shimmer', 'sage'].includes(lessonVoice('ユキ', 'يوكي')));
    assert.notEqual(lessonVoice('入国審査官', 'موظف الجوازات'), 'ash');
    assert.equal(toSpeech('〜をください。「はい」'), 'をください。 はい');
  });

  it('ignores unknown files', async () => {
    const la = new LessonAudio(index, async () => new Uint8Array([1]), mkdtempSync(join(tmpdir(), 'la-')));
    assert.equal(la.has('../../etc/passwd'), false);
    assert.equal(await la.get('nope.mp3'), undefined);
  });
});

describe('LessonAudio', () => {
  const clip: LessonClip = { file: 'x_01.mp3', kind: 'line', text: 'こんにちは', voice: 'sage' };

  it('generates once, then serves from cache (also across restarts via disk)', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'la-'));
    let calls = 0;
    const synth = async () => {
      calls++;
      await new Promise((r) => setTimeout(r, 5));
      return new Uint8Array([1, 2, 3]);
    };
    const la = new LessonAudio(new Map([[clip.file, clip]]), synth, dir);
    const [a, b] = await Promise.all([la.get(clip.file), la.get(clip.file)]); // concurrent: one provider call
    assert.deepEqual([...a!], [1, 2, 3]);
    assert.deepEqual([...b!], [1, 2, 3]);
    await la.get(clip.file);
    assert.equal(calls, 1);

    const fresh = new LessonAudio(new Map([[clip.file, clip]]), synth, dir); // new process, same disk
    assert.deepEqual([...(await fresh.get(clip.file))!], [1, 2, 3]);
    assert.equal(calls, 1);
  });

  it('does not cache failures', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'la-'));
    let fail = true;
    const la = new LessonAudio(new Map([[clip.file, clip]]), async () => {
      if (fail) throw new Error('boom');
      return new Uint8Array([9]);
    }, dir);
    await assert.rejects(() => la.get(clip.file), /boom/);
    fail = false;
    assert.deepEqual([...(await la.get(clip.file))!], [9]);
  });
});
