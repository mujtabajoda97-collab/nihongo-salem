import 'dart:convert';
import 'dart:math';

import 'json_helpers.dart';

/// The beginner course: Japanese letters first (hiragana), then words, then
/// light sentences. Content lives in assets/data/kana_course.json (built by
/// tool/make_kana_course.py).
enum KanaLessonKind { intro, letters, review, words, sentences }

KanaLessonKind _kindOf(String s) => KanaLessonKind.values.firstWhere(
      (k) => k.name == s,
      orElse: () => throw FormatException('unknown lesson kind "$s"'),
    );

class KanaWord {
  const KanaWord({
    required this.jp,
    required this.romaji,
    required this.ar,
    required this.emoji,
    required this.audio,
  });

  factory KanaWord.fromJson(Map<String, dynamic> j, [String ctx = '']) =>
      KanaWord(
        jp: reqString(j, 'jp', ctx: ctx),
        romaji: reqString(j, 'romaji', ctx: ctx),
        ar: reqString(j, 'ar', ctx: ctx),
        emoji: reqString(j, 'emoji', ctx: ctx),
        audio: reqString(j, 'audio', ctx: ctx),
      );

  final String jp;
  final String romaji;
  final String ar;
  final String emoji;
  final String audio;
}

class KanaChar {
  const KanaChar({
    required this.char,
    required this.romaji,
    required this.soundAr,
    required this.noteAr,
    required this.strokes,
    required this.tipAr,
    required this.audio,
    required this.word,
  });

  factory KanaChar.fromJson(Map<String, dynamic> j, [String ctx = '']) =>
      KanaChar(
        char: reqString(j, 'char', ctx: ctx),
        romaji: reqString(j, 'romaji', ctx: ctx),
        soundAr: reqString(j, 'sound_ar', ctx: ctx),
        noteAr: reqString(j, 'note_ar', ctx: ctx),
        strokes: reqInt(j, 'strokes', ctx: ctx),
        tipAr: reqString(j, 'tip_ar', ctx: ctx),
        audio: reqString(j, 'audio', ctx: ctx),
        word: KanaWord.fromJson(reqMap(j, 'word', ctx: ctx), '${ctx}word: '),
      );

  final String char;
  final String romaji;
  final String soundAr;
  final String noteAr;
  final int strokes;
  final String tipAr;
  final String audio;
  final KanaWord word;
}

class KanaPage {
  const KanaPage({required this.titleAr, required this.glyph, required this.bodyAr});

  factory KanaPage.fromJson(Map<String, dynamic> j, [String ctx = '']) =>
      KanaPage(
        titleAr: reqString(j, 'title_ar', ctx: ctx),
        glyph: reqString(j, 'glyph', ctx: ctx),
        bodyAr: reqString(j, 'body_ar', ctx: ctx),
      );

  final String titleAr;
  final String glyph;
  final String bodyAr;
}

class KanaLesson {
  const KanaLesson({
    required this.id,
    required this.stage,
    required this.kind,
    required this.titleAr,
    required this.subtitleAr,
    required this.noteAr,
    required this.chars,
    required this.items,
    required this.pages,
  });

  factory KanaLesson.fromJson(Map<String, dynamic> j, [String ctx = '']) =>
      KanaLesson(
        id: reqInt(j, 'id', ctx: ctx),
        stage: reqInt(j, 'stage', ctx: ctx),
        kind: _kindOf(reqString(j, 'kind', ctx: ctx)),
        titleAr: reqString(j, 'title_ar', ctx: ctx),
        subtitleAr: reqString(j, 'subtitle_ar', ctx: ctx),
        noteAr: reqString(j, 'note_ar', ctx: ctx),
        chars: reqObjects(j, 'chars', KanaChar.fromJson, ctx: ctx),
        items: reqObjects(j, 'items', KanaWord.fromJson, ctx: ctx),
        pages: reqObjects(j, 'pages', KanaPage.fromJson, ctx: ctx),
      );

  final int id;
  final int stage;
  final KanaLessonKind kind;
  final String titleAr;
  final String subtitleAr;
  final String noteAr;
  final List<KanaChar> chars;
  final List<KanaWord> items;
  final List<KanaPage> pages;

  bool get isStudyList => kind != KanaLessonKind.letters && kind != KanaLessonKind.intro;
}

class KanaStage {
  const KanaStage({required this.id, required this.titleAr, required this.descAr});

  factory KanaStage.fromJson(Map<String, dynamic> j, [String ctx = '']) =>
      KanaStage(
        id: reqInt(j, 'id', ctx: ctx),
        titleAr: reqString(j, 'title_ar', ctx: ctx),
        descAr: reqString(j, 'desc_ar', ctx: ctx),
      );

  final int id;
  final String titleAr;
  final String descAr;
}

class KanaCourse {
  const KanaCourse({required this.stages, required this.lessons});

  factory KanaCourse.fromJsonString(String source) {
    final raw = jsonDecode(source);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('kana course must be a JSON object');
    }
    final lessons = reqObjects(raw, 'lessons', KanaLesson.fromJson);
    for (var i = 0; i < lessons.length; i++) {
      if (lessons[i].id != i + 1) {
        throw FormatException('lesson ids must be 1..n in order, got ${lessons[i].id} at $i');
      }
    }
    return KanaCourse(
      stages: reqObjects(raw, 'stages', KanaStage.fromJson),
      lessons: lessons,
    );
  }

  final List<KanaStage> stages;
  final List<KanaLesson> lessons;

  KanaLesson lessonById(int id) => lessons[id - 1];

  List<KanaLesson> inStage(int stage) =>
      lessons.where((l) => l.stage == stage).toList(growable: false);

  /// Number of lessons that teach new letters (what the learner sees as "الحروف").
  int get letterLessonCount =>
      lessons.where((l) => l.kind == KanaLessonKind.letters).length;

  /// Letters taught up to and including [lessonId] (used for quiz distractors).
  List<KanaChar> charsUpTo(int lessonId) => [
        for (final l in lessons)
          if (l.id <= lessonId) ...l.chars,
      ];

  /// Words/items known up to and including [lessonId].
  List<KanaWord> wordsUpTo(int lessonId) => [
        for (final l in lessons)
          if (l.id <= lessonId) ...[for (final c in l.chars) c.word, ...l.items],
      ];
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------

class KanaProgress {
  const KanaProgress({this.completed = const {}, this.stars = const {}});

  factory KanaProgress.fromJsonString(String? source) {
    if (source == null) return const KanaProgress();
    try {
      final raw = jsonDecode(source);
      if (raw is! Map<String, dynamic>) return const KanaProgress();
      final done = <int>{
        for (final v in (raw['completed'] as List<dynamic>? ?? const []))
          if (v is int) v,
      };
      final stars = <int, int>{};
      final rawStars = raw['stars'];
      if (rawStars is Map<String, dynamic>) {
        rawStars.forEach((k, v) {
          final id = int.tryParse(k);
          if (id != null && v is int) stars[id] = v.clamp(0, 3).toInt();
        });
      }
      return KanaProgress(completed: done, stars: stars);
    } on Object {
      return const KanaProgress();
    }
  }

  final Set<int> completed;
  final Map<int, int> stars;

  String toJsonString() => jsonEncode({
        'completed': completed.toList()..sort(),
        'stars': {for (final e in stars.entries) '${e.key}': e.value},
      });

  bool isCompleted(int id) => completed.contains(id);
  int starsFor(int id) => stars[id] ?? 0;

  /// Lessons open one after the other. Finished lessons stay open.
  bool isUnlocked(int id) => id <= 1 || completed.contains(id) || completed.contains(id - 1);

  /// The first lesson that is not finished yet (null when all are done).
  int? nextLesson(int total) {
    for (var i = 1; i <= total; i++) {
      if (!completed.contains(i)) return i;
    }
    return null;
  }

  KanaProgress withCompleted(int id, int newStars) => KanaProgress(
        completed: {...completed, id},
        stars: {...stars, id: newStars > starsFor(id) ? newStars : starsFor(id)},
      );
}

// ---------------------------------------------------------------------------
// Quiz
// ---------------------------------------------------------------------------

enum KanaQuestionKind { listenPickChar, charPickSound, wordPickMeaning, listenPickMeaning }

class KanaQuestion {
  const KanaQuestion({
    required this.kind,
    required this.prompt,
    required this.options,
    required this.answer,
    this.audio,
    this.hint,
    this.japaneseOptions = false,
  });

  final KanaQuestionKind kind;

  /// What is shown (a letter, a word or an Arabic instruction).
  final String prompt;
  final String? hint;
  final String? audio;
  final List<String> options;
  final int answer;

  /// true when the options are Japanese text (shown left-to-right, larger).
  final bool japaneseOptions;

  String get correct => options[answer];
}

List<String> _distractors(String correct, Iterable<String> pool, int n, Random rnd) {
  final unique = <String>{
    for (final p in pool)
      if (p != correct) p,
  }.toList()
    ..shuffle(rnd);
  return unique.take(n).toList();
}

KanaQuestion _make(
  Random rnd, {
  required KanaQuestionKind kind,
  required String prompt,
  required String correct,
  required Iterable<String> pool,
  String? audio,
  String? hint,
  bool japaneseOptions = false,
}) {
  final options = [correct, ..._distractors(correct, pool, 3, rnd)]..shuffle(rnd);
  return KanaQuestion(
    kind: kind,
    prompt: prompt,
    hint: hint,
    audio: audio,
    options: options,
    answer: options.indexOf(correct),
    japaneseOptions: japaneseOptions,
  );
}

/// Builds the short quiz that ends a lesson. Distractors come from the same
/// lesson first and then from everything learned before, so a beginner is
/// never asked about a letter they have not met.
List<KanaQuestion> buildKanaQuiz(KanaLesson lesson, KanaCourse course, Random rnd) {
  final out = <KanaQuestion>[];
  if (lesson.kind == KanaLessonKind.letters) {
    final chars = course.charsUpTo(lesson.id);
    final words = course.wordsUpTo(lesson.id);
    for (final c in lesson.chars) {
      final glyphPool = [...lesson.chars.map((e) => e.char), ...chars.map((e) => e.char)];
      final soundPool = [...lesson.chars.map((e) => e.romaji), ...chars.map((e) => e.romaji)];
      out.add(_make(rnd,
          kind: KanaQuestionKind.listenPickChar,
          prompt: 'استمع ثم اختر الحرف الصحيح',
          audio: c.audio,
          correct: c.char,
          pool: glyphPool,
          japaneseOptions: true));
      out.add(_make(rnd,
          kind: KanaQuestionKind.charPickSound,
          prompt: c.char,
          hint: 'كيف يُنطق هذا الحرف؟',
          correct: c.romaji,
          pool: soundPool));
      out.add(_make(rnd,
          kind: KanaQuestionKind.wordPickMeaning,
          prompt: c.word.jp,
          audio: c.word.audio,
          hint: 'ما معنى هذه الكلمة؟',
          correct: c.word.ar,
          pool: words.map((w) => w.ar)));
    }
  } else if (lesson.isStudyList) {
    final pool = course.wordsUpTo(lesson.id).map((w) => w.ar);
    final items = [...lesson.items]..shuffle(rnd);
    for (var i = 0; i < items.length && out.length < 12; i++) {
      final w = items[i];
      out.add(i.isEven
          ? _make(rnd,
              kind: KanaQuestionKind.listenPickMeaning,
              prompt: 'استمع ثم اختر المعنى',
              audio: w.audio,
              correct: w.ar,
              pool: pool)
          : _make(rnd,
              kind: KanaQuestionKind.wordPickMeaning,
              prompt: w.jp,
              audio: w.audio,
              hint: 'ما معنى هذه الكلمة؟',
              correct: w.ar,
              pool: pool));
    }
  }
  out.shuffle(rnd);
  return out;
}

/// 3 stars with no mistakes, 2 with up to two, otherwise 1.
int starsForMistakes(int mistakes) => mistakes == 0 ? 3 : (mistakes <= 2 ? 2 : 1);
