import '../core/constants.dart';
import '../models/enums.dart';
import '../models/user_models.dart';

/// Why an episode is closed.
enum EpisodeLock {
  /// Open.
  none,

  /// The placement test (or "start from episode 1") has not been done yet.
  placementRequired,

  /// Outside the two free episodes: needs the monthly subscription -> paywall.
  requiresPremium,

  /// Open to the learner's plan, but the previous episode is not finished yet.
  notYetReached,
}

class EpisodeAccess {
  const EpisodeAccess(this.lock);

  final EpisodeLock lock;

  bool get isUnlocked => lock == EpisodeLock.none;
  bool get needsPaywall => lock == EpisodeLock.requiresPremium;
}

/// The business rules of free vs. paid. Pure functions, easy to test.
abstract final class AccessPolicy {
  /// The two free episodes: counted from where the placement test starts the
  /// learner (1-2, 11-12 or 21-22). Empty before the first placement.
  static Set<int> freeEpisodeIds(UserState user) {
    final start = user.freeWindowStart;
    if (start == null) return const {};
    return {
      for (var i = 0; i < AppRules.freeEpisodeCount; i++)
        if (start + i <= AppRules.totalEpisodes) start + i,
    };
  }

  static EpisodeAccess episodeAccess({
    required int episodeId,
    required UserState user,
    required bool isPremium,
  }) {
    if (!user.placementCompleted) {
      return const EpisodeAccess(EpisodeLock.placementRequired);
    }
    if (!isPremium && !freeEpisodeIds(user).contains(episodeId)) {
      return const EpisodeAccess(EpisodeLock.requiresPremium);
    }
    if (episodeId > user.reachedEpisode) {
      return const EpisodeAccess(EpisodeLock.notYetReached);
    }
    return const EpisodeAccess(EpisodeLock.none);
  }

  /// Free plan: 2 personas (polite_sensei, casual_friend). Subscribers: all 4.
  static bool canUsePersona(Persona persona, {required bool isPremium}) =>
      isPremium || persona.isFree;

  /// Seconds the learner may still talk today; `null` = unlimited (subscriber).
  static int? remainingCallSeconds({
    required bool isPremium,
    required int usedSecondsToday,
  }) {
    if (isPremium) return null;
    final left = AppRules.freeDailyCallSeconds - usedSecondsToday;
    return left < 0 ? 0 : left;
  }

  static bool canStartCall(int? remainingSeconds) =>
      remainingSeconds == null || remainingSeconds > 0;
}
