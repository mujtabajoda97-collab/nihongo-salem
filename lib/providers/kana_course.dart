import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/kana_course.dart';
import 'providers.dart';

const kKanaCourseAsset = 'assets/data/kana_course.json';
const kKanaProgressKey = 'kana_progress_v1';

/// The bundled beginner course (letters -> words -> sentences).
final kanaCourseProvider = FutureProvider<KanaCourse>((ref) async {
  final source = await rootBundle.loadString(kKanaCourseAsset);
  return KanaCourse.fromJsonString(source);
});

final kanaProgressProvider =
    NotifierProvider<KanaProgressController, KanaProgress>(KanaProgressController.new);

class KanaProgressController extends Notifier<KanaProgress> {
  @override
  KanaProgress build() => KanaProgress.fromJsonString(
        ref.read(sharedPreferencesProvider).getString(kKanaProgressKey),
      );

  void complete(int lessonId, {required int stars}) {
    state = state.withCompleted(lessonId, stars.clamp(0, 3).toInt());
    unawaited(ref
        .read(sharedPreferencesProvider)
        .setString(kKanaProgressKey, state.toJsonString()));
    ref.read(userStateProvider.notifier).touchActivity();
  }

  void replaceFromCloud(KanaProgress merged) {
    state = merged;
    unawaited(ref
        .read(sharedPreferencesProvider)
        .setString(kKanaProgressKey, merged.toJsonString()));
  }

  Future<void> reset() async {
    state = const KanaProgress();
    await ref.read(sharedPreferencesProvider).remove(kKanaProgressKey);
  }
}

/// Letters taught inside each episode (see tool/make_episode_letters.py).
final episodeLettersMapProvider = FutureProvider<Map<int, List<EpisodeLetter>>>((ref) async {
  return parseEpisodeLetters(await rootBundle.loadString('assets/data/episode_letters.json'));
});

/// The ready-to-show letter cards of one episode (empty when it adds none).
final episodeLetterCardsProvider =
    FutureProvider.family<List<KanaChar>, int>((ref, episodeId) async {
  final course = await ref.watch(kanaCourseProvider.future);
  final map = await ref.watch(episodeLettersMapProvider.future);
  final byChar = {
    for (final l in course.lessons)
      for (final c in l.chars) c.char: c,
  };
  return [
    for (final e in map[episodeId] ?? const <EpisodeLetter>[])
      if (byChar[e.char] != null) e.toKanaChar(byChar[e.char]!),
  ];
});
