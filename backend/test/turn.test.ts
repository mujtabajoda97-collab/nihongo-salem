import assert from 'node:assert/strict';
import { afterEach, describe, it } from 'node:test';
import { UpstreamError } from '../src/http.ts';
import { cleanTranscript } from '../src/providers/stt.ts';
import { cleanForSpeech } from '../src/providers/tts.ts';
import { RequestError, runTurn, validateRequest } from '../src/turn.ts';
import { aiTurn, claudeReply, json, makeConfig, makeDeps, mockFetch, mp3, standardRoutes } from './helpers.ts';

let restore = () => {};
afterEach(() => restore());

// What the Flutter app really sends (see lib/models/ai_turn.dart).
const tutorPayload = (over: Record<string, unknown> = {}) => ({
  session_id: 'sess-1',
  mode: 'episode_tutor',
  episode_id: 3,
  tone: 'strict_tsundere',
  user_name: 'サーレム',
  variables: {
    TONE: 'strict_tsundere', EPISODE_ID: '3', EPISODE_TITLE_AR: 'عنوان', EPISODE_SCENARIO: 'You are a station clerk.',
    INITIAL_AI_MESSAGE: 'どこへ 行きますか。', EPISODE_VOCAB: 'えき = محطة', EPISODE_GRAMMAR: '〜へ 行きます', USER_NAME: 'サーレム',
  },
  tts_provider: 'openai',
  is_first_turn: false,
  user_message: 'しぶやを 行きます。',
  ...over,
});

const freePayload = (over: Record<string, unknown> = {}) => ({
  session_id: 'call-1',
  mode: 'free_talk',
  persona: 'kansai',
  tts_provider: 'openai',
  variables: { PERSONA: 'kansai', USER_NAME: 'サーレム', USER_PROGRESS: '14', KNOWN_VOCAB: 'ねこ', LOCAL_TIME: '08:15', IS_FIRST_TURN: 'false' },
  is_first_turn: false,
  user_message: 'おはよう',
  ...over,
});

const AUDIO = new Uint8Array([1, 2, 3, 4]);

describe('validateRequest', () => {
  const cfg = makeConfig();

  it('accepts both app payloads; lesson_roleplay is an alias', () => {
    assert.equal(validateRequest(tutorPayload(), cfg).mode, 'episode_tutor');
    assert.equal(validateRequest(tutorPayload({ mode: 'lesson_roleplay' }), cfg).voiceKey, 'tsundere');
    const free = validateRequest(freePayload(), cfg);
    assert.equal(free.voiceKey, 'kansai');
    assert.equal(free.variables.IS_FIRST_TURN, 'false');
  });

  it('rejects bad input with a 4xx RequestError', () => {
    const bad = (p: unknown, code: string) =>
      assert.throws(() => validateRequest(p, cfg), (e: unknown) => e instanceof RequestError && e.code === code && e.status >= 400 && e.status < 500);
    bad(null, 'bad_payload');
    bad(tutorPayload({ session_id: '' }), 'bad_session_id');
    bad(tutorPayload({ session_id: 'a b/../c' }), 'bad_session_id');
    bad(tutorPayload({ mode: 'other' }), 'bad_mode');
    bad(tutorPayload({ tone: 'angry' }), 'bad_tone');
    bad(tutorPayload({ tts_provider: 'google' }), 'bad_tts_provider');
    bad(tutorPayload({ variables: { TONE: 'x' } }), 'missing_scenario');
    bad(freePayload({ persona: 'robot' }), 'bad_persona');
    bad(freePayload({ user_message: 'あ'.repeat(5000) }), 'message_too_long');
    assert.throws(() => validateRequest(freePayload(), cfg, new Uint8Array(cfg.maxAudioBytes + 1)), RequestError);
  });

  it('removes placeholder syntax from variables', () => {
    const r = validateRequest(freePayload({ variables: { USER_NAME: '{{PERSONA}} evil' } }), cfg);
    assert.ok(!r.variables.USER_NAME!.includes('{{'));
  });
});

describe('runTurn: episode tutor', () => {
  it('text turn: calls only Claude and TTS, fills the lesson prompt, returns the 7 keys + audio_url', async () => {
    const m = mockFetch(standardRoutes({ turn: aiTurn({ has_mistake: true, emotion_tone: 'sigh' }) }));
    restore = m.restore;
    const deps = makeDeps();
    const res = await runTurn(deps, validateRequest(tutorPayload(), deps.cfg));

    assert.deepEqual(Object.keys(res).sort(), [
      'audio_url', 'conversation_completed', 'correction_ar', 'emotion_tone',
      'has_mistake', 'reply_arabic', 'reply_japanese', 'reply_romaji',
    ]);
    assert.equal(res.has_mistake, true);
    assert.match(res.audio_url!, /^https:\/\/api\.test\/v1\/audio\/[0-9a-f]{32}\.mp3$/);
    assert.equal(res.user_transcript, undefined);

    const claude = m.calls.find((c) => c.url.includes('anthropic'))!;
    assert.ok(claude.json.system[0].text.includes('You are a station clerk.'));
    assert.ok(!claude.json.system[0].text.includes('{{'));
    assert.equal(claude.json.messages.at(-1).content, 'しぶやを 行きます。');
    assert.ok(!m.calls.some((c) => c.url.includes('transcriptions')));

    const tts = m.calls.find((c) => c.url.includes('/audio/speech'))!;
    assert.equal(tts.json.model, 'gpt-4o-mini-tts');
    assert.equal(tts.json.input, 'そうですか。');
    assert.equal(tts.json.voice, deps.cfg.openaiVoices.tsundere);
    assert.match(tts.json.instructions, /sassy[\s\S]*exasperated/i);
  });

  it('voice turn: Whisper gets m4a + language ja, transcript is returned and used', async () => {
    const m = mockFetch(standardRoutes({ transcript: 'しぶやへ いきます' }));
    restore = m.restore;
    const deps = makeDeps();
    const res = await runTurn(deps, validateRequest(tutorPayload({ user_message: undefined }), deps.cfg, AUDIO));

    const stt = m.calls.find((c) => c.url.includes('transcriptions'))!;
    assert.equal(stt.form!.get('model'), 'whisper-1');
    assert.equal(stt.form!.get('language'), 'ja');
    assert.equal((stt.form!.get('file') as File).name, 'turn.m4a');
    assert.equal(res.user_transcript, 'しぶやへ いきます');
    const claude = m.calls.find((c) => c.url.includes('anthropic'))!;
    assert.equal(claude.json.messages.at(-1).content, 'しぶやへ いきます');
  });

  it('remembers earlier turns of the same session only', async () => {
    const m = mockFetch(standardRoutes());
    restore = m.restore;
    const deps = makeDeps();
    await runTurn(deps, validateRequest(tutorPayload({ user_message: 'ひとつめ' }), deps.cfg));
    await runTurn(deps, validateRequest(tutorPayload({ user_message: 'ふたつめ' }), deps.cfg));
    await runTurn(deps, validateRequest(tutorPayload({ session_id: 'other', user_message: 'べつ' }), deps.cfg));

    const claudeCalls = m.calls.filter((c) => c.url.includes('anthropic'));
    assert.deepEqual(claudeCalls[1]!.json.messages.map((x: any) => x.role), ['user', 'assistant', 'user']);
    assert.equal(claudeCalls[1]!.json.messages[0].content, 'ひとつめ');
    assert.equal(claudeCalls[2]!.json.messages.length, 1);
  });

  it('a turn without text or audio is a 400', async () => {
    const m = mockFetch(standardRoutes());
    restore = m.restore;
    const deps = makeDeps();
    await assert.rejects(runTurn(deps, validateRequest(tutorPayload({ user_message: undefined }), deps.cfg)), RequestError);
    assert.equal(m.calls.length, 0);
  });
});

describe('runTurn: free talk', () => {
  it('first turn: the greeting is forced to the exact persona text', async () => {
    const m = mockFetch(standardRoutes({ turn: aiTurn({ reply_japanese: 'やあ！', has_mistake: true }) }));
    restore = m.restore;
    const deps = makeDeps();
    const res = await runTurn(deps, validateRequest(freePayload({ is_first_turn: true, user_message: undefined }), deps.cfg));
    assert.equal(res.reply_japanese, 'まいど！元気しとる？今日も楽しくしゃべろか！');
    assert.equal(res.reply_romaji, 'Maido! Genki shitoru? Kyō mo tanoshiku shaberoka!');
    assert.equal(res.has_mistake, false);
    const claude = m.calls.find((c) => c.url.includes('anthropic'))!;
    assert.ok(claude.json.system[0].text.includes('Current persona: kansai'));
    assert.equal(claude.json.messages[0].content, '(The call has just started.)');
    const tts = m.calls.find((c) => c.url.includes('/audio/speech'))!;
    assert.equal(tts.json.input, 'まいど！元気しとる？今日も楽しくしゃべろか！');
  });

  it('the same greeting is not paid for twice (audio reused)', async () => {
    const m = mockFetch(standardRoutes());
    restore = m.restore;
    const deps = makeDeps();
    const first = await runTurn(deps, validateRequest(freePayload({ session_id: 'c1', is_first_turn: true, user_message: undefined }), deps.cfg));
    const second = await runTurn(deps, validateRequest(freePayload({ session_id: 'c2', is_first_turn: true, user_message: undefined }), deps.cfg));
    assert.equal(first.audio_url, second.audio_url);
    assert.equal(m.calls.filter((c) => c.url.includes('/audio/speech')).length, 1);
  });

  it('__END_CALL__ is sent to Claude as is and always ends the call', async () => {
    const m = mockFetch(standardRoutes({ turn: aiTurn({ conversation_completed: false, has_mistake: true }) }));
    restore = m.restore;
    const deps = makeDeps();
    const res = await runTurn(deps, validateRequest(freePayload({ user_message: '__END_CALL__' }), deps.cfg));
    const claude = m.calls.find((c) => c.url.includes('anthropic'))!;
    assert.equal(claude.json.messages.at(-1).content, '__END_CALL__');
    assert.equal(res.conversation_completed, true);
    assert.equal(res.has_mistake, false);
  });

  it('silence / Whisper hallucination: friendly reply, no Claude, no TTS', async () => {
    const m = mockFetch(standardRoutes({ transcript: 'ご視聴ありがとうございました' }));
    restore = m.restore;
    const deps = makeDeps();
    const res = await runTurn(deps, validateRequest(freePayload({ user_message: undefined }), deps.cfg, AUDIO));
    assert.equal(res.user_transcript, '');
    assert.equal(res.has_mistake, false);
    assert.equal(res.audio_url, undefined);
    assert.deepEqual(m.calls.map((c) => c.url.includes('transcriptions')), [true]);
    assert.equal(deps.sessions.size, 0);
  });
});

describe('TTS choices', () => {
  it('ElevenLabs: right voice, model and emotion settings', async () => {
    const m = mockFetch(standardRoutes({ turn: aiTurn({ emotion_tone: 'excited' }) }));
    restore = m.restore;
    const deps = makeDeps(makeConfig({ ELEVENLABS_API_KEY: 'xi', ELEVENLABS_VOICE_ID: 'VOICE1', ELEVENLABS_VOICE_KANSAI: 'OSAKA' }));
    const res = await runTurn(deps, validateRequest(freePayload({ tts_provider: 'elevenlabs' }), deps.cfg));
    const tts = m.calls.find((c) => c.url.includes('elevenlabs.io'))!;
    assert.match(tts.url, /text-to-speech\/OSAKA\?output_format=mp3_/);
    assert.equal((tts.init.headers as any)['xi-api-key'], 'xi');
    assert.equal(tts.json.model_id, 'eleven_multilingual_v2');
    assert.equal(tts.json.voice_settings.stability, 0.3);
    assert.ok(res.audio_url);
    assert.ok(!m.calls.some((c) => c.url.includes('/audio/speech')));
  });

  it('ElevenLabs asked but not configured: falls back to OpenAI', async () => {
    const m = mockFetch(standardRoutes());
    restore = m.restore;
    const deps = makeDeps();
    const res = await runTurn(deps, validateRequest(freePayload({ tts_provider: 'elevenlabs' }), deps.cfg));
    assert.ok(res.audio_url);
    assert.ok(m.calls.some((c) => c.url.includes('/audio/speech')));
  });

  it('TTS down everywhere: the text reply still succeeds, without audio_url', async () => {
    const m = mockFetch((c) =>
      c.url.includes('anthropic') ? claudeReply(aiTurn()) : json({ error: 'nope' }, 400));
    restore = m.restore;
    const deps = makeDeps();
    const res = await runTurn(deps, validateRequest(freePayload(), deps.cfg));
    assert.equal(res.reply_japanese, 'そうですか。');
    assert.equal(res.audio_url, undefined);
  });

  it('base64 delivery returns a data URL', async () => {
    const m = mockFetch(standardRoutes());
    restore = m.restore;
    const deps = makeDeps(makeConfig({ AUDIO_DELIVERY: 'base64' }));
    const res = await runTurn(deps, validateRequest(freePayload(), deps.cfg));
    assert.match(res.audio_url!, /^data:audio\/mpeg;base64,/);
    assert.equal(deps.audio.size, 0);
  });

  it('stored clip is retrievable by the id inside audio_url', async () => {
    const m = mockFetch(standardRoutes());
    restore = m.restore;
    const deps = makeDeps();
    const res = await runTurn(deps, validateRequest(freePayload(), deps.cfg));
    const id = res.audio_url!.split('/').pop()!.replace('.mp3', '');
    assert.deepEqual([...deps.audio.get(id)!.data], [0x49, 0x44, 0x33, 1, 2, 3]);
  });
});

describe('failures', () => {
  it('Claude down: UpstreamError (the HTTP layer answers 502), nothing saved', async () => {
    const m = mockFetch(() => json({ error: 'down' }, 500));
    restore = m.restore;
    const deps = makeDeps();
    await assert.rejects(runTurn(deps, validateRequest(freePayload(), deps.cfg)), (e: unknown) => e instanceof UpstreamError && e.service === 'llm');
    assert.equal(deps.sessions.size, 0);
  });

  it('model keeps returning garbage: UpstreamError', async () => {
    const m = mockFetch(() => claudeReply('hello there'));
    restore = m.restore;
    const deps = makeDeps();
    await assert.rejects(runTurn(deps, validateRequest(freePayload(), deps.cfg)), UpstreamError);
  });

  it('Whisper down: UpstreamError (stt)', async () => {
    const m = mockFetch(() => json({ error: 'x' }, 401));
    restore = m.restore;
    const deps = makeDeps();
    await assert.rejects(runTurn(deps, validateRequest(freePayload({ user_message: undefined }), deps.cfg, AUDIO)), (e: unknown) => e instanceof UpstreamError && e.service === 'stt');
  });
});

describe('text cleaning', () => {
  it('cleanTranscript', () => {
    assert.equal(cleanTranscript('  。。 '), '');
    assert.equal(cleanTranscript('ご視聴ありがとうございました。'), '');
    assert.equal(cleanTranscript(' おはよう '), 'おはよう');
  });
  it('cleanForSpeech drops emoji and brackets, keeps Japanese punctuation', () => {
    assert.equal(cleanForSpeech('やった！😀 (すごい) ね？'), 'やった！ すごい ね？');
  });
});
