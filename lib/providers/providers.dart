import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/date_utils.dart';
import '../models/enums.dart';
import '../models/episode.dart';
import '../models/placement_test.dart';
import '../models/user_models.dart';
import '../services/access_policy.dart';
import '../services/audio_service.dart';
import '../services/content_repository.dart';
import '../services/entitlement_service.dart';
import '../services/local_storage_service.dart';
import '../services/tutor_api.dart';
import '../services/voice_recorder.dart';
import 'kana_course.dart' show kanaProgressProvider;

// ---------------------------------------------------------------------------
// Overridden in main() / tests
// ---------------------------------------------------------------------------

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider'),
);

final entitlementServiceProvider = Provider<EntitlementService>(
  (ref) => throw UnimplementedError('Override entitlementServiceProvider'),
);

/// Replaceable clock (daily quota, streak) so tests can move time.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final localStorageProvider = Provider<LocalStorageService>(
  (ref) => LocalStorageService(ref.watch(sharedPreferencesProvider)),
);

final contentRepositoryProvider =
    Provider<ContentRepository>((ref) => ContentRepository());

final audioServiceProvider = Provider<AudioService>((ref) {
  final AudioService service = JustAudioService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// Microphone of the live call. Replace in tests with a fake.
final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final recorder = RecordVoiceRecorder();
  ref.onDispose(() => unawaited(recorder.dispose()));
  return recorder;
});

/// Server client of station D and the live call. Replace in tests with a fake.
final tutorApiProvider = Provider<TutorApi>((ref) => DioTutorApi());

// ---------------------------------------------------------------------------
// Content
// ---------------------------------------------------------------------------

/// All 40 episodes, in order.
final episodeListProvider = FutureProvider<List<Episode>>(
  (ref) => ref.watch(contentRepositoryProvider).loadAllEpisodes(),
);

final episodeProvider = FutureProvider.family<Episode, int>(
  (ref, id) => ref.watch(contentRepositoryProvider).loadEpisode(id),
);

final placementTestProvider = FutureProvider<PlacementTest>(
  (ref) => ref.watch(contentRepositoryProvider).loadPlacementTest(),
);

/// Result of the placement test the learner just finished (read by the
/// result screen, saved to [userStateProvider] only when they pick a start).
final placementResultProvider = StateProvider<PlacementResult?>((ref) => null);

// ---------------------------------------------------------------------------
// Learner state
// ---------------------------------------------------------------------------

final userStateProvider =
    NotifierProvider<UserStateController, UserState>(UserStateController.new);

class UserStateController extends Notifier<UserState> {
  @override
  UserState build() =>
      ref.read(localStorageProvider).loadUserState() ?? const UserState();

  void _commit(UserState next) {
    state = next;
    unawaited(ref.read(localStorageProvider).saveUserState(next));
  }

  void setDisplayName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _commit(state.copyWith(displayName: trimmed));
  }

  /// Saves the result of the placement test. With [startFromBeginning] the
  /// learner picked "أفضّل البدء من الحلقة 1" instead of the suggested episode.
  void applyPlacement(PlacementResult result, {bool startFromBeginning = false}) {
    final start = startFromBeginning ? 1 : result.startEpisode;
    _commit(state.copyWith(
      placementCompleted: true,
      placementScore: result.score,
      startEpisode: start,
      // The free window is decided once. Retaking the test never moves it.
      freeWindowStart: state.freeWindowStart ?? start,
    ));
  }

  /// "Skip the test": start at episode 1.
  void skipPlacement() {
    _commit(state.copyWith(
      placementCompleted: true,
      startEpisode: 1,
      freeWindowStart: state.freeWindowStart ?? 1,
    ));
  }

  /// Replaces the progress with the merged result of a cloud sync.
  void replaceFromCloud(UserState merged) => _commit(merged);

  /// Marks an episode finished. [stars] (0-3) only ever goes up.
  void completeEpisode(int episodeId, {required int stars}) {
    final clamped = stars.clamp(0, 3).toInt();
    final best = max(clamped, state.starsFor(episodeId));
    _commit(state.copyWith(
      completedEpisodes: {...state.completedEpisodes, episodeId},
      stars: {...state.stars, episodeId: best},
    ));
    touchActivity();
  }

  /// Updates the day streak. Call when the learner does something meaningful.
  void touchActivity() {
    final now = ref.read(clockProvider)();
    final today = dateKey(now);
    final last = state.lastActiveDate;
    if (last == today) return;
    final streak = last == dateKey(previousDay(now)) ? state.streakDays + 1 : 1;
    _commit(state.copyWith(streakDays: streak, lastActiveDate: today));
  }

  /// Wipes progress and settings on this device.
  Future<void> resetAll() async {
    await ref.read(localStorageProvider).clearAll();
    state = const UserState();
    ref.invalidate(appSettingsProvider);
    ref.invalidate(callQuotaProvider);
    await ref.read(sharedPreferencesProvider).remove('kana_progress_v1');
    ref.invalidate(kanaProgressProvider);
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
        AppSettingsController.new);

class AppSettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() =>
      ref.read(localStorageProvider).loadSettings() ?? const AppSettings();

  void _commit(AppSettings next) {
    state = next;
    unawaited(ref.read(localStorageProvider).saveSettings(next));
  }

  void setTutorTone(TutorTone v) => _commit(state.copyWith(tutorTone: v));
  void setTtsProvider(TtsProvider v) => _commit(state.copyWith(ttsProvider: v));
  void setSlowAudio(bool v) => _commit(state.copyWith(slowAudio: v));
  void setShowRomaji(bool v) => _commit(state.copyWith(showRomaji: v));
  void setShowArabicTranslation(bool v) =>
      _commit(state.copyWith(showArabicTranslation: v));

  /// Returns false (and changes nothing) when the free plan cannot use [v].
  bool setPersona(Persona v) {
    final premium = ref.read(premiumProvider);
    if (!AccessPolicy.canUsePersona(v, isPremium: premium)) return false;
    _commit(state.copyWith(persona: v));
    return true;
  }
}

// ---------------------------------------------------------------------------
// Subscription
// ---------------------------------------------------------------------------

/// true while the learner has an active subscription.
///
/// Starts from the last answer saved on the device (valid for
/// [AppRules.premiumCacheGrace]) so paying users are not locked out offline,
/// then follows the store.
final premiumProvider =
    NotifierProvider<PremiumController, bool>(PremiumController.new);

class PremiumController extends Notifier<bool> {
  bool _disposed = false;

  @override
  bool build() {
    _disposed = false; // build() runs again after a dependency changes
    final service = ref.watch(entitlementServiceProvider);
    final storage = ref.watch(localStorageProvider);
    final now = ref.read(clockProvider);

    final subscription = service.premiumChanges.listen(
      (value) => _apply(value),
      onError: (Object _) {},
    );
    ref.onDispose(() {
      _disposed = true;
      unawaited(subscription.cancel());
    });

    unawaited(service.refresh().then(_apply).catchError((Object _) {}));

    return storage.loadPremiumCache(
            now: now(), maxAge: AppRules.premiumCacheGrace) ??
        false;
  }

  void _apply(bool value) {
    if (_disposed) return;
    state = value;
    unawaited(ref
        .read(localStorageProvider)
        .savePremiumCache(value, ref.read(clockProvider)()));
  }

  Future<PurchaseOutcome> purchase(PaywallPlan plan) async {
    final outcome = await ref.read(entitlementServiceProvider).purchase(plan);
    if (outcome == PurchaseOutcome.purchased) _apply(true);
    return outcome;
  }

  Future<bool> restore() async {
    final premium = await ref.read(entitlementServiceProvider).restore();
    _apply(premium);
    return premium;
  }
}

/// true while purchases are simulated (no real store connected yet).
final isMockPurchasesProvider = Provider<bool>(
  (ref) => ref.watch(entitlementServiceProvider) is MockEntitlementService,
);

final paywallPlansProvider = FutureProvider<List<PaywallPlan>>(
  (ref) => ref.watch(entitlementServiceProvider).loadPlans(),
);

// ---------------------------------------------------------------------------
// Access rules
// ---------------------------------------------------------------------------

final episodeAccessProvider = Provider.family<EpisodeAccess, int>((ref, id) {
  final user = ref.watch(userStateProvider);
  final premium = ref.watch(premiumProvider);
  return AccessPolicy.episodeAccess(
      episodeId: id, user: user, isPremium: premium);
});

/// The two free episodes (empty for subscribers' UI purposes: use for badges).
final freeEpisodeIdsProvider = Provider<Set<int>>(
  (ref) => AccessPolicy.freeEpisodeIds(ref.watch(userStateProvider)),
);

// ---------------------------------------------------------------------------
// Live-call quota
// ---------------------------------------------------------------------------

final callQuotaProvider =
    NotifierProvider<CallQuotaController, CallQuota>(CallQuotaController.new);

class CallQuotaController extends Notifier<CallQuota> {
  String get _today => dateKey(ref.read(clockProvider)());

  @override
  CallQuota build() {
    final stored = ref.read(localStorageProvider).loadCallQuota();
    if (stored != null && stored.dateKey == _today) return stored;
    return CallQuota(dateKey: _today, usedSeconds: 0);
  }

  /// Adds talk time. Call it every few seconds during a call and once more
  /// when the call ends, so a crash loses at most a few seconds.
  void addUsage(int seconds) {
    if (seconds <= 0) return;
    final today = _today;
    final base = state.dateKey == today ? state.usedSeconds : 0;
    final next = CallQuota(dateKey: today, usedSeconds: base + seconds);
    state = next;
    unawaited(ref.read(localStorageProvider).saveCallQuota(next));
  }
}

/// Seconds of free call time left today, `null` = unlimited (subscriber).
/// Reads the clock on every evaluation, so a new day resets the quota even if
/// the app stayed open overnight (re-read it when the call screen opens).
final callRemainingSecondsProvider = Provider<int?>((ref) {
  final quota = ref.watch(callQuotaProvider);
  final premium = ref.watch(premiumProvider);
  final today = dateKey(ref.read(clockProvider)());
  final used = quota.dateKey == today ? quota.usedSeconds : 0;
  return AccessPolicy.remainingCallSeconds(
      isPremium: premium, usedSecondsToday: used);
});
