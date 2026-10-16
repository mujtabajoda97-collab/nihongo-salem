import 'dart:math';

import 'episode.dart';
import 'kana_course.dart';

/// Gentle warm-up before an episode's sentence questions, in three small levels:
///   1. listen and pick the letter      (only the letters of this episode)
///   2. see a letter and pick its sound
///   3. words: listen / read a single word and pick its meaning
/// No full sentences, so a learner who knows no letters yet can still succeed.
List<KanaQuestion> buildEpisodeWarmup({
  required Episode episode,
  required List<KanaChar> letters,
  required List<KanaChar> allLetters,
  required Random rnd,
}) {
  final out = <KanaQuestion>[];

  // Distractor pool: letters that appear in this episode's words + the new ones.
  final seen = <String>{for (final l in letters) l.char};
  for (final v in episode.vocabulary) {
    for (final ch in v.kana.runes.map(String.fromCharCode)) {
      seen.add(ch);
    }
  }
  final pool = allLetters.where((c) => seen.contains(c.char)).toList();

  for (final l in letters) {
    out.add(makeKanaQuestion(rnd,
        kind: KanaQuestionKind.listenPickChar,
        prompt: 'استمع ثم اختر الحرف الصحيح',
        audio: l.audio,
        correct: l.char,
        pool: pool.map((c) => c.char),
        japaneseOptions: true));
  }
  for (final l in letters) {
    out.add(makeKanaQuestion(rnd,
        kind: KanaQuestionKind.charPickSound,
        prompt: l.char,
        hint: 'كيف يُنطق هذا الحرف؟',
        correct: l.romaji,
        pool: pool.map((c) => c.romaji)));
  }

  final words = [...episode.vocabulary]..shuffle(rnd);
  final meanings = episode.vocabulary.map((v) => v.arabic);
  for (var i = 0; i < words.length && i < 4; i++) {
    final w = words[i];
    out.add(i < 2
        ? makeKanaQuestion(rnd,
            kind: KanaQuestionKind.listenPickMeaning,
            prompt: 'استمع ثم اختر المعنى',
            audio: w.audio,
            correct: w.arabic,
            pool: meanings)
        : makeKanaQuestion(rnd,
            kind: KanaQuestionKind.wordPickMeaning,
            prompt: w.kana,
            audio: w.audio,
            hint: 'ما معنى هذه الكلمة؟',
            correct: w.arabic,
            pool: meanings));
  }
  return out;
}
