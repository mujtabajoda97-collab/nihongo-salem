import '../core/constants.dart';
import 'enums.dart';
import 'json_helpers.dart';

/// Everything saved about the learner on this device.
class UserState {
  const UserState({
    this.displayName = AppRules.defaultUserName,
    this.placementCompleted = false,
    this.placementScore,
    this.startEpisode = 1,
    this.freeWindowStart,
    this.completedEpisodes = const {},
    this.stars = const {},
    this.streakDays = 0,
    this.lastActiveDate,
  });

  factory UserState.fromJson(Map<String, dynamic> j) {
    final completed = j['completed_episodes'];
    final stars = j['stars'];
    return UserState(
      displayName: optString(j, 'display_name') ?? AppRules.defaultUserName,
      placementCompleted: readBool(j['placement_completed']),
      placementScore: j['placement_score'] is int
          ? j['placement_score'] as int
          : null,
      startEpisode: j['start_episode'] is int ? j['start_episode'] as int : 1,
      freeWindowStart: j['free_window_start'] is int
          ? j['free_window_start'] as int
          : null,
      completedEpisodes: {
        if (completed is List<dynamic>)
          for (final e in completed)
            if (e is int) e,
      },
      stars: {
        if (stars is Map<String, dynamic>)
          for (final e in stars.entries)
            if (int.tryParse(e.key) != null && e.value is int)
              int.parse(e.key): e.value as int,
      },
      streakDays: j['streak_days'] is int ? j['streak_days'] as int : 0,
      lastActiveDate: optString(j, 'last_active_date'),
    );
  }

  final String displayName;
  final bool placementCompleted;
  final int? placementScore;

  /// Where the learner's path begins (1, 11 or 21, or 1 if they chose to start over).
  final int startEpisode;

  /// First episode of the two free episodes. Fixed the first time the learner
  /// chooses a starting point and never moved by a later retake of the test.
  final int? freeWindowStart;
  final Set<int> completedEpisodes;

  /// Best star rating (0-3) per episode.
  final Map<int, int> stars;
  final int streakDays;

  /// Local date `yyyy-MM-dd` of the last activity (for the streak).
  final String? lastActiveDate;

  bool isCompleted(int episodeId) => completedEpisodes.contains(episodeId);
  int starsFor(int episodeId) => stars[episodeId] ?? 0;
  int get totalStars => stars.values.fold(0, (a, b) => a + b);

  /// Highest completed episode number, 0 if none.
  int get highestCompleted => completedEpisodes.isEmpty
      ? 0
      : completedEpisodes.reduce((a, b) => a > b ? a : b);

  /// The farthest episode the learner may open: the one after the highest
  /// completed one, but never before the placement start. Earlier episodes
  /// stay open for review.
  int get reachedEpisode {
    final base = highestCompleted > startEpisode - 1
        ? highestCompleted
        : startEpisode - 1;
    final next = base + 1;
    return next > AppRules.totalEpisodes ? AppRules.totalEpisodes : next;
  }

  bool get finishedAllEpisodes =>
      completedEpisodes.length >= AppRules.totalEpisodes;

  UserState copyWith({
    String? displayName,
    bool? placementCompleted,
    int? placementScore,
    int? startEpisode,
    int? freeWindowStart,
    Set<int>? completedEpisodes,
    Map<int, int>? stars,
    int? streakDays,
    String? lastActiveDate,
  }) =>
      UserState(
        displayName: displayName ?? this.displayName,
        placementCompleted: placementCompleted ?? this.placementCompleted,
        placementScore: placementScore ?? this.placementScore,
        startEpisode: startEpisode ?? this.startEpisode,
        freeWindowStart: freeWindowStart ?? this.freeWindowStart,
        completedEpisodes: completedEpisodes ?? this.completedEpisodes,
        stars: stars ?? this.stars,
        streakDays: streakDays ?? this.streakDays,
        lastActiveDate: lastActiveDate ?? this.lastActiveDate,
      );

  Map<String, dynamic> toJson() => {
        'display_name': displayName,
        'placement_completed': placementCompleted,
        'placement_score': placementScore,
        'start_episode': startEpisode,
        'free_window_start': freeWindowStart,
        'completed_episodes': completedEpisodes.toList()..sort(),
        'stars': {for (final e in stars.entries) '${e.key}': e.value},
        'streak_days': streakDays,
        'last_active_date': lastActiveDate,
      };
}

/// User-facing preferences, saved on the device.
class AppSettings {
  const AppSettings({
    this.tutorTone = TutorTone.politeEncouraging,
    this.persona = Persona.politeSensei,
    this.ttsProvider = TtsProvider.openai,
    this.slowAudio = false,
    this.showRomaji = true,
    this.showArabicTranslation = true,
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        tutorTone: TutorTone.fromWire(optString(j, 'tutor_tone')),
        persona: Persona.fromWire(optString(j, 'persona')),
        ttsProvider: TtsProvider.fromWire(optString(j, 'tts_provider')),
        slowAudio: readBool(j['slow_audio']),
        showRomaji: j['show_romaji'] is bool ? j['show_romaji'] as bool : true,
        showArabicTranslation: j['show_arabic_translation'] is bool
            ? j['show_arabic_translation'] as bool
            : true,
      );

  final TutorTone tutorTone;
  final Persona persona;
  final TtsProvider ttsProvider;

  /// Play lesson audio at [AppRules.slowAudioSpeed].
  final bool slowAudio;
  final bool showRomaji;
  final bool showArabicTranslation;

  AppSettings copyWith({
    TutorTone? tutorTone,
    Persona? persona,
    TtsProvider? ttsProvider,
    bool? slowAudio,
    bool? showRomaji,
    bool? showArabicTranslation,
  }) =>
      AppSettings(
        tutorTone: tutorTone ?? this.tutorTone,
        persona: persona ?? this.persona,
        ttsProvider: ttsProvider ?? this.ttsProvider,
        slowAudio: slowAudio ?? this.slowAudio,
        showRomaji: showRomaji ?? this.showRomaji,
        showArabicTranslation:
            showArabicTranslation ?? this.showArabicTranslation,
      );

  Map<String, dynamic> toJson() => {
        'tutor_tone': tutorTone.wire,
        'persona': persona.wire,
        'tts_provider': ttsProvider.wire,
        'slow_audio': slowAudio,
        'show_romaji': showRomaji,
        'show_arabic_translation': showArabicTranslation,
      };
}

/// Seconds of live call used on one local day (free plan quota).
class CallQuota {
  const CallQuota({required this.dateKey, required this.usedSeconds});

  factory CallQuota.fromJson(Map<String, dynamic> j) => CallQuota(
        dateKey: reqString(j, 'date', ctx: 'call quota: '),
        usedSeconds: reqInt(j, 'used_seconds', ctx: 'call quota: '),
      );

  final String dateKey;
  final int usedSeconds;

  Map<String, dynamic> toJson() => {'date': dateKey, 'used_seconds': usedSeconds};
}
