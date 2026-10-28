import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/constants.dart';
import '../models/ai_turn.dart';

/// Readable error for the UI (Arabic message, safe to show).
class TutorApiException implements Exception {
  const TutorApiException(this.messageAr, {this.code});
  final String messageAr;

  /// Short technical reason shown in small print (e.g. "HTTP 502 · llm_failed",
  /// "receiveTimeout") so a problem can be traced in the server logs.
  final String? code;

  @override
  String toString() => 'TutorApiException: $messageAr ($code)';
}

/// Arabic message + short code for a failed request.
TutorApiException tutorErrorFrom(DioException e) {
  final status = e.response?.statusCode;
  final data = e.response?.data;
  final serverCode =
      data is Map && data['error'] is String ? data['error'] as String : null;
  final code = status != null
      ? 'HTTP $status${serverCode != null ? ' · $serverCode' : ''}'
      : e.type.name;
  final message = switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      'انتهت مهلة انتظار المعلم. تأكد من الإنترنت وحاول مرة أخرى.',
    DioExceptionType.connectionError =>
      'تعذّر الوصول إلى خادم المعلم. تأكد من الإنترنت وحاول مرة أخرى.',
    DioExceptionType.badResponse => switch (status) {
        401 => 'التطبيق غير مصرّح له بالاتصال بالخادم (مفتاح التطبيق).',
        413 => 'التسجيل طويل جداً. قل جملة أقصر.',
        429 => 'طلبات كثيرة في وقت قصير. انتظر دقيقة ثم حاول.',
        502 => switch (serverCode) {
            'stt_failed' => 'تعذّر تحويل صوتك إلى نص الآن. حاول مرة أخرى.',
            'tts_failed' => 'تعذّر توليد صوت المعلم الآن. حاول مرة أخرى.',
            _ => 'خدمة الذكاء الاصطناعي لم ترد الآن. حاول مرة أخرى.',
          },
        final int s when s >= 400 && s < 500 =>
          'الخادم رفض الطلب. حدّث التطبيق أو حاول مرة أخرى.',
        _ => 'حدث خطأ في خادم المعلم. حاول مرة أخرى.',
      },
    _ => 'تعذّر الحصول على رد من المعلم. حاول مرة أخرى.',
  };
  return TutorApiException(message, code: code);
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
          throw const TutorApiException('رد الخادم فارغ. حاول مرة أخرى.',
              code: 'empty_body');
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
        throw tutorErrorFrom(e);
      } on FormatException {
        throw const TutorApiException('رد الخادم غير مفهوم. حاول مرة أخرى.',
            code: 'bad_json');
      }
    }
  }
}

/// Pings `/health`, which also wakes a sleeping server (free hosting plans
/// stop idle services; waking takes up to about a minute). Returns true when
/// the server answered, or when no server is configured (nothing to wake).
Future<bool> wakeUpServer() async {
  if (AppConfig.apiBaseUrl.isEmpty) return true;
  try {
    await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 90),
    )).get<void>('${AppConfig.apiBaseUrl}/health');
    return true;
  } on Object {
    return false;
  }
}
