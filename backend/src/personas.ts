import type { Emotion, PersonaKey, TutorTone } from './types.ts';

/** Exact greetings from free_talk_personas_prompt.txt (same texts as the Flutter app). */
export const GREETINGS: Record<PersonaKey, { jp: string; romaji: string; ar: string }> = {
  polite_sensei: {
    jp: 'こんにちは！今日も一緒に日本語を練習しましょう。',
    romaji: 'Konnichiwa! Kyō mo issho ni nihongo o renshū shimashō.',
    ar: 'مرحباً! لنتدرب على اليابانية معاً اليوم أيضاً.',
  },
  casual_friend: {
    jp: 'よっ！元気？今何してるの？ご飯食べた？',
    romaji: 'Yo! Genki? Ima nani shiteru no? Gohan tabeta?',
    ar: 'هلا! كيفك؟ شو تسوي الحين؟ أكلت؟',
  },
  tsundere: {
    jp: 'はぁ？また来たの？まあいいよ、早く始めて！',
    romaji: 'Hā? Mata kita no? Mā ii yo, hayaku hajimete!',
    ar: 'ها؟ جئت مجدداً؟ حسناً، هيا ابدأ بسرعة!',
  },
  kansai: {
    jp: 'まいど！元気しとる？今日も楽しくしゃべろか！',
    romaji: 'Maido! Genki shitoru? Kyō mo tanoshiku shaberoka!',
    ar: 'أهلاً! كيف حالك؟ لنتحدث بمرح اليوم أيضاً!',
  },
};

/** In lessons the tone picks the voice character. */
export function voiceKeyForTone(tone: TutorTone): PersonaKey {
  switch (tone) {
    case 'strict_tsundere':
      return 'tsundere';
    case 'friendly_peer':
      return 'casual_friend';
    default:
      return 'polite_sensei';
  }
}

export const DEFAULT_OPENAI_VOICES: Record<PersonaKey, string> = {
  polite_sensei: 'sage',
  casual_friend: 'coral',
  tsundere: 'shimmer',
  kansai: 'ash',
};

// ---- gpt-4o-mini-tts "instructions" -------------------------------------

const PERSONA_STYLE: Record<PersonaKey, string> = {
  polite_sensei: 'A calm, respectful, patient Japanese teacher. Clear standard pronunciation, slightly slow.',
  casual_friend: 'An energetic, upbeat young Japanese friend. Casual and natural, relaxed rhythm.',
  tsundere: 'A sassy anime-style character: fake annoyance and playful grumbling, but never cruel.',
  kansai: 'A very cheerful, funny person from Osaka with a warm Kansai accent and lively rhythm.',
};

const EMOTION_STYLE: Record<Emotion, string> = {
  happy: 'Warm and smiling.',
  strict: 'Firm and a little stern, but playful.',
  sigh: 'Exasperated and weary, as if sighing before the sentence.',
  excited: 'High energy and enthusiastic.',
  calm: 'Gentle and relaxed.',
};

export function openAiInstructions(voice: PersonaKey, emotion: Emotion): string {
  return (
    `Speak Japanese for a beginner learner: articulate every word clearly, natural intonation, no rushing. ` +
    `${PERSONA_STYLE[voice]} ${EMOTION_STYLE[emotion]}`
  );
}

// ---- ElevenLabs voice settings ------------------------------------------

export const ELEVEN_SETTINGS: Record<Emotion, { stability: number; style: number }> = {
  calm: { stability: 0.6, style: 0.1 },
  happy: { stability: 0.45, style: 0.3 },
  strict: { stability: 0.55, style: 0.4 },
  sigh: { stability: 0.5, style: 0.35 },
  excited: { stability: 0.3, style: 0.6 },
};
