import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihongo_salem/core/constants.dart';
import 'package:nihongo_salem/models/ai_turn.dart';
import 'package:nihongo_salem/models/enums.dart';
import 'package:nihongo_salem/models/episode.dart';
import 'package:nihongo_salem/models/placement_test.dart';

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Episode _episode(int id) => Episode.fromJson(_json(
    'assets/data/episodes/episode_${id.toString().padLeft(2, '0')}.json'));

PlacementTest _placement() =>
    PlacementTest.fromJson(_json('assets/data/placement_test_logic.json'));

void main() {
  group('episodes', () {
    test('all 40 files parse and keep the agreed shape', () {
      for (var id = 1; id <= AppRules.totalEpisodes; id++) {
        final e = _episode(id);
        expect(e.id, id);
        expect(e.season, (id - 1) ~/ AppRules.episodesPerSeason + 1);
        expect(e.level, 'JLPT_N5');
        expect(e.vocabulary.length, 8, reason: 'episode $id vocabulary');
        expect(e.grammarPoints.length, 2, reason: 'episode $id grammar');
        expect(e.quiz.length, 2, reason: 'episode $id quiz');
        expect(e.quiz.whereType<MultipleChoiceQuiz>().length, 1);
        expect(e.quiz.whereType<WordOrderQuiz>().length, 1);
        expect(e.dialogues, isNotEmpty);
      }
    });

    test('quiz answers are checked correctly', () {
      final e = _episode(1);
      final mc = e.quiz.whereType<MultipleChoiceQuiz>().single;
      expect(mc.isCorrect(mc.correctIndex), isTrue);
      expect(mc.isCorrect((mc.correctIndex + 1) % mc.options.length), isFalse);

      final wo = e.quiz.whereType<WordOrderQuiz>().single;
      expect(wo.isCorrect(wo.correctOrder), isTrue);
      expect(wo.isCorrect(wo.words), isFalse); // file order is shuffled
    });

    test('kana-only vocabulary uses the kana as headline', () {
      final ikura = _episode(2)
          .vocabulary
          .firstWhere((v) => v.kana == 'いくら');
      expect(ikura.hasKanji, isFalse);
      expect(ikura.headline, 'いくら');
      final kuukou = _episode(1).vocabulary.first;
      expect(kuukou.headline, '空港');
    });

    test('tutor variables contain every template key', () {
      final vars = _episode(3)
          .tutorVariables(tone: TutorTone.strictTsundere, userName: 'サーレム');
      expect(vars.keys, containsAll(<String>[
        'TONE',
        'EPISODE_ID',
        'EPISODE_TITLE_AR',
        'EPISODE_SCENARIO',
        'INITIAL_AI_MESSAGE',
        'EPISODE_VOCAB',
        'EPISODE_GRAMMAR',
        'USER_NAME',
      ]));
      expect(vars['TONE'], 'strict_tsundere');
    });

    test('known vocab is capped', () {
      final all = [for (var i = 1; i <= 40; i++) _episode(i)];
      final words = Episode.knownVocabString(all).split('、');
      expect(words.length, lessThanOrEqualTo(AppRules.maxKnownVocabWords));
    });
  });

  group('placement test', () {
    test('parses 10 questions', () {
      final t = _placement();
      expect(t.questions.length, 10);
      expect(t.settings.questionCount, 10);
    });

    Map<int, int?> answers(PlacementTest t, int correct) => {
          for (var i = 0; i < t.questions.length; i++)
            t.questions[i].id: i < correct ? t.questions[i].correctIndex : null,
        };

    test('score ranges map to episodes 1 / 11 / 21', () {
      final t = _placement();
      expect(t.evaluate(answers(t, 0)).startEpisode, 1);
      expect(t.evaluate(answers(t, 3)).startEpisode, 1);
      expect(t.evaluate(answers(t, 4)).startEpisode, 11);
      expect(t.evaluate(answers(t, 7)).startEpisode, 11);
      expect(t.evaluate(answers(t, 8)).startEpisode, 21);
      expect(t.evaluate(answers(t, 10)).startEpisode, 21);
    });

    test('skipped and wrong answers are listed as missed', () {
      final t = _placement();
      final r = t.evaluate(answers(t, 6));
      expect(r.score, 6);
      expect(r.missed.length, 4);
      expect(r.maxScore, 10);
      expect(t.resultScreen.scoreText(r.score, r.maxScore), contains('6'));
      expect(t.resultScreen.ctaText(11), contains('11'));
    });

    test('a wrong option does not score', () {
      final t = _placement();
      final wrong = {
        for (final q in t.questions) q.id: (q.correctIndex + 1) % q.options.length,
      };
      expect(t.evaluate(wrong).score, 0);
    });
  });

  group('AI response', () {
    test('parses the 7-key contract, including has_mistake', () {
      const raw = '{"correction_ar":"x","reply_japanese":"こんにちは","reply_romaji":"Konnichiwa",'
          '"reply_arabic":"مرحباً","emotion_tone":"sigh","has_mistake":true,'
          '"conversation_completed":false}';
      final r = AiTurnResponse.fromRawText(raw);
      expect(r.hasMistake, isTrue);
      expect(r.conversationCompleted, isFalse);
      expect(r.emotionTone, EmotionTone.sigh);
      expect(AiTurnResponse.fromJson(r.toJson()).replyJapanese, 'こんにちは');
    });

    test('tolerates a code fence and a missing has_mistake', () {
      const raw = '```json\n{"correction_ar":"x","reply_japanese":"a","reply_romaji":"a",'
          '"reply_arabic":"a","emotion_tone":"unknown","conversation_completed":"true"}\n```';
      final r = AiTurnResponse.fromRawText(raw);
      expect(r.hasMistake, isFalse);
      expect(r.conversationCompleted, isTrue);
      expect(r.emotionTone, EmotionTone.calm);
    });

    test('the end-call request carries the control message', () {
      final req = FreeTalkTurnRequest.endCall(
        sessionId: 's1',
        persona: Persona.kansai,
        userName: 'サーレム',
        userProgress: 5,
        knownVocab: '',
        localTime: '08:15',
        ttsProvider: TtsProvider.elevenlabs,
      ).toJson();
      expect(req['user_message'], '__END_CALL__');
      expect(req['persona'], 'kansai');
      expect(req['tts_provider'], 'elevenlabs');
    });
  });
}
