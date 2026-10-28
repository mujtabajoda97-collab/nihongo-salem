import { AudioStore } from './audioStore.ts';
import type { Config } from './config.ts';
import { UpstreamError } from './http.ts';
import { GREETINGS, voiceKeyForTone } from './personas.ts';
import type { Prompts } from './prompts.ts';
import { fillTemplate, sanitizeValue } from './prompts.ts';
import { generateTurn, LlmFormatError } from './providers/llm.ts';
import { cleanTranscript, transcribe } from './providers/stt.ts';
import { synthesize } from './providers/tts.ts';
import type { SessionStore } from './sessions.ts';
import type { AiTurn, Mode, PersonaKey, TurnRequest, TurnResponse, TutorTone, TtsProvider } from './types.ts';
import { END_CALL_MESSAGE, PERSONA_KEYS, TUTOR_TONES } from './types.ts';

/** A problem with the request itself (HTTP 4xx). */
export class RequestError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = 'RequestError';
    this.status = status;
    this.code = code;
  }
}

export interface TurnDeps {
  cfg: Config;
  prompts: Prompts;
  sessions: SessionStore;
  audio: AudioStore;
  /** Public base URL used to build audio_url, e.g. https://api.example.com */
  baseUrl: string;
  log?: (msg: string) => void;
  /** Receives how long each stage took (no learner content, safe to log). */
  timing?: (t: Record<string, string | number | boolean>) => void;
}

// ---------------------------------------------------------------------------
// Request validation
// ---------------------------------------------------------------------------

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function readBool(v: unknown): boolean {
  return v === true || (typeof v === 'string' && v.trim().toLowerCase() === 'true');
}

/**
 * Checks the JSON sent by the app (TutorTurnRequest / FreeTalkTurnRequest) and
 * returns a clean request. `lesson_roleplay` is accepted as another name of
 * `episode_tutor`.
 */
export function validateRequest(raw: unknown, cfg: Config, audio?: Uint8Array): TurnRequest {
  if (!isObject(raw)) throw new RequestError(400, 'bad_payload', 'payload must be a JSON object');

  const sessionId = typeof raw.session_id === 'string' ? raw.session_id.trim() : '';
  if (!/^[\w.-]{1,100}$/.test(sessionId)) {
    throw new RequestError(400, 'bad_session_id', 'session_id is required (letters, digits, - _ .)');
  }

  let mode: Mode;
  if (raw.mode === 'episode_tutor' || raw.mode === 'lesson_roleplay') mode = 'episode_tutor';
  else if (raw.mode === 'free_talk') mode = 'free_talk';
  else throw new RequestError(400, 'bad_mode', 'mode must be episode_tutor, lesson_roleplay or free_talk');

  let ttsProvider: TtsProvider = cfg.defaultTtsProvider;
  if (raw.tts_provider !== undefined) {
    if (raw.tts_provider !== 'openai' && raw.tts_provider !== 'elevenlabs') {
      throw new RequestError(400, 'bad_tts_provider', 'tts_provider must be openai or elevenlabs');
    }
    ttsProvider = raw.tts_provider;
  }

  const variables: Record<string, string> = {};
  if (raw.variables !== undefined) {
    if (!isObject(raw.variables)) throw new RequestError(400, 'bad_variables', 'variables must be an object');
    const entries = Object.entries(raw.variables);
    if (entries.length > 40) throw new RequestError(400, 'bad_variables', 'too many variables');
    for (const [k, v] of entries) {
      if (!/^[A-Z0-9_]{1,40}$/.test(k)) continue;
      if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') {
        variables[k] = sanitizeValue(String(v));
      }
    }
  }

  let userMessage: string | undefined;
  if (raw.user_message !== undefined && raw.user_message !== null) {
    if (typeof raw.user_message !== 'string') {
      throw new RequestError(400, 'bad_user_message', 'user_message must be a string');
    }
    userMessage = raw.user_message.trim();
    if (userMessage.length > cfg.maxTextChars) {
      throw new RequestError(413, 'message_too_long', `user_message is longer than ${cfg.maxTextChars} characters`);
    }
    if (userMessage === '') userMessage = undefined;
  }

  const isFirstTurn = readBool(raw.is_first_turn);
  let voiceKey: PersonaKey;

  if (mode === 'episode_tutor') {
    const tone = (raw.tone ?? 'polite_encouraging') as TutorTone;
    if (!(TUTOR_TONES as readonly string[]).includes(tone)) {
      throw new RequestError(400, 'bad_tone', 'tone must be polite_encouraging, strict_tsundere or friendly_peer');
    }
    voiceKey = voiceKeyForTone(tone);
    variables.TONE = tone;
    if (raw.episode_id !== undefined) variables.EPISODE_ID = String(raw.episode_id);
    if (!variables.EPISODE_SCENARIO) {
      throw new RequestError(400, 'missing_scenario', 'variables.EPISODE_SCENARIO is required in episode_tutor mode');
    }
    variables.USER_NAME ||= 'サーレム';
  } else {
    const persona = raw.persona as PersonaKey;
    if (!(PERSONA_KEYS as readonly string[]).includes(persona)) {
      throw new RequestError(400, 'bad_persona', 'persona must be polite_sensei, casual_friend, tsundere or kansai');
    }
    voiceKey = persona;
    variables.PERSONA = persona;
    variables.IS_FIRST_TURN = String(isFirstTurn);
    variables.USER_NAME ||= 'サーレム';
    variables.USER_PROGRESS ||= '0';
    variables.KNOWN_VOCAB ||= '';
    variables.LOCAL_TIME ||= '12:00';
  }

  if (audio && audio.byteLength > cfg.maxAudioBytes) {
    throw new RequestError(413, 'audio_too_large', 'audio file is too large');
  }

  return { sessionId, mode, ttsProvider, voiceKey, variables, userMessage, isFirstTurn, audio };
}

// ---------------------------------------------------------------------------
// The pipeline: Whisper -> Claude -> TTS
// ---------------------------------------------------------------------------

/** Used when Whisper heard nothing usable (silence, noise). No AI call, nothing saved. */
function notHeardReply(): TurnResponse {
  return {
    correction_ar: 'لم أسمع صوتك بوضوح. قرّب الميكروفون وحاول مرة أخرى.',
    reply_japanese: 'すみません、もう いちど おねがいします。',
    reply_romaji: 'Sumimasen, mō ichido onegaishimasu.',
    reply_arabic: 'عفواً، أعد من فضلك مرة أخرى.',
    emotion_tone: 'calm',
    has_mistake: false,
    conversation_completed: false,
    user_transcript: '',
  };
}

function firstTurnNudge(mode: Mode): string {
  return mode === 'free_talk'
    ? '(The call has just started.)'
    : '(The learner has just entered the scene. Say your opening line.)';
}

export async function runTurn(deps: TurnDeps, req: TurnRequest): Promise<TurnResponse> {
  const { cfg } = deps;
  const log = deps.log ?? (() => {});
  const t: Record<string, string | number | boolean> = {
    mode: req.mode,
    first: req.isFirstTurn,
    audioBytes: req.audio?.byteLength ?? 0,
  };
  const report = () => deps.timing?.(t);
  let mark = Date.now();
  const lap = (name: string) => {
    const now = Date.now();
    t[name] = now - mark;
    mark = now;
  };

  // 1. Listen
  let userText = req.userMessage;
  let transcript: string | undefined;
  if (req.audio) {
    const text = cleanTranscript(await transcribe(cfg, req.audio));
    lap('sttMs');
    if (text === '') {
      t.heard = false;
      report();
      return notHeardReply();
    }
    transcript = text;
    userText = text;
  }
  if (!userText && !req.isFirstTurn) {
    throw new RequestError(400, 'empty_turn', 'send user_message or an audio file');
  }

  // 2. Think
  const template = req.mode === 'free_talk' ? deps.prompts.freeTalk : deps.prompts.tutor;
  const system = fillTemplate(template, req.variables);
  const history = deps.sessions.get(req.sessionId);
  const content = userText ?? firstTurnNudge(req.mode);
  const isEndCall = req.mode === 'free_talk' && userText === END_CALL_MESSAGE;

  let turn: AiTurn;
  try {
    turn = await generateTurn(cfg, system, history, content);
    lap('llmMs');
  } catch (e) {
    if (e instanceof LlmFormatError) {
      throw new UpstreamError('llm', 502, `llm answer was not valid: ${e.message}`);
    }
    throw e;
  }

  // 3. Guard rails that must not depend on the model's mood
  if (req.mode === 'free_talk' && req.isFirstTurn && !userText) {
    const g = GREETINGS[req.voiceKey];
    turn = {
      ...turn,
      reply_japanese: g.jp,
      reply_romaji: g.romaji,
      reply_arabic: g.ar,
      has_mistake: false,
      conversation_completed: false,
    };
  }
  if (isEndCall) turn = { ...turn, conversation_completed: true, has_mistake: false };
  if (req.isFirstTurn && !userText) turn = { ...turn, has_mistake: false };

  deps.sessions.append(req.sessionId, content, JSON.stringify(turn));

  // 4. Speak
  const response: TurnResponse = { ...turn };
  if (transcript !== undefined) response.user_transcript = transcript;

  const cacheKey = AudioStore.keyFor(
    req.ttsProvider, req.voiceKey, turn.emotion_tone, turn.reply_japanese, cfg.openaiTtsModel, cfg.elevenlabsModel,
  );
  let audioId = deps.audio.find(cacheKey);
  let inline: { data: Uint8Array; mime: string } | undefined;
  if (!audioId) {
    const speech = await synthesize(cfg, req.ttsProvider, turn.reply_japanese, req.voiceKey, turn.emotion_tone, log);
    if (speech) {
      if (cfg.audioDelivery === 'base64') inline = speech;
      else audioId = deps.audio.put(speech.data, speech.mime, cacheKey);
    }
  }
  lap('ttsMs');
  t.audio = Boolean(inline || audioId);
  report();
  if (inline) {
    response.audio_url = `data:${inline.mime};base64,${Buffer.from(inline.data).toString('base64')}`;
  } else if (audioId) {
    response.audio_url = `${deps.baseUrl}/v1/audio/${audioId}.mp3`;
  }
  return response;
}
