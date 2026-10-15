import '../core/constants.dart';
import 'enums.dart';
import 'json_helpers.dart';

/// One line of the visual-novel scene (station A).
class Dialogue {
  const Dialogue({
    required this.id,
    required this.speakerNameJp,
    required this.speakerNameAr,
    required this.characterAvatar,
    required this.audioFile,
    required this.japanese,
    required this.romaji,
    required this.arabic,
  });

  factory Dialogue.fromJson(Map<String, dynamic> j, String ctx) => Dialogue(
        id: reqInt(j, 'id', ctx: ctx),
        speakerNameJp: reqString(j, 'speaker_name_jp', ctx: ctx),
        speakerNameAr: reqString(j, 'speaker_name_ar', ctx: ctx),
        characterAvatar: reqString(j, 'character_avatar', ctx: ctx),
        audioFile: reqString(j, 'audio_file', ctx: ctx),
        japanese: reqString(j, 'japanese', ctx: ctx),
        romaji: reqString(j, 'romaji', ctx: ctx),
        arabic: reqString(j, 'arabic', ctx: ctx),
      );

  final int id;
  final String speakerNameJp;
  final String speakerNameAr;
  final String characterAvatar;
  final String audioFile;
  final String japanese;
  final String romaji;
  final String arabic;

  /// True when the learner's own character (Salem) is speaking.
  bool get isLearnerLine => speakerNameJp == AppRules.learnerSpeakerJp;
}

/// A vocabulary card (station B). [kanji] is empty for kana-only words.
class VocabItem {
  const VocabItem({
    required this.kanji,
    required this.kana,
    required this.romaji,
    required this.arabic,
    required this.audio,
  });

  factory VocabItem.fromJson(Map<String, dynamic> j, String ctx) => VocabItem(
        kanji: reqString(j, 'kanji', ctx: ctx),
        kana: reqString(j, 'kana', ctx: ctx),
        romaji: reqString(j, 'romaji', ctx: ctx),
        arabic: reqString(j, 'arabic', ctx: ctx),
        audio: reqString(j, 'audio', ctx: ctx),
      );

  final String kanji;
  final String kana;
  final String romaji;
  final String arabic;
  final String audio;

  bool get hasKanji => kanji.isNotEmpty && kanji != kana;

  /// The big text on the card: the kanji form if there is one, otherwise the kana.
  String get headline => hasKanji ? kanji : kana;
}

class GrammarPoint {
  const GrammarPoint({
    required this.titleAr,
    required this.pattern,
    required this.explanationAr,
  });

  factory GrammarPoint.fromJson(Map<String, dynamic> j, String ctx) =>
      GrammarPoint(
        titleAr: reqString(j, 'title_ar', ctx: ctx),
        pattern: reqString(j, 'pattern', ctx: ctx),
        explanationAr: reqString(j, 'explanation_ar', ctx: ctx),
      );

  final String titleAr;
  final String pattern;
  final String explanationAr;
}

/// A quiz question (station C). The JSON `type` decides the subclass.
sealed class QuizItem {
  const QuizItem({
    required this.id,
    required this.questionAr,
    required this.explanationAr,
  });

  factory QuizItem.fromJson(Map<String, dynamic> j, String ctx) {
    final type = reqString(j, 'type', ctx: ctx);
    return switch (type) {
      'multiple_choice' => MultipleChoiceQuiz.fromJson(j, ctx),
      'word_order' => WordOrderQuiz.fromJson(j, ctx),
      _ => throw FormatException('${ctx}unknown quiz type "$type"'),
    };
  }

  final int id;
  final String questionAr;
  final String explanationAr;
}

final class MultipleChoiceQuiz extends QuizItem {
  const MultipleChoiceQuiz({
    required super.id,
    required super.questionAr,
    required super.explanationAr,
    required this.options,
    required this.correctIndex,
  });

  factory MultipleChoiceQuiz.fromJson(Map<String, dynamic> j, String ctx) {
    final options = reqStringList(j, 'options', ctx: ctx);
    final correct = reqInt(j, 'correct_index', ctx: ctx);
    if (correct < 0 || correct >= options.length) {
      throw FormatException('${ctx}correct_index $correct is out of range');
    }
    return MultipleChoiceQuiz(
      id: reqInt(j, 'id', ctx: ctx),
      questionAr: reqString(j, 'question_ar', ctx: ctx),
      explanationAr: reqString(j, 'explanation_ar', ctx: ctx),
      options: options,
      correctIndex: correct,
    );
  }

  /// Options in file order. Shuffle for display and keep the original index.
  final List<String> options;
  final int correctIndex;

  bool isCorrect(int selectedIndex) => selectedIndex == correctIndex;
}

final class WordOrderQuiz extends QuizItem {
  const WordOrderQuiz({
    required super.id,
    required super.questionAr,
    required super.explanationAr,
    required this.words,
    required this.correctOrder,
  });

  factory WordOrderQuiz.fromJson(Map<String, dynamic> j, String ctx) {
    final words = reqStringList(j, 'words', ctx: ctx);
    final order = reqStringList(j, 'correct_order', ctx: ctx);
    final a = [...words]..sort();
    final b = [...order]..sort();
    if (a.length != b.length || !_sameItems(a, b)) {
      throw FormatException('${ctx}correct_order does not match words');
    }
    return WordOrderQuiz(
      id: reqInt(j, 'id', ctx: ctx),
      questionAr: reqString(j, 'question_ar', ctx: ctx),
      explanationAr: reqString(j, 'explanation_ar', ctx: ctx),
      words: words,
      correctOrder: order,
    );
  }

  /// Word tiles as listed in the file (the tile bank; shuffle for display).
  final List<String> words;
  final List<String> correctOrder;

  bool isCorrect(List<String> answer) => _sameSequence(answer, correctOrder);

  static bool _sameItems(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _sameSequence(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Station D: the in-episode role-play with the AI tutor.
class AiRoleplay {
  const AiRoleplay({
    required this.systemScenario,
    required this.initialAiMessageJp,
    required this.initialAiMessageAr,
  });

  factory AiRoleplay.fromJson(Map<String, dynamic> j, String ctx) =>
      AiRoleplay(
        systemScenario: reqString(j, 'system_scenario', ctx: ctx),
        initialAiMessageJp: reqString(j, 'initial_ai_message_jp', ctx: ctx),
        initialAiMessageAr: reqString(j, 'initial_ai_message_ar', ctx: ctx),
      );

  /// English scenario text; goes into {{EPISODE_SCENARIO}}.
  final String systemScenario;
  final String initialAiMessageJp;
  final String initialAiMessageAr;
}

class Episode {
  const Episode({
    required this.id,
    required this.season,
    required this.level,
    required this.titleAr,
    required this.titleJp,
    required this.backgroundImage,
    required this.dialogues,
    required this.vocabulary,
    required this.grammarPoints,
    required this.quiz,
    required this.aiRoleplay,
  });

  factory Episode.fromJson(Map<String, dynamic> j) {
    final id = reqInt(j, 'episode_id');
    final ctx = 'episode $id: ';
    return Episode(
      id: id,
      season: reqInt(j, 'season', ctx: ctx),
      level: reqString(j, 'level', ctx: ctx),
      titleAr: reqString(j, 'title_ar', ctx: ctx),
      titleJp: reqString(j, 'title_jp', ctx: ctx),
      backgroundImage: reqString(j, 'background_image', ctx: ctx),
      dialogues: reqObjects(j, 'dialogues', Dialogue.fromJson, ctx: ctx),
      vocabulary: reqObjects(j, 'vocabulary', VocabItem.fromJson, ctx: ctx),
      grammarPoints:
          reqObjects(j, 'grammar_points', GrammarPoint.fromJson, ctx: ctx),
      quiz: reqObjects(j, 'quiz', QuizItem.fromJson, ctx: ctx),
      aiRoleplay: AiRoleplay.fromJson(reqMap(j, 'ai_roleplay', ctx: ctx), ctx),
    );
  }

  final int id;
  final int season;
  final String level;
  final String titleAr;
  final String titleJp;
  final String backgroundImage;
  final List<Dialogue> dialogues;
  final List<VocabItem> vocabulary;
  final List<GrammarPoint> grammarPoints;
  final List<QuizItem> quiz;
  final AiRoleplay aiRoleplay;

  /// `01` ... `40`
  String get code => id.toString().padLeft(2, '0');

  /// Template variables of ai_tutor_system_prompt.txt.
  Map<String, String> tutorVariables({
    required TutorTone tone,
    required String userName,
  }) =>
      {
        'TONE': tone.wire,
        'EPISODE_ID': '$id',
        'EPISODE_TITLE_AR': titleAr,
        'EPISODE_SCENARIO': aiRoleplay.systemScenario,
        'INITIAL_AI_MESSAGE': aiRoleplay.initialAiMessageJp,
        'EPISODE_VOCAB': vocabulary
            .map((v) => '${v.kana}${v.hasKanji ? ' (${v.kanji})' : ''}'
                ' = ${v.arabic}')
            .join(' | '),
        'EPISODE_GRAMMAR': grammarPoints.map((g) => g.pattern).join(' | '),
        'USER_NAME': userName,
      };

  /// Words of [episodes] for {{KNOWN_VOCAB}} in free_talk_personas_prompt.txt,
  /// newest episodes first, capped at [AppRules.maxKnownVocabWords].
  static String knownVocabString(Iterable<Episode> episodes) {
    final sorted = episodes.toList()..sort((a, b) => b.id.compareTo(a.id));
    final words = <String>{};
    for (final e in sorted) {
      for (final v in e.vocabulary) {
        if (words.length >= AppRules.maxKnownVocabWords) break;
        words.add(v.kana);
      }
    }
    return words.join('、');
  }
}
