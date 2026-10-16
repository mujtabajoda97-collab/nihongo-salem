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

  Future<void> reset() async {
    state = const KanaProgress();
    await ref.read(sharedPreferencesProvider).remove(kKanaProgressKey);
  }
}
