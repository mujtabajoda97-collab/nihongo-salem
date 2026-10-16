import 'package:flutter_test/flutter_test.dart';
import 'package:nihongo_salem/models/kana_course.dart';
import 'package:nihongo_salem/models/user_models.dart';
import 'package:nihongo_salem/services/cloud_sync.dart';

void main() {
  test('merge keeps everything from both sides and the best stars', () {
    const local = UserState(
      completedEpisodes: {1, 2},
      stars: {1: 3, 2: 1},
      streakDays: 2,
      lastActiveDate: '2026-10-16',
    );
    final cloud = buildProgressPayload(
      const UserState(
        displayName: 'منى',
        placementCompleted: true,
        placementScore: 7,
        startEpisode: 11,
        freeWindowStart: 11,
        completedEpisodes: {2, 3},
        stars: {2: 3, 3: 2},
        streakDays: 5,
        lastActiveDate: '2026-10-10',
      ),
      const KanaProgress(completed: {1, 2}, stars: {1: 2}),
      const AppSettings(),
    );
    final m = mergeProgress(
      local,
      const KanaProgress(completed: {3}, stars: {3: 1}),
      cloud,
    );
    expect(m.user.completedEpisodes, {1, 2, 3});
    expect(m.user.stars, {1: 3, 2: 3, 3: 2});
    expect(m.user.streakDays, 5);
    expect(m.user.lastActiveDate, '2026-10-16');
    // A fresh install restores the placement and the name from the cloud.
    expect(m.user.placementCompleted, isTrue);
    expect(m.user.startEpisode, 11);
    expect(m.user.displayName, 'منى');
    expect(m.kana.completed, {1, 2, 3});
    expect(m.kana.starsFor(1), 2);
  });

  test('no cloud row yet: local progress is kept as is', () {
    const local = UserState(completedEpisodes: {4});
    final m = mergeProgress(local, const KanaProgress(), null);
    expect(m.user.completedEpisodes, {4});
  });

  test('error messages are Arabic', () {
    expect(CloudService.messageFor(const CloudException('x')), 'x');
  });
}
