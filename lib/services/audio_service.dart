import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../core/constants.dart';

/// Plays lesson audio (bundled mp3) and server voice replies (URL).
///
/// Every play method returns `false` instead of throwing when the file is
/// missing or cannot be played, so the screens fall back gracefully (the audio
/// files are produced separately from the app code).
abstract interface class AudioService {
  Future<bool> playAsset(String assetPath, {bool slow = false});
  Future<bool> playUrl(String url);

  /// Plays a server voice reply and completes when it has finished (or was
  /// stopped). Returns false if it could not be played at all.
  Future<bool> playUrlAndWait(String url);
  Future<void> stop();
  Future<void> dispose();
}

class JustAudioService implements AudioService {
  JustAudioService() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<bool> playAsset(String assetPath, {bool slow = false}) async {
    try {
      await _player.stop();
      await _player.setAsset(assetPath);
      await _player.setSpeed(slow ? AppRules.slowAudioSpeed : 1.0);
      unawaited(_player.play().catchError((Object _) {}));
      return true;
    } on Object {
      // The mp3 is not bundled in the app: ask the server, which generates the
      // lesson clip the first time and serves it from its cache afterwards.
      return _playFromServer(assetPath, slow);
    }
  }

  Future<bool> _playFromServer(String assetPath, bool slow) async {
    final base = AppConfig.apiBaseUrl;
    final file = assetPath.split('/').last;
    if (base.isEmpty || !file.endsWith('.mp3')) return false;
    try {
      await _player.stop();
      await _player.setUrl('$base/v1/lesson-audio/$file');
      await _player.setSpeed(slow ? AppRules.slowAudioSpeed : 1.0);
      unawaited(_player.play().catchError((Object _) {}));
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> playUrl(String url) async {
    try {
      await _player.stop();
      await _player.setUrl(url);
      await _player.setSpeed(1.0);
      unawaited(_player.play().catchError((Object _) {}));
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> playUrlAndWait(String url) async {
    try {
      await _player.stop();
      await _player.setUrl(url);
      await _player.setSpeed(1.0);
      // play() completes when playback ends or stop() is called.
      await _player.play().timeout(const Duration(seconds: 90));
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } on Object {
      // nothing to stop
    }
  }

  @override
  Future<void> dispose() => _player.dispose();
}
