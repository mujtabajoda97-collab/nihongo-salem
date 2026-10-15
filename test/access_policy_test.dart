import 'package:flutter_test/flutter_test.dart';
import 'package:nihongo_salem/models/enums.dart';
import 'package:nihongo_salem/models/user_models.dart';
import 'package:nihongo_salem/services/access_policy.dart';

UserState _user({
  int start = 1,
  Set<int> done = const {},
  bool placed = true,
}) =>
    UserState(
      placementCompleted: placed,
      startEpisode: start,
      freeWindowStart: placed ? start : null,
      completedEpisodes: done,
    );

EpisodeLock _lock(int ep, UserState u, {bool premium = false}) =>
    AccessPolicy.episodeAccess(episodeId: ep, user: u, isPremium: premium).lock;

void main() {
  test('nothing opens before the placement step', () {
    expect(_lock(1, _user(placed: false)), EpisodeLock.placementRequired);
  });

  test('free: two episodes from the start point, one after the other', () {
    for (final start in [1, 11, 21]) {
      final u = _user(start: start);
      expect(AccessPolicy.freeEpisodeIds(u), {start, start + 1});
      expect(_lock(start, u), EpisodeLock.none);
      expect(_lock(start + 1, u), EpisodeLock.notYetReached);
      final after = _user(start: start, done: {start});
      expect(_lock(start + 1, after), EpisodeLock.none);
      expect(_lock(start + 2, after), EpisodeLock.requiresPremium);
    }
  });

  test('free: everything before the start point is behind the paywall', () {
    final u = _user(start: 11);
    expect(_lock(1, u), EpisodeLock.requiresPremium);
    expect(_lock(10, u), EpisodeLock.requiresPremium);
  });

  test('premium: sequential, earlier episodes open for review', () {
    final u = _user(start: 11, done: {11, 12});
    expect(_lock(1, u, premium: true), EpisodeLock.none);
    expect(_lock(13, u, premium: true), EpisodeLock.none);
    expect(_lock(14, u, premium: true), EpisodeLock.notYetReached);
  });

  test('reachedEpisode never exceeds 40', () {
    final u = _user(done: {for (var i = 1; i <= 40; i++) i});
    expect(u.reachedEpisode, 40);
    expect(u.finishedAllEpisodes, isTrue);
  });

  test('free window stops at episode 40', () {
    expect(AccessPolicy.freeEpisodeIds(_user(start: 40)), {40});
  });

  test('personas: two free, four for subscribers', () {
    final free = Persona.values
        .where((p) => AccessPolicy.canUsePersona(p, isPremium: false));
    expect(free, [Persona.politeSensei, Persona.casualFriend]);
    expect(
        Persona.values
            .every((p) => AccessPolicy.canUsePersona(p, isPremium: true)),
        isTrue);
  });

  test('call quota: 5 free minutes, unlimited for subscribers', () {
    expect(AccessPolicy.remainingCallSeconds(isPremium: false, usedSecondsToday: 0), 300);
    expect(AccessPolicy.remainingCallSeconds(isPremium: false, usedSecondsToday: 299), 1);
    expect(AccessPolicy.remainingCallSeconds(isPremium: false, usedSecondsToday: 400), 0);
    expect(AccessPolicy.remainingCallSeconds(isPremium: true, usedSecondsToday: 9999), isNull);
    expect(AccessPolicy.canStartCall(0), isFalse);
    expect(AccessPolicy.canStartCall(null), isTrue);
  });

  test('user state survives a JSON round trip', () {
    final u = UserState(
      displayName: 'سالم',
      placementCompleted: true,
      placementScore: 8,
      startEpisode: 21,
      freeWindowStart: 21,
      completedEpisodes: {21, 22},
      stars: {21: 3, 22: 2},
      streakDays: 4,
      lastActiveDate: '2026-10-16',
    );
    final back = UserState.fromJson(u.toJson());
    expect(back.toJson(), u.toJson());
    expect(back.totalStars, 5);
  });
}
