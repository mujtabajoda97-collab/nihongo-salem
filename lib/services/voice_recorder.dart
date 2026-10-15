import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Microphone for the live call: records to a file and reports the voice level
/// (0..1, about ten times a second) so the call can detect when the learner
/// stops talking and animate the orb.
abstract interface class VoiceRecorder {
  /// Asks for the microphone permission if needed.
  Future<bool> hasPermission();

  /// Starts a new recording.
  Future<void> start();

  /// Voice level while recording (broadcast stream).
  Stream<double> get levels;

  /// Stops and returns the file path (null if nothing was recorded).
  Future<String?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();

  Future<void> dispose();
}

class RecordVoiceRecorder implements VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<double> _levels = StreamController<double>.broadcast();
  StreamSubscription<Amplitude>? _amplitudeSub;

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/call_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);
    await _amplitudeSub?.cancel();
    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((a) {
      // dBFS: about -50 (quiet room) .. 0 (very loud) -> 0..1
      final level = ((a.current + 50) / 50).clamp(0.0, 1.0).toDouble();
      if (!_levels.isClosed) _levels.add(level);
    });
  }

  @override
  Future<String?> stop() async {
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    try {
      return await _recorder.stop();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    try {
      await _recorder.cancel();
    } on Object {
      // not recording
    }
  }

  @override
  Future<void> dispose() async {
    await _amplitudeSub?.cancel();
    await _levels.close();
    await _recorder.dispose();
  }
}
