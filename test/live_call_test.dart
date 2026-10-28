import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihongo_salem/core/constants.dart';
import 'package:nihongo_salem/models/ai_turn.dart';
import 'package:nihongo_salem/models/enums.dart';
import 'package:nihongo_salem/providers/live_call.dart';
import 'package:nihongo_salem/providers/providers.dart';
import 'package:nihongo_salem/services/audio_service.dart';
import 'package:nihongo_salem/services/entitlement_service.dart';
import 'package:nihongo_salem/services/tutor_api.dart';
import 'package:nihongo_salem/services/voice_recorder.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRecorder implements VoiceRecorder {
  final _levels = StreamController<double>.broadcast();
  bool allowed = true;
  int starts = 0;
  int stops = 0;
  int cancels = 0;

  @override
  Future<bool> hasPermission() async => allowed;
  @override
  Future<void> start() async => starts++;
  @override
  Stream<double> get levels => _levels.stream;
  @override
  Future<String?> stop() async {
    stops++;
    return '/tmp/turn_$stops.m4a';
  }

  @override
  Future<void> cancel() async => cancels++;
  @override
  Future<void> dispose() async {}
}

class _FakeAudio implements AudioService {
  final played = <String>[];
  @override
  Future<bool> playAsset(String assetPath, {bool slow = false}) async => true;
  @override
  Future<bool> playUrl(String url) async => true;
  @override
  Future<bool> playUrlAndWait(String url) async {
    played.add(url);
    return true;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _FakeApi implements TutorApi {
  final requests = <FreeTalkTurnRequest>[];
  final audioPaths = <String?>[];
  TutorReply Function(FreeTalkTurnRequest) reply = (_) => _reply();
  Object? failWith;
  Completer<TutorReply>? hold;

  @override
  Future<TutorReply> sendTurn(TutorTurnRequest request, {String? audioPath}) =>
      throw UnimplementedError();

  @override
  Future<TutorReply> sendFreeTalkTurn(FreeTalkTurnRequest request,
      {String? audioPath}) async {
    requests.add(request);
    audioPaths.add(audioPath);
    final e = failWith;
    if (e != null) throw e;
    final h = hold;
    if (h != null) return h.future;
    return reply(request);
  }
}

TutorReply _reply({
  bool completed = false,
  bool mistake = false,
  String? transcript,
  String? audio,
}) =>
    TutorReply(
      turn: AiTurnResponse(
        correctionAr: 'ملاحظة',
        replyJapanese: 'そうですか。',
        replyRomaji: 'Sō desu ka.',
        replyArabic: 'حقاً؟',
        emotionTone: EmotionTone.happy,
        hasMistake: mistake,
        conversationCompleted: completed,
      ),
      userTranscript: transcript,
      audioUrl: audio,
    );

/// Lets queued async work run.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Env {
  _Env(this.c, this.recorder, this.api, this.audio, this.clock);
  final ProviderContainer c;
  final _FakeRecorder recorder;
  final _FakeApi api;
  final _FakeAudio audio;
  final _Clock clock;
  LiveCallController get ctl => c.read(liveCallProvider.notifier);
  LiveCallState get state => c.read(liveCallProvider);
}

class _Clock {
  DateTime now = DateTime(2026, 5, 1, 10);
  DateTime call() => now;
}

Future<_Env> _setup({
  bool premium = false,
  int usedSeconds = 0,
  Future<bool> Function()? wake,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final recorder = _FakeRecorder();
  final api = _FakeApi();
  final audio = _FakeAudio();
  final clock = _Clock();
  final entitlement = DebugEntitlementService();
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    entitlementServiceProvider.overrideWithValue(entitlement),
    voiceRecorderProvider.overrideWithValue(recorder),
    tutorApiProvider.overrideWithValue(api),
    audioServiceProvider.overrideWithValue(audio),
    clockProvider.overrideWithValue(clock.call),
    serverWakeProvider.overrideWithValue(wake ?? () async => true),
  ]);
  addTearDown(c.dispose);
  LiveCallController.silentReplyPause = Duration.zero;
  c.read(userStateProvider.notifier).skipPlacement();
  if (premium) {
    c.read(premiumProvider); // start listening to the store first
    entitlement.debugSetPremium(true);
    await settle();
  }
  if (usedSeconds > 0) {
    c.read(callQuotaProvider.notifier).addUsage(usedSeconds);
  }
  c.listen(liveCallProvider, (_, __) {});
  return _Env(c, recorder, api, audio, clock);
}

void main() {
  test('server unreachable: clear error with a code, retry wakes it again',
      () async {
    var awake = false;
    final e = await _setup(wake: () async => awake);
    await e.ctl.start();
    await settle();
    expect(e.state.phase, CallPhase.error);
    expect(e.state.errorCode, 'health_unreachable');
    expect(e.api.requests, isEmpty);

    awake = true;
    await e.ctl.retry();
    await settle();
    expect(e.api.requests.single.isFirstTurn, isTrue);
    expect(e.state.phase, CallPhase.listening);
  });

  test('server error code reaches the screen', () async {
    final e = await _setup();
    e.api.failWith =
        const TutorApiException('تعذّر', code: 'HTTP 502 · llm_failed');
    await e.ctl.start();
    await settle();
    expect(e.state.phase, CallPhase.error);
    expect(e.state.errorCode, 'HTTP 502 · llm_failed');
  });

  test('ending before any reply closes at once, without a server call',
      () async {
    final e = await _setup();
    e.api.failWith = const TutorApiException('تعذّر', code: 'receiveTimeout');
    await e.ctl.start();
    await settle();
    final sent = e.api.requests.length;

    await e.ctl.endCall();
    expect(e.state.phase, CallPhase.ended);
    expect(e.api.requests.length, sent);
    expect(e.state.errorAr, isNotNull);
  });

  test('waiting can be cancelled; a late answer is then ignored', () async {
    final e = await _setup();
    final hold = Completer<TutorReply>();
    e.api.hold = hold;
    final started = e.ctl.start(); // waits for the held answer
    await settle();
    expect(e.state.phase, CallPhase.thinking);
    for (var i = 0; i < 30; i++) {
      e.ctl.tick();
    }
    expect(e.state.waitSeconds, 30);

    e.ctl.cancelWait();
    expect(e.state.phase, CallPhase.error);
    expect(e.state.errorCode, 'client_wait_30s');

    hold.complete(_reply());
    await settle();
    expect(e.state.phase, CallPhase.error);
    await started;
  });

  test('start: shows the greeting, asks for the first turn, then listens',
      () async {
    final e = await _setup();
    await e.ctl.start();
    await settle();

    expect(e.api.requests.single.isFirstTurn, isTrue);
    expect(e.api.requests.single.persona, Persona.politeSensei);
    expect(e.api.audioPaths.single, isNull);
    expect(e.state.japanese, 'そうですか。');
    expect(e.state.phase, CallPhase.listening);
    expect(e.recorder.starts, 1);
  });

  test('the reply voice is played before listening again', () async {
    final e = await _setup();
    e.api.reply = (_) => _reply(audio: 'https://x/a.mp3');
    await e.ctl.start();
    await settle();
    expect(e.audio.played, ['https://x/a.mp3']);
    expect(e.state.phase, CallPhase.listening);
  });

  test('speech then silence sends the recording and keeps the loop going',
      () async {
    final e = await _setup();
    await e.ctl.start();
    await settle();
    e.api.reply = (_) => _reply(transcript: 'こんにちは');

    e.ctl.onLevel(0.7);
    expect(e.state.heardSpeech, isTrue);
    e.clock.now = e.clock.now.add(const Duration(milliseconds: 600));
    e.ctl.onLevel(0.7);
    e.clock.now = e.clock.now.add(const Duration(milliseconds: 1500));
    e.ctl.onLevel(0.0);
    await settle();

    expect(e.api.requests.length, 2);
    expect(e.api.requests.last.isFirstTurn, isFalse);
    expect(e.api.audioPaths.last, '/tmp/turn_1.m4a');
    expect(e.state.learnerText, 'こんにちは');
    expect(e.state.phase, CallPhase.listening);
    expect(e.recorder.starts, 2);
  });

  test('a short click or cough is ignored', () async {
    final e = await _setup();
    await e.ctl.start();
    await settle();

    e.ctl.onLevel(0.9);
    e.clock.now = e.clock.now.add(const Duration(milliseconds: 100));
    e.ctl.onLevel(0.0);
    e.clock.now = e.clock.now.add(const Duration(milliseconds: 1500));
    e.ctl.onLevel(0.0);
    await settle();

    expect(e.api.requests.length, 1);
    expect(e.state.phase, CallPhase.listening);
    expect(e.state.heardSpeech, isFalse);
  });

  test('silence alone never sends anything', () async {
    final e = await _setup();
    await e.ctl.start();
    await settle();
    for (var i = 0; i < 50; i++) {
      e.clock.now = e.clock.now.add(const Duration(milliseconds: 200));
      e.ctl.onLevel(0.05);
    }
    await settle();
    expect(e.api.requests.length, 1);
  });

  test('free plan: usage is charged each second and flushed every 5', () async {
    final e = await _setup();
    await e.ctl.start();
    await settle();
    expect(e.state.remainingSeconds, AppRules.freeDailyCallSeconds);

    for (var i = 0; i < 7; i++) {
      e.ctl.tick();
    }
    expect(e.state.remainingSeconds, AppRules.freeDailyCallSeconds - 7);
    expect(e.state.elapsedSeconds, 7);
    expect(e.c.read(callQuotaProvider).usedSeconds, 5);

    await e.ctl.endCall(); // flushes the rest
    expect(e.c.read(callQuotaProvider).usedSeconds, 7);
  });

  test('last free minute is flagged, and at 0 the call ends by itself',
      () async {
    final e = await _setup(usedSeconds: AppRules.freeDailyCallSeconds - 62);
    await e.ctl.start();
    await settle();
    expect(e.state.lastMinute, isFalse);

    e.ctl.tick();
    e.ctl.tick();
    expect(e.state.remainingSeconds, 60);
    expect(e.state.lastMinute, isTrue);

    for (var i = 0; i < 60; i++) {
      e.ctl.tick();
    }
    await settle();
    expect(e.state.phase, CallPhase.ended);
    expect(e.api.requests.last.userMessage, AppRules.endCallControlMessage);
    expect(e.c.read(callRemainingSecondsProvider), 0);
  });

  test('subscriber: unlimited time, only elapsed time is shown', () async {
    final e = await _setup(premium: true, usedSeconds: 9999);
    await e.ctl.start();
    await settle();
    e.ctl.tick();
    expect(e.state.remainingSeconds, isNull);
    expect(e.state.lastMinute, isFalse);
    expect(e.state.elapsedSeconds, 1);
  });

  test('no minutes left: the call does not start', () async {
    final e = await _setup(usedSeconds: AppRules.freeDailyCallSeconds);
    await e.ctl.start();
    await settle();
    expect(e.state.phase, CallPhase.ended);
    expect(e.api.requests, isEmpty);
    expect(e.recorder.starts, 0);
  });

  test('End call sends __END_CALL__ and shows the summary', () async {
    final e = await _setup();
    await e.ctl.start();
    await settle();
    e.api.reply = (r) => r.userMessage == AppRules.endCallControlMessage
        ? _reply(completed: true)
        : _reply();

    await e.ctl.endCall();
    expect(e.state.phase, CallPhase.ended);
    expect(e.state.summary, isNotNull);
    final last = e.api.requests.last;
    expect(last.userMessage, '__END_CALL__');
    expect(last.toJson()['mode'], 'free_talk');
    expect(e.recorder.cancels, greaterThan(0));
  });

  test('the AI saying goodbye (conversation_completed) ends the call',
      () async {
    final e = await _setup();
    await e.ctl.start();
    await settle();
    e.api.reply = (_) => _reply(completed: true);

    e.ctl.onLevel(0.8);
    e.clock.now = e.clock.now.add(const Duration(milliseconds: 700));
    e.ctl.onLevel(0.8);
    e.clock.now = e.clock.now.add(const Duration(milliseconds: 1500));
    e.ctl.onLevel(0.0);
    await settle();

    expect(e.state.phase, CallPhase.ended);
    expect(e.state.summary?.conversationCompleted, isTrue);
  });

  test('server error: error phase, retry resends the same recording', () async {
    final e = await _setup();
    await e.ctl.start();
    await settle();

    e.api.failWith = const TutorApiException('لا يوجد اتصال');
    e.ctl.onLevel(0.8);
    e.clock.now = e.clock.now.add(const Duration(milliseconds: 700));
    e.ctl.onLevel(0.8);
    e.clock.now = e.clock.now.add(const Duration(milliseconds: 1500));
    e.ctl.onLevel(0.0);
    await settle();
    expect(e.state.phase, CallPhase.error);
    expect(e.state.errorAr, 'لا يوجد اتصال');

    e.api.failWith = null;
    await e.ctl.retry();
    await settle();
    expect(e.api.audioPaths.where((p) => p == '/tmp/turn_1.m4a').length, 2);
    expect(e.state.phase, CallPhase.listening);
  });

  test('microphone permission denied: clear error, retry works', () async {
    final e = await _setup();
    e.recorder.allowed = false;
    await e.ctl.start();
    await settle();
    expect(e.state.phase, CallPhase.error);

    e.recorder.allowed = true;
    await e.ctl.retry();
    expect(e.state.phase, CallPhase.listening);
  });

  test('pause stops the microphone, resume listens again', () async {
    final e = await _setup();
    await e.ctl.start();
    await settle();

    e.ctl.togglePause();
    expect(e.state.phase, CallPhase.paused);
    final starts = e.recorder.starts;
    e.ctl.togglePause();
    await settle();
    expect(e.state.phase, CallPhase.listening);
    expect(e.recorder.starts, starts + 1);
  });
}
