import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_models.dart';

/// Thin typed wrapper over SharedPreferences. A corrupt value is treated as
/// missing (the app starts from defaults) instead of crashing at launch.
class LocalStorageService {
  LocalStorageService(this._prefs);

  final SharedPreferences _prefs;

  static const _kUserState = 'user_state_v1';
  static const _kSettings = 'app_settings_v1';
  static const _kCallQuota = 'call_quota_v1';
  static const _kPremiumCache = 'premium_cache_v1';

  UserState? loadUserState() => _read(_kUserState, UserState.fromJson);
  Future<void> saveUserState(UserState s) => _write(_kUserState, s.toJson());

  AppSettings? loadSettings() => _read(_kSettings, AppSettings.fromJson);
  Future<void> saveSettings(AppSettings s) => _write(_kSettings, s.toJson());

  CallQuota? loadCallQuota() => _read(_kCallQuota, CallQuota.fromJson);
  Future<void> saveCallQuota(CallQuota q) => _write(_kCallQuota, q.toJson());

  /// Last known subscription answer, or null if none / older than [maxAge].
  bool? loadPremiumCache({required DateTime now, required Duration maxAge}) {
    final m = _readMap(_kPremiumCache);
    if (m == null) return null;
    final value = m['premium'];
    final at = DateTime.tryParse('${m['at']}');
    if (value is! bool || at == null) return null;
    if (now.difference(at) > maxAge) return null;
    return value;
  }

  Future<void> savePremiumCache(bool premium, DateTime now) =>
      _write(_kPremiumCache, {'premium': premium, 'at': now.toIso8601String()});

  /// Wipes everything (sign-out / "reset progress").
  Future<void> clearAll() async {
    for (final k in [_kUserState, _kSettings, _kCallQuota, _kPremiumCache]) {
      await _prefs.remove(k);
    }
  }

  T? _read<T>(String key, T Function(Map<String, dynamic>) parse) {
    final m = _readMap(key);
    if (m == null) return null;
    try {
      return parse(m);
    } on Object {
      return null;
    }
  }

  Map<String, dynamic>? _readMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(String key, Map<String, dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));
}
