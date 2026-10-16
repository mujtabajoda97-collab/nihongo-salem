import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/kana_course.dart';
import '../models/user_models.dart';

/// Where the accounts live (Supabase: auth + one row of progress per user).
/// The publishable key is public by design; row-level security keeps every
/// user to their own row.
abstract final class CloudConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wsvvafdybopdastfxuqo.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_Lf9sPQhVy_7kzyOauowMeg_sCECXhFg',
  );
}

class CloudSession {
  const CloudSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
  });

  factory CloudSession.fromAuthJson(Map<String, dynamic> j, {String? fallbackEmail}) {
    final user = j['user'] is Map<String, dynamic> ? j['user'] as Map<String, dynamic> : const {};
    final expiresIn = j['expires_in'] is int ? j['expires_in'] as int : 3600;
    final expiresAt = j['expires_at'] is int
        ? j['expires_at'] as int
        : DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn;
    return CloudSession(
      accessToken: j['access_token'] as String,
      refreshToken: (j['refresh_token'] as String?) ?? '',
      expiresAt: expiresAt,
      userId: (user['id'] as String?) ?? '',
      email: (user['email'] as String?) ?? fallbackEmail ?? '',
    );
  }

  factory CloudSession.fromJson(Map<String, dynamic> j) => CloudSession(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        expiresAt: j['expires_at'] as int,
        userId: j['user_id'] as String,
        email: j['email'] as String,
      );

  final String accessToken;
  final String refreshToken;

  /// Unix seconds.
  final int expiresAt;
  final String userId;
  final String email;

  bool get expiresSoon => expiresAt - DateTime.now().millisecondsSinceEpoch ~/ 1000 < 90;

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt,
        'user_id': userId,
        'email': email,
      };
}

/// A problem the learner can understand (already in Arabic).
class CloudException implements Exception {
  const CloudException(this.messageAr, {this.needsEmailConfirmation = false});

  final String messageAr;
  final bool needsEmailConfirmation;

  @override
  String toString() => messageAr;
}

class CloudService {
  CloudService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: CloudConfig.url,
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 25),
              headers: {'apikey': CloudConfig.publishableKey},
            ));

  final Dio _dio;

  static String messageFor(Object e) {
    if (e is CloudException) return e.messageAr;
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        final code = '${data['error_code'] ?? data['code'] ?? ''}';
        final msg = '${data['msg'] ?? data['message'] ?? data['error_description'] ?? ''}'.toLowerCase();
        if (code == 'invalid_credentials' || msg.contains('invalid login')) {
          return 'البريد أو كلمة المرور غير صحيحة';
        }
        if (code == 'user_already_exists' || msg.contains('already registered')) {
          return 'هذا البريد مسجّل مسبقاً، سجّل الدخول بدلاً من إنشاء حساب';
        }
        if (code == 'weak_password' || msg.contains('password should')) {
          return 'كلمة المرور ضعيفة، استعمل 6 أحرف على الأقل';
        }
        if (code == 'email_not_confirmed') {
          return 'فعّل بريدك أولاً من الرسالة التي وصلتك ثم سجّل الدخول';
        }
        if (code.contains('rate_limit') || msg.contains('rate limit')) {
          return 'محاولات كثيرة، انتظر قليلاً ثم أعد المحاولة';
        }
        if (code == 'validation_failed' || msg.contains('valid email')) {
          return 'اكتب بريداً إلكترونياً صحيحاً';
        }
      }
      if (e.response == null) return 'تعذّر الاتصال، تحقق من الإنترنت وأعد المحاولة';
    }
    return 'حدث خطأ غير متوقع، أعد المحاولة';
  }

  Future<CloudSession> signIn(String email, String password) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/v1/token',
        queryParameters: {'grant_type': 'password'},
        data: {'email': email, 'password': password},
      );
      return CloudSession.fromAuthJson(res.data!, fallbackEmail: email);
    } on DioException catch (e) {
      throw CloudException(messageFor(e));
    }
  }

  /// Creates the account. When the project requires email confirmation there
  /// is no session yet: [CloudException.needsEmailConfirmation] is set.
  Future<CloudSession> signUp(String email, String password) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/v1/signup',
        data: {'email': email, 'password': password},
      );
      final data = res.data!;
      if (data['access_token'] is String) {
        return CloudSession.fromAuthJson(data, fallbackEmail: email);
      }
      throw const CloudException(
        'أنشأنا حسابك. أرسلنا لك رسالة تفعيل على بريدك، افتحها ثم سجّل الدخول هنا.',
        needsEmailConfirmation: true,
      );
    } on DioException catch (e) {
      throw CloudException(messageFor(e));
    }
  }

  Future<CloudSession> refresh(CloudSession s) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/v1/token',
        queryParameters: {'grant_type': 'refresh_token'},
        data: {'refresh_token': s.refreshToken},
      );
      return CloudSession.fromAuthJson(res.data!, fallbackEmail: s.email);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 400 || code == 401) {
        throw const CloudException('انتهت جلسة الدخول، سجّل الدخول من جديد');
      }
      throw CloudException(messageFor(e));
    }
  }

  Options _auth(CloudSession s) => Options(headers: {'Authorization': 'Bearer ${s.accessToken}'});

  /// The progress saved in the cloud, or null if this account has none yet.
  Future<Map<String, dynamic>?> fetchProgress(CloudSession s) async {
    try {
      final res = await _dio.get<List<dynamic>>(
        '/rest/v1/user_progress',
        queryParameters: {'select': 'data', 'user_id': 'eq.${s.userId}'},
        options: _auth(s),
      );
      final rows = res.data ?? const [];
      if (rows.isEmpty) return null;
      final row = rows.first;
      if (row is Map<String, dynamic> && row['data'] is Map<String, dynamic>) {
        return row['data'] as Map<String, dynamic>;
      }
      return null;
    } on DioException catch (e) {
      throw CloudException(messageFor(e));
    }
  }

  Future<void> pushProgress(CloudSession s, Map<String, dynamic> data) async {
    try {
      await _dio.post<void>(
        '/rest/v1/user_progress',
        queryParameters: {'on_conflict': 'user_id'},
        data: jsonEncode({
          'user_id': s.userId,
          'data': data,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
        options: Options(
          headers: {
            'Authorization': 'Bearer ${s.accessToken}',
            'Prefer': 'resolution=merge-duplicates,return=minimal',
          },
          contentType: Headers.jsonContentType,
        ),
      );
    } on DioException catch (e) {
      throw CloudException(messageFor(e));
    }
  }
}

// ---------------------------------------------------------------------------
// Progress payload + merge
// ---------------------------------------------------------------------------

Map<String, dynamic> buildProgressPayload(UserState user, KanaProgress kana, AppSettings settings) => {
      'v': 1,
      'user': user.toJson(),
      'kana': jsonDecode(kana.toJsonString()),
      'settings': settings.toJson(),
    };

Map<int, int> _maxStars(Map<int, int> a, Map<int, int> b) {
  final out = {...a};
  b.forEach((k, v) {
    if (v > (out[k] ?? 0)) out[k] = v;
  });
  return out;
}

class MergedProgress {
  const MergedProgress(this.user, this.kana);

  final UserState user;
  final KanaProgress kana;
}

/// Combines this device's progress with the cloud's. Nothing is ever lost:
/// finished episodes/lessons are unioned and the best stars win.
MergedProgress mergeProgress(UserState local, KanaProgress localKana, Map<String, dynamic>? cloud) {
  if (cloud == null) return MergedProgress(local, localKana);
  final cu = cloud['user'] is Map<String, dynamic>
      ? UserState.fromJson(cloud['user'] as Map<String, dynamic>)
      : const UserState();
  final ck = cloud['kana'] is Map<String, dynamic>
      ? KanaProgress.fromJsonString(jsonEncode(cloud['kana']))
      : const KanaProgress();

  final usePlacementFromLocal = local.placementCompleted || !cu.placementCompleted;
  final lastActive = [local.lastActiveDate, cu.lastActiveDate].whereType<String>().fold<String?>(
      null, (best, d) => best == null || d.compareTo(best) > 0 ? d : best);

  final user = UserState(
    displayName: local.displayName != const UserState().displayName ? local.displayName : cu.displayName,
    placementCompleted: local.placementCompleted || cu.placementCompleted,
    placementScore: usePlacementFromLocal ? local.placementScore : cu.placementScore,
    startEpisode: usePlacementFromLocal ? local.startEpisode : cu.startEpisode,
    freeWindowStart: usePlacementFromLocal
        ? (local.freeWindowStart ?? cu.freeWindowStart)
        : (cu.freeWindowStart ?? local.freeWindowStart),
    completedEpisodes: {...local.completedEpisodes, ...cu.completedEpisodes},
    stars: _maxStars(local.stars, cu.stars),
    streakDays: local.streakDays > cu.streakDays ? local.streakDays : cu.streakDays,
    lastActiveDate: lastActive,
  );
  final kana = KanaProgress(
    completed: {...localKana.completed, ...ck.completed},
    stars: _maxStars(localKana.stars, ck.stars),
  );
  return MergedProgress(user, kana);
}
