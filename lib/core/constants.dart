import 'package:flutter/foundation.dart';

/// Product rules decided with the app owner. Change them here only.
abstract final class AppRules {
  /// 4 seasons x 10 episodes.
  static const int totalEpisodes = 40;
  static const int episodesPerSeason = 10;

  /// Free plan: this many episodes, counted from the episode chosen by the
  /// placement test (1-2, 11-12 or 21-22). Everything else needs the subscription.
  static const int freeEpisodeCount = 2;

  /// Free plan: live voice call time per local day. Subscribers: unlimited.
  static const int freeDailyCallSeconds = 5 * 60;

  /// RevenueCat entitlement identifier.
  static const String premiumEntitlementId = 'premium';

  /// How long the last known "premium" answer is trusted while offline.
  static const Duration premiumCacheGrace = Duration(days: 7);

  /// Control message sent to the free-talk prompt when the user taps
  /// "End conversation" or the free time reaches zero.
  static const String endCallControlMessage = '__END_CALL__';

  /// The learner's own character in the dialogues (used to align chat bubbles).
  static const String learnerSpeakerJp = 'サーレム';

  /// Default name sent to the prompts as {{USER_NAME}}.
  static const String defaultUserName = 'サーレム';

  /// Slow playback speed for the "slow audio" button.
  static const double slowAudioSpeed = 0.7;

  /// Arabic names of the four seasons (10 episodes each).
  static const List<String> seasonTitlesAr = [
    'الوصول والأساسيات',
    'الروتين اليومي والمدينة',
    'المدرسة والحياة في اليابان',
    'العمل والسفر',
  ];

  /// Coach character of station D (Sensei Ken). Falls back to an icon if the
  /// image file is not there yet.
  static const String senseiKenAvatar =
      'assets/images/characters/sensei_ken.webp';

  /// Maximum number of known words sent in {{KNOWN_VOCAB}}.
  static const int maxKnownVocabWords = 150;
}

/// Build-time configuration, passed with --dart-define:
///
///   flutter run \
///     --dart-define=API_BASE_URL=https://api.your-server.com \
///     --dart-define=RC_API_KEY_ANDROID=goog_xxx \
///     --dart-define=RC_API_KEY_IOS=appl_xxx
abstract final class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Optional shared secret, sent as `x-app-key` (must match APP_API_KEY on the server).
  static const String appApiKey = String.fromEnvironment('APP_API_KEY');
  static const String revenueCatKeyAndroid =
      String.fromEnvironment('RC_API_KEY_ANDROID');
  static const String revenueCatKeyIos =
      String.fromEnvironment('RC_API_KEY_IOS');

  /// Simulated purchases: `--dart-define=MOCK_PURCHASES=true`. Works in any
  /// build mode so testers can try the paywall before Google Play / App Store
  /// are connected. Never ship a store build with this flag on.
  static const bool mockPurchases = bool.fromEnvironment('MOCK_PURCHASES');

  /// Empty string => no store key for this platform => debug entitlement service.
  static String get revenueCatApiKey => switch (defaultTargetPlatform) {
        TargetPlatform.android => revenueCatKeyAndroid,
        TargetPlatform.iOS => revenueCatKeyIos,
        _ => '',
      };
}
