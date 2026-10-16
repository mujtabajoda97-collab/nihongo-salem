/** The four voices of the app. Lesson tones map onto them (see personas.ts). */
export type PersonaKey = 'polite_sensei' | 'casual_friend' | 'tsundere' | 'kansai';
export type TutorTone = 'polite_encouraging' | 'strict_tsundere' | 'friendly_peer';
export type Emotion = 'happy' | 'strict' | 'sigh' | 'excited' | 'calm';
export type TtsProvider = 'openai' | 'elevenlabs';
export type Mode = 'episode_tutor' | 'free_talk';

/** The 7-key JSON both prompts return. */
export interface AiTurn {
  correction_ar: string;
  reply_japanese: string;
  reply_romaji: string;
  reply_arabic: string;
  emotion_tone: Emotion;
  has_mistake: boolean;
  conversation_completed: boolean;
}

/** What the app gets back: the 7 keys + optional extras. */
export interface TurnResponse extends AiTurn {
  user_transcript?: string;
  audio_url?: string;
}

/** A validated request. */
export interface TurnRequest {
  sessionId: string;
  mode: Mode;
  ttsProvider: TtsProvider;
  voiceKey: PersonaKey;
  /** Template variables of the matching prompt file. */
  variables: Record<string, string>;
  userMessage?: string;
  isFirstTurn: boolean;
  /** Recorded learner audio (m4a), if this is a voice turn. */
  audio?: Uint8Array;
}

export interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}

export const EMOTIONS: readonly Emotion[] = ['happy', 'strict', 'sigh', 'excited', 'calm'];
export const PERSONA_KEYS: readonly PersonaKey[] = [
  'polite_sensei',
  'casual_friend',
  'tsundere',
  'kansai',
];
export const TUTOR_TONES: readonly TutorTone[] = [
  'polite_encouraging',
  'strict_tsundere',
  'friendly_peer',
];
export const END_CALL_MESSAGE = '__END_CALL__';
