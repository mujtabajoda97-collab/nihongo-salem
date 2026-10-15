import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_turn.dart';
import '../models/enums.dart';
import '../models/episode.dart';
import '../services/tutor_api.dart';
import 'providers.dart';

enum TutorSender { ai, learner }

class TutorMessage {
  const TutorMessage.learner(this.japanese)
      : sender = TutorSender.learner,
        romaji = null,
        arabic = null,
        turn = null;

  const TutorMessage.ai({
    required this.japanese,
    this.romaji,
    this.arabic,
    this.turn,
  }) : sender = TutorSender.ai;

  final TutorSender sender;
  final String japanese;
  final String? romaji;
  final String? arabic;

  /// The full AI answer (correction box data). Null for the opening line.
  final AiTurnResponse? turn;
}

class TutorSessionState {
  const TutorSessionState({
    this.tone,
    this.messages = const [],
    this.loading = false,
    this.errorAr,
    this.completed = false,
    this.learnerTurns = 0,
  });

  /// Null until the learner picks a tone and starts.
  final TutorTone? tone;
  final List<TutorMessage> messages;
  final bool loading;
  final String? errorAr;

  /// The AI ended the conversation (`conversation_completed`).
  final bool completed;
  final int learnerTurns;

  bool get started => tone != null;

  /// Last AI answer that has correction data.
  AiTurnResponse? get lastTurn {
    for (final m in messages.reversed) {
      if (m.turn != null) return m.turn;
    }
    return null;
  }

  TutorSessionState copyWith({
    TutorTone? tone,
    List<TutorMessage>? messages,
    bool? loading,
    String? errorAr,
    bool clearError = false,
    bool? completed,
    int? learnerTurns,
  }) =>
      TutorSessionState(
        tone: tone ?? this.tone,
        messages: messages ?? this.messages,
        loading: loading ?? this.loading,
        errorAr: clearError ? null : (errorAr ?? this.errorAr),
        completed: completed ?? this.completed,
        learnerTurns: learnerTurns ?? this.learnerTurns,
      );
}

/// Station D: one conversation with the AI tutor for one episode.
final tutorSessionProvider = NotifierProvider.autoDispose
    .family<TutorSessionController, TutorSessionState, int>(
        TutorSessionController.new);

class TutorSessionController
    extends AutoDisposeFamilyNotifier<TutorSessionState, int> {
  late final String _sessionId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';
  Episode? _episode;

  // What to repeat if the last request failed.
  String? _pendingText;
  String? _pendingAudio;

  @override
  TutorSessionState build(int arg) {
    final audio = ref.read(audioServiceProvider);
    ref.onDispose(() => unawaited(audio.stop()));
    return const TutorSessionState();
  }

  /// Opens the conversation with the episode's own first line (already
  /// written in the JSON, so no server call is needed to begin).
  void start(Episode episode, TutorTone tone) {
    _episode = episode;
    state = TutorSessionState(
      tone: tone,
      messages: [
        TutorMessage.ai(
          japanese: episode.aiRoleplay.initialAiMessageJp,
          arabic: episode.aiRoleplay.initialAiMessageAr,
        ),
      ],
    );
  }

  Future<void> sendText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future.value();
    return _send(text: trimmed);
  }

  Future<void> sendVoice(String audioPath) => _send(audioPath: audioPath);

  /// Repeats the request that failed.
  Future<void> retry() {
    final text = _pendingText;
    final audio = _pendingAudio;
    if (text == null && audio == null) return Future.value();
    return _send(text: text, audioPath: audio, isRetry: true);
  }

  Future<void> _send({
    String? text,
    String? audioPath,
    bool isRetry = false,
  }) async {
    final episode = _episode;
    final tone = state.tone;
    if (episode == null || tone == null) return;
    if (state.loading || state.completed) return;

    _pendingText = text;
    _pendingAudio = audioPath;

    // A typed message shows at once; a voice message shows once it is transcribed.
    state = state.copyWith(
      messages: (text != null && !isRetry)
          ? [...state.messages, TutorMessage.learner(text)]
          : state.messages,
      loading: true,
      clearError: true,
    );

    final user = ref.read(userStateProvider);
    final settings = ref.read(appSettingsProvider);
    final request = TutorTurnRequest(
      sessionId: _sessionId,
      episodeId: episode.id,
      tone: tone,
      userName: user.displayName,
      variables: episode.tutorVariables(tone: tone, userName: user.displayName),
      ttsProvider: settings.ttsProvider,
      userMessage: text,
    );

    try {
      final reply =
          await ref.read(tutorApiProvider).sendTurn(request, audioPath: audioPath);
      final turn = reply.turn;
      _pendingText = null;
      _pendingAudio = null;
      state = state.copyWith(
        messages: [
          ...state.messages,
          if (audioPath != null)
            TutorMessage.learner(reply.userTranscript ?? '🎤'),
          TutorMessage.ai(
            japanese: turn.replyJapanese,
            romaji: turn.replyRomaji,
            arabic: turn.replyArabic,
            turn: turn,
          ),
        ],
        loading: false,
        completed: turn.conversationCompleted,
        learnerTurns: state.learnerTurns + 1,
      );
      final url = reply.audioUrl;
      if (url != null) {
        unawaited(ref.read(audioServiceProvider).playUrl(url));
      }
    } on TutorApiException catch (e) {
      state = state.copyWith(loading: false, errorAr: e.messageAr);
    } on Object {
      state = state.copyWith(
          loading: false, errorAr: 'حدث خطأ غير متوقع. حاول مرة أخرى.');
    }
  }

  /// Drops the failed request and lets the learner try something else.
  void dismissError() {
    _pendingText = null;
    _pendingAudio = null;
    state = state.copyWith(clearError: true);
  }
}
