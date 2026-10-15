import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_utils.dart';
import '../models/ai_turn.dart';
import '../models/enums.dart';
import '../models/episode.dart';
import '../models/persona_info.dart';
import '../services/access_policy.dart';
import '../services/audio_service.dart';
import '../services/tutor_api.dart';
import '../services/voice_recorder.dart';
import 'providers.dart';

enum CallPhase {
  /// Greeting is being fetched.
  connecting,

  /// The microphone is open and waiting for / hearing the learner.
  listening,

  /// The learner's audio is with the server; waiting for the reply.
  thinking,

  /// The persona's voice reply is playing.
  speaking,

  /// The learner paused the hands-free loop.
  paused,

  /// A request or the microphone failed; offers retry.
  error,

  /// The final turn (`__END_CALL__`) is being fetched.
  ending,

  /// Call finished; the summary is shown.
  ended,
}

class LiveCallState {
  const LiveCallState({
    this.phase = CallPhase.connecting,
    this.persona = Persona.politeSensei,
    this.turn,
    this.japanese = '',
    this.romaji = '',
    this.arabic = '',
    this.learnerText,
    this.level = 0,
    this.elapsedSeconds = 0,
    this.remainingSeconds,
    this.correctionVisible = false,
    this.errorAr,
    this.summary,
    this.heardSpeech = false,
    this.paused = false,
  });

  final CallPhase phase;
  final Persona persona;

  /// Latest AI answer (correction box, emotion tone). Null before the first one.
  final AiTurnResponse? turn;

  /// Text on screen: the persona's last line.
  final String japanese;
  final String romaji;
  final String arabic;

  /// What the learner said (speech-to-text), shown muted.
  final String? learnerText;

  /// Microphone level 0..1, drives the orb.
  final double level;
  final int elapsedSeconds;

  /// Free seconds left today; null = unlimited (subscriber).
  final int? remainingSeconds;
  final bool correctionVisible;
  final String? errorAr;

  /// Final summary turn (call finished).
  final AiTurnResponse? summary;
  final bool heardSpeech;
  final bool paused;

  EmotionTone get tone => turn?.emotionTone ?? EmotionTone.calm;

  /// Last free minute: the counter turns red.
  bool get lastMinute =>
      remainingSeconds != null && remainingSeconds! <= 60 && phase != CallPhase.ended;

  bool get isFinished => phase == CallPhase.ended;

  LiveCallState copyWith({
    CallPhase? phase,
    Persona? persona,
    AiTurnResponse? turn,
    String? japanese,
    String? romaji,
    String? arabic,
    String? learnerText,
    double? level,
    int? elapsedSeconds,
    int? remainingSeconds,
    bool? correctionVisible,
    String? errorAr,
    bool clearError = false,
    AiTurnResponse? summary,
    bool? heardSpeech,
    bool? paused,
  }) =>
      LiveCallState(
        phase: phase ?? this.phase,
        persona: persona ?? this.persona,
        turn: turn ?? this.turn,
        japanese: japanese ?? this.japanese,
        romaji: romaji ?? this.romaji,
        arabic: arabic ?? this.arabic,
        learnerText: learnerText ?? this.learnerText,
        level: level ?? this.level,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        correctionVisible: correctionVisible ?? this.correctionVisible,
        errorAr: clearError ? null : (errorAr ?? this.errorAr),
        summary: summary ?? this.summary,
        heardSpeech: heardSpeech ?? this.heardSpeech,
        paused: paused ?? this.paused,
      );
}

final liveCallProvider =
    NotifierProvider.autoDispose<LiveCallController, LiveCallState>(
        LiveCallController.new);

/// Hands-free voice call:
///   listen -> (learner stops talking) -> send audio -> reply plays -> listen ...
/// until the learner ends it, the AI says goodbye, or the free time runs out.
class LiveCallController extends AutoDisposeNotifier<LiveCallState> {
  // Voice detection (levels are 0..1 from VoiceRecorder).
  static const double speechLevel = 0.34;
  static const Duration silenceToSend = Duration(milliseconds: 1300);
  static const Duration minUtterance = Duration(milliseconds: 350);
  static const Duration maxUtterance = Duration(seconds: 30);

  /// How long a reply without audio stays on screen before listening again.
  @visibleForTesting
  static Duration silentReplyPause = const Duration(milliseconds: 900);

  late final VoiceRecorder _recorder;
  late final AudioService _audio;
  late final CallQuotaController _quota;
  late final String _sessionId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';

  Timer? _ticker;
  Timer? _correctionTimer;
  StreamSubscription<double>? _levelSub;

  Persona _persona = Persona.politeSensei;
  String _userName = '';
  int _progress = 0;
  String _knownVocab = '';
  TtsProvider _tts = TtsProvider.openai;

  int? _startRemaining;
  int _used = 0;
  int _unflushed = 0;

  DateTime? _speechStartAt;
  DateTime? _lastVoiceAt;
  bool _speech = false;

  bool _started = false;
  bool _ending = false;
  bool _disposed = false;
  Future<void> Function()? _retryAction;

  @override
  LiveCallState build() {
    _recorder = ref.read(voiceRecorderProvider);
    _audio = ref.read(audioServiceProvider);
    _quota = ref.read(callQuotaProvider.notifier);
    ref.onDispose(_onDispose);
    return const LiveCallState();
  }

  void _onDispose() {
    _disposed = true;
    _ticker?.cancel();
    _correctionTimer?.cancel();
    unawaited(_levelSub?.cancel());
    unawaited(_recorder.cancel());
    unawaited(_audio.stop());
    _flushUsage();
  }

  DateTime _now() => ref.read(clockProvider)();

  // ---- lifecycle ----------------------------------------------------------

  /// Starts the call: shows the persona greeting at once, then asks the server
  /// for the real first turn (greeting + voice).
  Future<void> start() async {
    if (_started) return;
    _started = true;

    final settings = ref.read(appSettingsProvider);
    final premium = ref.read(premiumProvider);
    final user = ref.read(userStateProvider);
    _persona = AccessPolicy.canUsePersona(settings.persona, isPremium: premium)
        ? settings.persona
        : Persona.politeSensei;
    _userName = user.displayName;
    _progress = user.highestCompleted;
    _tts = settings.ttsProvider;
    _startRemaining = ref.read(callRemainingSecondsProvider);

    if (_startRemaining != null && _startRemaining! <= 0) {
      state = state.copyWith(
        phase: CallPhase.ended,
        persona: _persona,
        errorAr: 'انتهى وقت المكالمة المجاني اليوم، ويتجدد غداً.',
      );
      return;
    }

    final info = PersonaInfo.of(_persona);
    state = state.copyWith(
      persona: _persona,
      japanese: info.greetingJp,
      romaji: info.greetingRomaji,
      arabic: info.greetingAr,
      remainingSeconds: _startRemaining,
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());

    try {
      final episodes = await ref.read(episodeListProvider.future);
      _knownVocab = Episode.knownVocabString(
          episodes.where((e) => user.isCompleted(e.id)));
    } on Object {
      _knownVocab = '';
    }
    if (_disposed || _ending) return;

    await _exchange(_request(first: true));
  }

  FreeTalkTurnRequest _request({bool first = false}) => FreeTalkTurnRequest(
        sessionId: _sessionId,
        persona: _persona,
        userName: _userName,
        userProgress: _progress,
        knownVocab: _knownVocab,
        localTime: hhmm(_now()),
        ttsProvider: _tts,
        isFirstTurn: first,
      );

  /// One second of call time. Public so tests can drive the clock.
  @visibleForTesting
  void tick() {
    if (_disposed || _ending || !_started || state.phase == CallPhase.ended) {
      return;
    }
    _used++;
    _unflushed++;
    final remaining = _startRemaining == null
        ? null
        : max(0, _startRemaining! - _used);
    state = state.copyWith(
      elapsedSeconds: state.elapsedSeconds + 1,
      remainingSeconds: remaining,
    );
    if (_unflushed >= 5) _flushUsage();
    if (remaining != null && remaining <= 0) unawaited(endCall());
  }

  void _flushUsage() {
    if (_unflushed <= 0) return;
    final seconds = _unflushed;
    _unflushed = 0;
    try {
      _quota.addUsage(seconds);
    } on Object {
      // The app is shutting down; the next call re-reads the saved value.
    }
  }

  // ---- one server round trip ---------------------------------------------

  Future<void> _exchange(FreeTalkTurnRequest request, {String? audioPath}) async {
    _retryAction = () => _exchange(request, audioPath: audioPath);
    state = state.copyWith(phase: CallPhase.thinking, level: 0, clearError: true);
    try {
      final reply = await ref
          .read(tutorApiProvider)
          .sendFreeTalkTurn(request, audioPath: audioPath);
      if (_disposed || _ending) return;
      _retryAction = null;
      await _present(reply);
    } on TutorApiException catch (e) {
      if (_disposed || _ending) return;
      state = state.copyWith(phase: CallPhase.error, errorAr: e.messageAr);
    } on Object {
      if (_disposed || _ending) return;
      state = state.copyWith(
          phase: CallPhase.error, errorAr: 'حدث خطأ غير متوقع. حاول مرة أخرى.');
    }
  }

  Future<void> _present(TutorReply reply) async {
    final turn = reply.turn;
    _correctionTimer?.cancel();
    state = state.copyWith(
      turn: turn,
      japanese: turn.replyJapanese,
      romaji: turn.replyRomaji,
      arabic: turn.replyArabic,
      learnerText: reply.userTranscript,
      correctionVisible: true,
      phase: CallPhase.speaking,
      level: 0,
    );
    _correctionTimer = Timer(const Duration(seconds: 8), () {
      if (!_disposed) state = state.copyWith(correctionVisible: false);
    });

    if (turn.conversationCompleted) {
      // The learner said goodbye: the AI answered with the summary.
      await _finishFromAi(turn, reply.audioUrl);
      return;
    }

    final url = reply.audioUrl;
    if (url != null) {
      await _audio.playUrlAndWait(url);
    } else {
      await Future<void>.delayed(silentReplyPause);
    }
    if (_disposed || _ending) return;
    await _listen();
  }

  // ---- listening ----------------------------------------------------------

  Future<void> _listen() async {
    if (_disposed || _ending) return;
    if (state.paused) {
      state = state.copyWith(phase: CallPhase.paused, level: 0);
      return;
    }
    if (state.remainingSeconds != null && state.remainingSeconds! <= 0) return;

    var allowed = false;
    try {
      allowed = await _recorder.hasPermission();
    } on Object {
      allowed = false;
    }
    if (_disposed || _ending) return;
    if (!allowed) {
      _retryAction = _listen;
      state = state.copyWith(
        phase: CallPhase.error,
        errorAr: 'نحتاج إذن الميكروفون لنتحدث. فعّله من إعدادات الجهاز ثم أعد المحاولة.',
      );
      return;
    }
    try {
      await _recorder.start();
    } on Object {
      if (_disposed || _ending) return;
      _retryAction = _listen;
      state = state.copyWith(
          phase: CallPhase.error, errorAr: 'تعذّر تشغيل الميكروفون.');
      return;
    }
    if (_disposed || _ending) {
      unawaited(_recorder.cancel());
      return;
    }
    _speech = false;
    _speechStartAt = null;
    _lastVoiceAt = null;
    await _levelSub?.cancel();
    _levelSub = _recorder.levels.listen(onLevel);
    state = state.copyWith(
        phase: CallPhase.listening, heardSpeech: false, clearError: true);
  }

  /// Handles one microphone level sample. Sends the recording after the
  /// learner has spoken and then been silent for [silenceToSend].
  @visibleForTesting
  void onLevel(double level) {
    if (_disposed) return;
    state = state.copyWith(level: level);
    if (state.phase != CallPhase.listening) return;

    final now = _now();
    if (level >= speechLevel) {
      _speechStartAt ??= now;
      _lastVoiceAt = now;
      if (!_speech) {
        _speech = true;
        state = state.copyWith(heardSpeech: true);
      }
    }
    if (!_speech) return;

    final spoke = _lastVoiceAt!.difference(_speechStartAt!);
    final silent = now.difference(_lastVoiceAt!);
    final tooLong = now.difference(_speechStartAt!) >= maxUtterance;
    if (silent >= silenceToSend || tooLong) {
      if (spoke < minUtterance && !tooLong) {
        // A cough or a click: forget it and keep listening.
        _speech = false;
        _speechStartAt = null;
        _lastVoiceAt = null;
        state = state.copyWith(heardSpeech: false);
        return;
      }
      _beginSend();
    }
  }

  void _beginSend() {
    // Leaving `listening` first makes any further level sample a no-op.
    state = state.copyWith(phase: CallPhase.thinking, level: 0);
    unawaited(_sendRecording());
  }

  Future<void> _sendRecording() async {
    await _levelSub?.cancel();
    _levelSub = null;
    final path = await _recorder.stop();
    if (_disposed || _ending) return;
    if (path == null) {
      await _listen();
      return;
    }
    await _exchange(_request(), audioPath: path);
  }

  // ---- controls -----------------------------------------------------------

  /// Tap on the orb: send now if the learner is mid-sentence, skip the
  /// persona's speech while it talks, or resume after a pause.
  void tapOrb() {
    switch (state.phase) {
      case CallPhase.listening:
        if (_speech) _beginSend();
      case CallPhase.speaking:
        unawaited(_audio.stop());
      case CallPhase.paused:
        togglePause();
      case CallPhase.connecting ||
            CallPhase.thinking ||
            CallPhase.error ||
            CallPhase.ending ||
            CallPhase.ended:
        break;
    }
  }

  /// Pause / resume the hands-free loop.
  void togglePause() {
    if (_ending || state.phase == CallPhase.ended) return;
    if (state.paused) {
      state = state.copyWith(paused: false);
      if (state.phase == CallPhase.paused) unawaited(_listen());
      return;
    }
    state = state.copyWith(paused: true);
    if (state.phase == CallPhase.listening) {
      unawaited(_levelSub?.cancel());
      _levelSub = null;
      unawaited(_recorder.cancel());
      state = state.copyWith(phase: CallPhase.paused, level: 0);
    }
  }

  /// Retry after an error.
  Future<void> retry() async {
    final action = _retryAction;
    if (action == null) return;
    await action();
  }

  /// After an error: forget the failed turn and listen again.
  Future<void> skipError() async {
    _retryAction = null;
    state = state.copyWith(clearError: true);
    await _listen();
  }

  // ---- ending ---------------------------------------------------------------

  /// Ends the call: sends `__END_CALL__` and shows the summary.
  Future<void> endCall() async {
    if (_ending || state.phase == CallPhase.ended) return;
    _ending = true;
    await _stopEverything();
    state = state.copyWith(phase: CallPhase.ending, level: 0, clearError: true);

    try {
      final reply = await ref.read(tutorApiProvider).sendFreeTalkTurn(
            FreeTalkTurnRequest.endCall(
              sessionId: _sessionId,
              persona: _persona,
              userName: _userName,
              userProgress: _progress,
              knownVocab: _knownVocab,
              localTime: hhmm(_now()),
              ttsProvider: _tts,
            ),
          );
      if (_disposed) return;
      _showSummary(reply.turn, reply.audioUrl);
    } on Object {
      // No summary available (offline): still close the call cleanly.
      if (!_disposed) state = state.copyWith(phase: CallPhase.ended);
    }
  }

  Future<void> _finishFromAi(AiTurnResponse turn, String? audioUrl) async {
    _ending = true;
    await _stopEverything();
    if (_disposed) return;
    _showSummary(turn, null);
    // Its voice reply (the goodbye) was already requested with this turn.
    if (audioUrl != null) await _audio.playUrlAndWait(audioUrl);
  }

  Future<void> _stopEverything() async {
    _ticker?.cancel();
    _correctionTimer?.cancel();
    await _levelSub?.cancel();
    _levelSub = null;
    await _recorder.cancel();
    await _audio.stop();
    _flushUsage();
  }

  void _showSummary(AiTurnResponse turn, String? audioUrl) {
    state = state.copyWith(
      phase: CallPhase.ended,
      turn: turn,
      summary: turn,
      japanese: turn.replyJapanese,
      romaji: turn.replyRomaji,
      arabic: turn.replyArabic,
      correctionVisible: true,
      level: 0,
    );
    if (audioUrl != null) unawaited(_audio.playUrl(audioUrl));
  }
}
