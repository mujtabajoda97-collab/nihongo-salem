import 'dart:math';

import 'json_helpers.dart';

/// Mirrors assets/data/placement_test_logic.json.
class PlacementTest {
  const PlacementTest({
    required this.testId,
    required this.version,
    required this.level,
    required this.titleAr,
    required this.titleJp,
    required this.instructionsAr,
    required this.settings,
    required this.scoring,
    required this.questions,
    required this.resultScreen,
  });

  factory PlacementTest.fromJson(Map<String, dynamic> j) {
    const ctx = 'placement test: ';
    return PlacementTest(
      testId: reqString(j, 'test_id', ctx: ctx),
      version: reqString(j, 'version', ctx: ctx),
      level: reqString(j, 'level', ctx: ctx),
      titleAr: reqString(j, 'title_ar', ctx: ctx),
      titleJp: reqString(j, 'title_jp', ctx: ctx),
      instructionsAr: reqString(j, 'instructions_ar', ctx: ctx),
      settings: PlacementSettings.fromJson(reqMap(j, 'settings', ctx: ctx)),
      scoring: PlacementScoring.fromJson(reqMap(j, 'scoring', ctx: ctx)),
      questions: reqObjects(j, 'questions', PlacementQuestion.fromJson,
          ctx: ctx),
      resultScreen:
          PlacementResultScreen.fromJson(reqMap(j, 'result_screen', ctx: ctx)),
    );
  }

  final String testId;
  final String version;
  final String level;
  final String titleAr;
  final String titleJp;
  final String instructionsAr;
  final PlacementSettings settings;
  final PlacementScoring scoring;
  final List<PlacementQuestion> questions;
  final PlacementResultScreen resultScreen;

  /// Scores the test.
  ///
  /// [answers] maps a question id to the selected index in the ORIGINAL
  /// `options` order (so the UI may shuffle freely and map back). A missing key
  /// or a `null` value means the learner chose "لا أعرف".
  PlacementResult evaluate(Map<int, int?> answers) {
    var correct = 0;
    var incorrect = 0;
    final missed = <PlacementQuestion>[];

    for (final q in questions) {
      final selected = answers[q.id];
      if (selected == null) {
        missed.add(q);
        if (settings.skipCountsAsIncorrect) incorrect++;
      } else if (q.isCorrect(selected)) {
        correct++;
      } else {
        missed.add(q);
        incorrect++;
      }
    }

    final raw = correct * scoring.pointsPerCorrect +
        incorrect * scoring.pointsPerIncorrect;
    final score = raw.clamp(0, scoring.maxScore).toInt();
    final rule = scoring.ruleFor(score);

    return PlacementResult(
      score: score,
      maxScore: scoring.maxScore,
      rule: rule,
      startEpisode: rule?.startEpisode ?? scoring.fallbackStartEpisode,
      missed: missed,
    );
  }
}

class PlacementSettings {
  const PlacementSettings({
    required this.questionCount,
    required this.shuffleOptions,
    required this.allowSkip,
    required this.skipLabelAr,
    required this.skipCountsAsIncorrect,
    required this.showFeedbackAfterEachQuestion,
    required this.showReviewAtEnd,
  });

  factory PlacementSettings.fromJson(Map<String, dynamic> j) {
    const ctx = 'placement settings: ';
    return PlacementSettings(
      questionCount: reqInt(j, 'question_count', ctx: ctx),
      shuffleOptions: reqBool(j, 'shuffle_options', ctx: ctx),
      allowSkip: reqBool(j, 'allow_skip', ctx: ctx),
      skipLabelAr: reqString(j, 'skip_label_ar', ctx: ctx),
      skipCountsAsIncorrect:
          reqString(j, 'skip_counts_as', ctx: ctx) == 'incorrect',
      showFeedbackAfterEachQuestion:
          reqBool(j, 'show_feedback_after_each_question', ctx: ctx),
      showReviewAtEnd: reqBool(j, 'show_review_at_end', ctx: ctx),
    );
  }

  final int questionCount;
  final bool shuffleOptions;
  final bool allowSkip;
  final String skipLabelAr;
  final bool skipCountsAsIncorrect;
  final bool showFeedbackAfterEachQuestion;
  final bool showReviewAtEnd;
}

class PlacementRule {
  const PlacementRule({
    required this.minScore,
    required this.maxScore,
    required this.startEpisode,
    required this.startSeason,
    required this.labelAr,
    required this.messageAr,
  });

  factory PlacementRule.fromJson(Map<String, dynamic> j, String ctx) =>
      PlacementRule(
        minScore: reqInt(j, 'min_score', ctx: ctx),
        maxScore: reqInt(j, 'max_score', ctx: ctx),
        startEpisode: reqInt(j, 'start_episode', ctx: ctx),
        startSeason: reqInt(j, 'start_season', ctx: ctx),
        labelAr: reqString(j, 'label_ar', ctx: ctx),
        messageAr: reqString(j, 'message_ar', ctx: ctx),
      );

  final int minScore;
  final int maxScore;
  final int startEpisode;
  final int startSeason;
  final String labelAr;
  final String messageAr;

  bool covers(int score) => score >= minScore && score <= maxScore;
}

class PlacementScoring {
  const PlacementScoring({
    required this.pointsPerCorrect,
    required this.pointsPerIncorrect,
    required this.maxScore,
    required this.rules,
    required this.fallbackStartEpisode,
  });

  factory PlacementScoring.fromJson(Map<String, dynamic> j) {
    const ctx = 'placement scoring: ';
    return PlacementScoring(
      pointsPerCorrect: reqInt(j, 'points_per_correct', ctx: ctx),
      pointsPerIncorrect: reqInt(j, 'points_per_incorrect', ctx: ctx),
      maxScore: reqInt(j, 'max_score', ctx: ctx),
      rules: reqObjects(j, 'placement_rules', PlacementRule.fromJson, ctx: ctx),
      fallbackStartEpisode: reqInt(
        reqMap(j, 'fallback_rule', ctx: ctx),
        'start_episode',
        ctx: '${ctx}fallback_rule: ',
      ),
    );
  }

  final int pointsPerCorrect;
  final int pointsPerIncorrect;
  final int maxScore;
  final List<PlacementRule> rules;
  final int fallbackStartEpisode;

  PlacementRule? ruleFor(int score) {
    for (final r in rules) {
      if (r.covers(score)) return r;
    }
    return null;
  }
}

class PlacementQuestion {
  const PlacementQuestion({
    required this.id,
    required this.difficulty,
    required this.skill,
    required this.skillAr,
    required this.type,
    required this.questionAr,
    required this.promptJp,
    required this.options,
    required this.correctIndex,
    required this.explanationAr,
    required this.relatedEpisode,
  });

  factory PlacementQuestion.fromJson(Map<String, dynamic> j, String ctx) {
    final options = reqStringList(j, 'options', ctx: ctx);
    final correct = reqInt(j, 'correct_index', ctx: ctx);
    if (correct < 0 || correct >= options.length) {
      throw FormatException('${ctx}correct_index $correct is out of range');
    }
    return PlacementQuestion(
      id: reqInt(j, 'id', ctx: ctx),
      difficulty: reqInt(j, 'difficulty', ctx: ctx),
      skill: reqString(j, 'skill', ctx: ctx),
      skillAr: reqString(j, 'skill_ar', ctx: ctx),
      type: reqString(j, 'type', ctx: ctx),
      questionAr: reqString(j, 'question_ar', ctx: ctx),
      promptJp: reqString(j, 'prompt_jp', ctx: ctx),
      options: options,
      correctIndex: correct,
      explanationAr: reqString(j, 'explanation_ar', ctx: ctx),
      relatedEpisode: reqInt(j, 'related_episode', ctx: ctx),
    );
  }

  final int id;
  final int difficulty;
  final String skill;
  final String skillAr;
  final String type;
  final String questionAr;

  /// Japanese sentence shown under the question. May be empty.
  final String promptJp;
  final List<String> options;
  final int correctIndex;
  final String explanationAr;

  /// Episode that teaches this skill (shown in the result review).
  final int relatedEpisode;

  bool isCorrect(int selectedIndex) => selectedIndex == correctIndex;

  /// Display order for the options: indexes into [options], shuffled.
  List<int> shuffledOptionOrder(Random random) =>
      [for (var i = 0; i < options.length; i++) i]..shuffle(random);
}

class PlacementResultScreen {
  const PlacementResultScreen({
    required this.titleAr,
    required this.scoreTemplateAr,
    required this.skillsBreakdown,
    required this.skillsBreakdownNoteAr,
    required this.ctaAr,
    required this.secondaryCtaAr,
  });

  factory PlacementResultScreen.fromJson(Map<String, dynamic> j) {
    const ctx = 'placement result_screen: ';
    return PlacementResultScreen(
      titleAr: reqString(j, 'title_ar', ctx: ctx),
      scoreTemplateAr: reqString(j, 'score_template_ar', ctx: ctx),
      skillsBreakdown: reqBool(j, 'skills_breakdown', ctx: ctx),
      skillsBreakdownNoteAr:
          reqString(j, 'skills_breakdown_note_ar', ctx: ctx),
      ctaAr: reqString(j, 'cta_ar', ctx: ctx),
      secondaryCtaAr: reqString(j, 'secondary_cta_ar', ctx: ctx),
    );
  }

  final String titleAr;
  final String scoreTemplateAr;
  final bool skillsBreakdown;
  final String skillsBreakdownNoteAr;
  final String ctaAr;
  final String secondaryCtaAr;

  String scoreText(int score, int maxScore) => scoreTemplateAr
      .replaceAll('{score}', '$score')
      .replaceAll('{max_score}', '$maxScore');

  String ctaText(int startEpisode) =>
      ctaAr.replaceAll('{start_episode}', '$startEpisode');
}

class PlacementResult {
  const PlacementResult({
    required this.score,
    required this.maxScore,
    required this.rule,
    required this.startEpisode,
    required this.missed,
  });

  final int score;
  final int maxScore;

  /// Null when no rule covers the score (fallback to episode 1 was used).
  final PlacementRule? rule;
  final int startEpisode;

  /// Wrong or skipped questions, in test order; the result screen groups them
  /// by [PlacementQuestion.skillAr] and shows [PlacementQuestion.relatedEpisode].
  final List<PlacementQuestion> missed;

  bool get usedFallback => rule == null;
}
