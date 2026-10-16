import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cloud_sync.dart';
import 'kana_course.dart';
import 'providers.dart';

const _kSessionKey = 'cloud_session_v1';

final cloudServiceProvider = Provider<CloudService>((ref) => CloudService());

/// The signed-in account (null = guest). Saved on the device.
final cloudSessionProvider =
    NotifierProvider<CloudSessionController, CloudSession?>(CloudSessionController.new);

class CloudSessionController extends Notifier<CloudSession?> {
  @override
  CloudSession? build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_kSessionKey);
    if (raw == null) return null;
    try {
      return CloudSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  void set(CloudSession? s) {
    state = s;
    final prefs = ref.read(sharedPreferencesProvider);
    if (s == null) {
      unawaited(prefs.remove(_kSessionKey));
    } else {
      unawaited(prefs.setString(_kSessionKey, jsonEncode(s.toJson())));
    }
  }
}

enum SyncPhase { idle, syncing, done, failed }

class SyncStatus {
  const SyncStatus(this.phase, {this.lastSync, this.error});

  final SyncPhase phase;
  final DateTime? lastSync;
  final String? error;
}

/// Signs in/up and keeps the learner's progress saved in the cloud:
/// pulls and merges when signing in, then pushes (debounced) after every change.
final cloudSyncProvider =
    NotifierProvider<CloudSyncController, SyncStatus>(CloudSyncController.new);

class CloudSyncController extends Notifier<SyncStatus> {
  Timer? _debounce;
  bool _applying = false;

  @override
  SyncStatus build() {
    ref.onDispose(() => _debounce?.cancel());
    void changed(Object? _, Object? __) {
      if (_applying || ref.read(cloudSessionProvider) == null) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 3), () => unawaited(syncNow()));
    }

    ref.listen(userStateProvider, changed);
    ref.listen(kanaProgressProvider, changed);
    ref.listen(appSettingsProvider, changed);

    if (ref.read(cloudSessionProvider) != null) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (ref.exists(cloudSessionProvider)) unawaited(syncNow());
      });
    }
    return const SyncStatus(SyncPhase.idle);
  }

  CloudService get _service => ref.read(cloudServiceProvider);

  /// Throws [CloudException] with an Arabic message.
  Future<void> signIn(String email, String password) async {
    final s = await _service.signIn(email.trim(), password);
    ref.read(cloudSessionProvider.notifier).set(s);
    await syncNow();
  }

  Future<void> signUp(String email, String password) async {
    final s = await _service.signUp(email.trim(), password);
    ref.read(cloudSessionProvider.notifier).set(s);
    await syncNow();
  }

  void signOut() {
    _debounce?.cancel();
    ref.read(cloudSessionProvider.notifier).set(null);
    state = const SyncStatus(SyncPhase.idle);
  }

  Future<CloudSession?> _fresh() async {
    var s = ref.read(cloudSessionProvider);
    if (s == null) return null;
    if (s.expiresSoon) {
      s = await _service.refresh(s);
      ref.read(cloudSessionProvider.notifier).set(s);
    }
    return s;
  }

  /// Pull -> merge -> apply -> push. Safe to call any time.
  Future<void> syncNow() async {
    state = SyncStatus(SyncPhase.syncing, lastSync: state.lastSync);
    try {
      final s = await _fresh();
      if (s == null) {
        state = const SyncStatus(SyncPhase.idle);
        return;
      }
      final cloud = await _service.fetchProgress(s);
      final merged = mergeProgress(
        ref.read(userStateProvider),
        ref.read(kanaProgressProvider),
        cloud,
      );
      _applying = true;
      try {
        // Only touch local state when the merge really changed something,
        // otherwise the change listeners would trigger another sync forever.
        if (jsonEncode(merged.user.toJson()) !=
            jsonEncode(ref.read(userStateProvider).toJson())) {
          ref.read(userStateProvider.notifier).replaceFromCloud(merged.user);
        }
        if (merged.kana.toJsonString() != ref.read(kanaProgressProvider).toJsonString()) {
          ref.read(kanaProgressProvider.notifier).replaceFromCloud(merged.kana);
        }
      } finally {
        _applying = false;
      }
      await _service.pushProgress(
        s,
        buildProgressPayload(merged.user, merged.kana, ref.read(appSettingsProvider)),
      );
      state = SyncStatus(SyncPhase.done, lastSync: DateTime.now());
    } on Object catch (e) {
      final msg = e is CloudException ? e.messageAr : CloudService.messageFor(e);
      if (e is CloudException && e.messageAr.startsWith('انتهت جلسة')) {
        ref.read(cloudSessionProvider.notifier).set(null);
      }
      state = SyncStatus(SyncPhase.failed, lastSync: state.lastSync, error: msg);
    }
  }
}
