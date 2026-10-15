import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihongo_salem/models/enums.dart';
import 'package:nihongo_salem/models/placement_test.dart';
import 'package:nihongo_salem/providers/providers.dart';
import 'package:nihongo_salem/services/entitlement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container({
  DateTime Function()? clock,
  DebugEntitlementService? entitlement,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    entitlementServiceProvider
        .overrideWithValue(entitlement ?? DebugEntitlementService()),
    if (clock != null) clockProvider.overrideWithValue(clock),
  ]);
  addTearDown(c.dispose);
  return c;
}

PlacementResult _result(int start) => PlacementResult(
    score: 8, maxScore: 10, rule: null, startEpisode: start, missed: const []);

void main() {
  test('the free window is fixed by the first placement choice', () async {
    final c = await _container();
    final user = c.read(userStateProvider.notifier);
    user.applyPlacement(_result(11));
    expect(c.read(freeEpisodeIdsProvider), {11, 12});
    user.applyPlacement(_result(21)); // retake: path moves, free window does not
    expect(c.read(userStateProvider).startEpisode, 21);
    expect(c.read(freeEpisodeIdsProvider), {11, 12});
  });

  test('"start from episode 1" overrides the suggested start', () async {
    final c = await _container();
    c.read(userStateProvider.notifier)
        .applyPlacement(_result(21), startFromBeginning: true);
    expect(c.read(userStateProvider).startEpisode, 1);
    expect(c.read(freeEpisodeIdsProvider), {1, 2});
  });

  test('stars only go up and completing opens the next episode', () async {
    final c = await _container();
    final user = c.read(userStateProvider.notifier)..skipPlacement();
    expect(c.read(episodeAccessProvider(2)).isUnlocked, isFalse);
    user.completeEpisode(1, stars: 3);
    user.completeEpisode(1, stars: 1);
    expect(c.read(userStateProvider).starsFor(1), 3);
    expect(c.read(episodeAccessProvider(2)).isUnlocked, isTrue);
    expect(c.read(episodeAccessProvider(3)).needsPaywall, isTrue);
  });

  test('progress is saved and restored', () async {
    final c = await _container();
    c.read(userStateProvider.notifier)
      ..skipPlacement()
      ..completeEpisode(1, stars: 2);
    final prefs = c.read(sharedPreferencesProvider);
    final c2 = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      entitlementServiceProvider.overrideWithValue(DebugEntitlementService()),
    ]);
    addTearDown(c2.dispose);
    expect(c2.read(userStateProvider).isCompleted(1), isTrue);
  });

  test('day streak: +1 on consecutive days, reset after a gap', () async {
    var now = DateTime(2026, 10, 14, 9);
    final c = await _container(clock: () => now);
    final user = c.read(userStateProvider.notifier);
    user.touchActivity();
    expect(c.read(userStateProvider).streakDays, 1);
    user.touchActivity(); // same day
    expect(c.read(userStateProvider).streakDays, 1);
    now = DateTime(2026, 10, 15, 22);
    user.touchActivity();
    expect(c.read(userStateProvider).streakDays, 2);
    now = DateTime(2026, 10, 18, 8);
    user.touchActivity();
    expect(c.read(userStateProvider).streakDays, 1);
  });

  test('free call minutes: 300 s a day, new day resets, premium is unlimited',
      () async {
    var now = DateTime(2026, 10, 15, 23, 50);
    final service = DebugEntitlementService();
    final c = await _container(clock: () => now, entitlement: service);
    c.read(premiumProvider); // start listening
    expect(c.read(callRemainingSecondsProvider), 300);
    c.read(callQuotaProvider.notifier).addUsage(120);
    expect(c.read(callRemainingSecondsProvider), 180);
    c.read(callQuotaProvider.notifier).addUsage(500);
    expect(c.read(callRemainingSecondsProvider), 0);

    now = DateTime(2026, 10, 16, 0, 5); // next local day
    c.invalidate(callRemainingSecondsProvider);
    expect(c.read(callRemainingSecondsProvider), 300);

    service.debugSetPremium(true);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(premiumProvider), isTrue);
    expect(c.read(callRemainingSecondsProvider), isNull);
  });

  test('free plan cannot select a premium persona', () async {
    final c = await _container();
    final settings = c.read(appSettingsProvider.notifier);
    expect(settings.setPersona(Persona.kansai), isFalse);
    expect(c.read(appSettingsProvider).persona, Persona.politeSensei);
    expect(settings.setPersona(Persona.casualFriend), isTrue);
    expect(c.read(appSettingsProvider).persona, Persona.casualFriend);
  });
}
