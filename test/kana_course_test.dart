import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nihongo_salem/models/episode.dart';
import 'package:nihongo_salem/models/episode_warmup.dart';
import 'package:nihongo_salem/models/kana_course.dart';

KanaCourse loadCourse() =>
    KanaCourse.fromJsonString(File('assets/data/kana_course.json').readAsStringSync());

void main() {
  final course = loadCourse();

  test('course has the expected shape', () {
    expect(course.lessons.length, greaterThan(60));
    expect(course.lessons.first.kind, KanaLessonKind.intro);
    expect(course.stages.length, 6);
    final base = course.lessons
        .where((l) => l.stage == 2 && l.kind == KanaLessonKind.letters)
        .expand((l) => l.chars)
        .toList();
    expect(base.length, 46); // the 46 basic hiragana
    for (final l in course.lessons.where((l) => l.kind == KanaLessonKind.letters)) {
      expect(l.chars.length, inInclusiveRange(1, 2), reason: 'lesson ${l.id}: 1-2 new letters');
    }
  });

  test('every audio path points to a clip listed in the file', () {
    final raw = jsonDecode(File('assets/data/kana_course.json').readAsStringSync())
        as Map<String, dynamic>;
    final files = {
      for (final c in raw['clips'] as List<dynamic>) 'assets/audio/${(c as Map)['file']}'
    };
    for (final l in course.lessons) {
      for (final c in l.chars) {
        expect(files, contains(c.audio));
        expect(files, contains(c.word.audio));
      }
      for (final i in l.items) {
        expect(files, contains(i.audio));
      }
    }
  });

  test('progress unlocks lessons one after the other and survives a round trip', () {
    var p = const KanaProgress();
    expect(p.isUnlocked(1), isTrue);
    expect(p.isUnlocked(2), isFalse);
    p = p.withCompleted(1, 2);
    expect(p.isUnlocked(2), isTrue);
    expect(p.nextLesson(5), 2);
    p = p.withCompleted(1, 1); // stars only go up
    expect(p.starsFor(1), 2);
    final again = KanaProgress.fromJsonString(p.toJsonString());
    expect(again.completed, {1});
    expect(again.starsFor(1), 2);
    expect(KanaProgress.fromJsonString('not json').completed, isEmpty);
  });

  test('quiz questions are well formed for every lesson', () {
    final rnd = Random(7);
    for (final l in course.lessons) {
      final quiz = buildKanaQuiz(l, course, rnd);
      if (l.kind == KanaLessonKind.intro) {
        expect(quiz, isEmpty);
        continue;
      }
      expect(quiz, isNotEmpty, reason: 'lesson ${l.id}');
      for (final q in quiz) {
        expect(q.options.toSet().length, q.options.length, reason: 'lesson ${l.id} duplicate options');
        expect(q.options.length, greaterThanOrEqualTo(2), reason: 'lesson ${l.id}');
        expect(q.answer, inInclusiveRange(0, q.options.length - 1));
      }
    }
  });

  test('stars follow the mistakes', () {
    expect(starsForMistakes(0), 3);
    expect(starsForMistakes(2), 2);
    expect(starsForMistakes(5), 1);
  });

  test('every episode with letters gets a gentle warm-up of letters then words', () {
    final map = parseEpisodeLetters(File('assets/data/episode_letters.json').readAsStringSync());
    final byChar = {
      for (final l in course.lessons) for (final c in l.chars) c.char: c,
    };
    final seen = <String>{};
    for (var id = 1; id <= 40; id++) {
      final letters = map[id] ?? const <EpisodeLetter>[];
      expect(letters.length, lessThanOrEqualTo(2), reason: 'episode $id');
      for (final e in letters) {
        expect(byChar, contains(e.char));
        expect(seen.add(e.char), isTrue, reason: '${e.char} taught twice');
      }
      if (letters.isEmpty) continue;
      final episode = Episode.fromJson(jsonDecode(
          File('assets/data/episodes/episode_${id.toString().padLeft(2, '0')}.json')
              .readAsStringSync()) as Map<String, dynamic>);
      final cards = [for (final e in letters) e.toKanaChar(byChar[e.char]!)];
      final quiz = buildEpisodeWarmup(
        episode: episode,
        letters: cards,
        allLetters: byChar.values.toList(),
        rnd: Random(id),
      );
      expect(quiz.first.kind, KanaQuestionKind.listenPickChar);
      for (final q in quiz) {
        expect(q.options.toSet().length, q.options.length);
        expect(q.options.length, greaterThanOrEqualTo(2));
      }
    }
  });
}
