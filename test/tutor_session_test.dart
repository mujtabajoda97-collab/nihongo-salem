import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihongo_salem/models/ai_turn.dart';
import 'package:nihongo_salem/models/enums.dart';
import 'package:nihongo_salem/models/episode.dart';
import 'package:nihongo_salem/providers/providers.dart';
import 'package:nihongo_salem/providers/tutor_session.dart';
import 'package:nihongo_salem/services/audio_service.dart';
import 'package:nihongo_salem/services/entitlement_service.dart';
import 'package:nihongo_salem/services/tutor_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi implements TutorApi {
  final requests = <TutorTurnRequest>[];
  final audioPaths = <String?>[];
  Object? failWith;
  TutorReply reply = _reply();

  @override
  Future<TutorReply> sendTurn(TutorTurnRequest request,
      {String? audioPath}) async {
    requests.add(request);
    audioPaths.add(audioPath);
    final error = failWith;
    if (error != null) throw error;
    return reply;
  }

  @override
  Future<TutorReply> sendFreeTalkTurn(FreeTalkTurnRequest request,
          {String? audioPath}) async =>
      reply;
}

class _SilentAudio implements AudioService {
  @override
  Future<bool> playAsset(String assetPath, {bool slow = false}) async => true;
  @override
  Future<bool> playUrl(String url) async => true;
  @override
  Future<bool> playUrlAndWait(String url) async => true;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

TutorReply _reply({
  bool mistake = false,
  bool completed = false,
  String? transcript,
}) =>
    TutorReply(
      turn: AiTurnResponse(
        correctionAr: 'ملاحظة',
        replyJapanese: 'はい。',
        replyRomaji: 'Hai.',
        replyArabic: 'نعم.',
        emotionTone: EmotionTone.calm,
        hasMistake: mistake,
        conversationCompleted: completed,
      ),
      userTranscript: transcript,
    );

Future<(ProviderContainer, _FakeApi, Episode)> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final api = _FakeApi();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    entitlementServiceProvider.overrideWithValue(DebugEntitlementService()),
    tutorApiProvider.overrideWithValue(api),
    audioServiceProvider.overrideWithValue(_SilentAudio()),
  ]);
  addTearDown(container.dispose);
  final episode = Episode.fromJson(jsonDecode(
          File('assets/data/episodes/episode_01.json').readAsStringSync())
      as Map<String, dynamic>);
  return (container, api, episode);
}

void main() {
  test('starts with the episode opening line, no server call', () async {
    final (c, api, ep) = await _setup();
    c.listen(tutorSessionProvider(1), (_, __) {});
    c.read(tutorSessionProvider(1).notifier).start(ep, TutorTone.friendlyPeer);
    final s = c.read(tutorSessionProvider(1));
    expect(s.started, isTrue);
    expect(s.messages.single.japanese, ep.aiRoleplay.initialAiMessageJp);
    expect(api.requests, isEmpty);
  });

  test('a text turn sends the template variables and keeps has_mistake',
      () async {
    final (c, api, ep) = await _setup();
    c.listen(tutorSessionProvider(1), (_, __) {});
    final ctl = c.read(tutorSessionProvider(1).notifier);
    ctl.start(ep, TutorTone.strictTsundere);
    api.reply = _reply(mistake: true);
    await ctl.sendText('  わたしは サーレム です  ');

    final s = c.read(tutorSessionProvider(1));
    expect(s.messages.length, 3); // opening, learner, ai
    expect(s.messages[1].sender, TutorSender.learner);
    expect(s.lastTurn!.hasMistake, isTrue);
    expect(s.learnerTurns, 1);
    expect(s.loading, isFalse);

    final req = api.requests.single;
    expect(req.userMessage, 'わたしは サーレム です');
    expect(req.tone, TutorTone.strictTsundere);
    expect(req.variables['TONE'], 'strict_tsundere');
    expect(req.variables['EPISODE_ID'], '1');
  });

  test('an error keeps the message; retry does not duplicate it', () async {
    final (c, api, ep) = await _setup();
    c.listen(tutorSessionProvider(1), (_, __) {});
    final ctl = c.read(tutorSessionProvider(1).notifier);
    ctl.start(ep, TutorTone.politeEncouraging);

    api.failWith = const TutorApiException('لا يوجد اتصال');
    await ctl.sendText('はい');
    var s = c.read(tutorSessionProvider(1));
    expect(s.errorAr, 'لا يوجد اتصال');
    expect(s.loading, isFalse);
    expect(s.messages.length, 2);

    api.failWith = null;
    await ctl.retry();
    s = c.read(tutorSessionProvider(1));
    expect(s.errorAr, isNull);
    expect(s.messages.length, 3); // opening, ONE learner message, ai
    expect(api.requests.length, 2);
  });

  test('after conversation_completed nothing more is sent', () async {
    final (c, api, ep) = await _setup();
    c.listen(tutorSessionProvider(1), (_, __) {});
    final ctl = c.read(tutorSessionProvider(1).notifier);
    ctl.start(ep, TutorTone.politeEncouraging);
    api.reply = _reply(completed: true);
    await ctl.sendText('ありがとう');
    expect(c.read(tutorSessionProvider(1)).completed, isTrue);
    await ctl.sendText('もう一回');
    expect(api.requests.length, 1);
  });

  test('a voice turn shows the transcript and uploads the recording',
      () async {
    final (c, api, ep) = await _setup();
    c.listen(tutorSessionProvider(1), (_, __) {});
    final ctl = c.read(tutorSessionProvider(1).notifier);
    ctl.start(ep, TutorTone.politeEncouraging);
    api.reply = _reply(transcript: 'はい、どうぞ');
    await ctl.sendVoice('/tmp/turn.m4a');
    final s = c.read(tutorSessionProvider(1));
    expect(api.audioPaths.single, '/tmp/turn.m4a');
    expect(s.messages[1].japanese, 'はい、どうぞ');
    expect(s.messages[1].sender, TutorSender.learner);
  });
}
