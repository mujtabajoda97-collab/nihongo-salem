import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/constants.dart';
import '../models/ai_turn.dart';

/// Readable error for the UI (Arabic message, safe to show).
class TutorApiException implements Exception {
  const TutorApiException(this.messageAr);
  final String messageAr;

  @override
  String toString() => 'TutorApiException: $messageAr';
}

/// Server contract for station D (one HTTP call per learner turn).
///
///   POST {API_BASE_URL}/v1/turn
///   - text turn : application/json  = TutorTurnRequest.toJson()
///   - voice turn: multipart/form-data
///         payload = TutorTurnRequest.toJson() as a JSON string
///         audio   = the recording (m4a)
///   200 -> JSON: the 7 keys of AiTurnResponse, flat, plus optional
///         "user_transcript" (what Whisper heard) and
///         "audio_url" (the TTS reply, played with just_audio).
abstract interface class TutorApi {
  Future<TutorReply> sendTurn(TutorTurnRequest request, {String? audioPath});

  /// One turn of the free live call (same endpoint, `mode: free_talk`).
  Future<TutorReply> sendFreeTalkTurn(FreeTalkTurnRequest request,
      {String? audioPath});
}

class DioTutorApi implements TutorApi {
  DioTutorApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              headers: {
                if (AppConfig.appApiKey.isNotEmpty) 'x-app-key': AppConfig.appApiKey,
              },
              // The free hosting plan puts the server to sleep when idle; waking it
              // up takes up to ~a minute, so the first call must wait that long.
              connectTimeout: const Duration(seconds: 75),
              sendTimeout: const Duration(seconds: 40),
              receiveTimeout: const Duration(seconds: 90),
            ));

  final Dio _dio;

  @override
  Future<TutorReply> sendTurn(TutorTurnRequest request, {String? audioPath}) =>
      _post(request.toJson(), audioPath);

  @override
  Future<TutorReply> sendFreeTalkTurn(FreeTalkTurnRequest request,
          {String? audioPath}) =>
      _post(request.toJson(), audioPath);

  Future<TutorReply> _post(Map<String, dynamic> json, String? audioPath) async {
    if (_dio.options.baseUrl.isEmpty) {
      throw const TutorApiException(
          'خادم المحادثة غير مُعدّ بعد. يمكنك تخطي هذه المحطة.');
    }
    for (var attempt = 0;; attempt++) {
      try {
        // FormData can be sent only once, so it is rebuilt for every attempt.
        final Object data = audioPath == null
            ? json
            : FormData.fromMap({
                'payload': jsonEncode(json),
                'audio': await MultipartFile.fromFile(audioPath,
                    filename: 'turn.m4a'),
              });
        final response =
            await _dio.post<Map<String, dynamic>>('/v1/turn', data: data);
        final body = response.data;
        if (body == null) {
          throw const TutorApiException('رد الخادم فارغ. حاول مرة أخرى.');
        }
        return TutorReply.fromJson(body);
      } on DioException catch (e) {
        final cantReach = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.connectionError;
        if (cantReach && attempt == 0) {
          // The server was probably asleep: it is awake now, try once more.
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        throw TutorApiException(switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout =>
            'انتهت مهلة الاتصال. تأكد من الإنترنت وحاول مرة أخرى.',
          DioExceptionType.connectionError =>
            'لا يوجد اتصال بالإنترنت. حاول مرة أخرى.',
          _ => 'تعذّر الحصول على رد من المعلم. حاول مرة أخرى.',
        });
      } on FormatException {
        throw const TutorApiException('رد الخادم غير مفهوم. حاول مرة أخرى.');
      }
    }
  }
}

/// Fire-and-forget ping that wakes a sleeping server (free hosting plans stop
/// idle services). Call it when the app starts and before a call begins.
Future<void> wakeUpServer() async {
  if (AppConfig.apiBaseUrl.isEmpty) return;
  try {
    await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 90),
    )).get<void>('${AppConfig.apiBaseUrl}/health');
  } on Object {
    // best effort only
  }
}
