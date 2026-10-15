import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/enums.dart';
import '../../providers/live_call.dart';

/// Orb colour for each emotion_tone the AI can return.
Color orbColorFor(EmotionTone tone) => switch (tone) {
      EmotionTone.happy => const Color(0xFFF5A623),
      EmotionTone.strict => const Color(0xFFD7263D),
      EmotionTone.sigh => const Color(0xFF78909C),
      EmotionTone.excited => const Color(0xFFEC4899),
      EmotionTone.calm => const Color(0xFF14A38B),
    };

/// The pulsing voice orb of the live call.
///
///  - listening: glow rings follow the microphone [level]
///  - thinking : three dots orbit
///  - speaking : slow breathing pulse
///  - paused / error / ended: still and dimmed
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    required this.phase,
    required this.tone,
    required this.level,
    this.size = 220,
    this.onTap,
  });

  final CallPhase phase;
  final EmotionTone tone;

  /// Microphone level 0..1.
  final double level;
  final double size;
  final VoidCallback? onTap;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  double _smooth = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = orbColorFor(widget.tone);
    return Semantics(
      button: widget.onTap != null,
      label: 'الكرة الصوتية',
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              // Ease toward the target so the rings do not jitter.
              _smooth += (widget.level - _smooth) * 0.35;
              return CustomPaint(
                painter: _OrbPainter(
                  t: _ctrl.value,
                  phase: widget.phase,
                  color: color,
                  level: _smooth,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.t,
    required this.phase,
    required this.color,
    required this.level,
  });

  final double t;
  final CallPhase phase;
  final Color color;
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide * 0.30;
    final wave = sin(t * 2 * pi);

    final dimmed = phase == CallPhase.paused ||
        phase == CallPhase.error ||
        phase == CallPhase.ended;

    // Activity 0..1 for the glow.
    final double activity = switch (phase) {
      CallPhase.listening => level.clamp(0.0, 1.0).toDouble(),
      CallPhase.speaking => 0.45 + 0.25 * wave,
      CallPhase.thinking || CallPhase.connecting || CallPhase.ending => 0.25,
      _ => 0.0,
    };

    final radius = base * (1 + 0.10 * activity + (dimmed ? 0 : 0.03 * wave));
    final alpha = dimmed ? 0.45 : 1.0;

    // Glow rings.
    for (var i = 3; i >= 1; i--) {
      final ring = radius * (1 + i * (0.14 + 0.22 * activity));
      final paint = Paint()
        ..color = color.withValues(alpha: (0.14 - i * 0.03) * alpha + 0.02)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(c, ring, paint);
    }

    // Body with a soft highlight.
    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        colors: [
          Color.lerp(color, Colors.white, 0.45)!.withValues(alpha: alpha),
          color.withValues(alpha: alpha),
          Color.lerp(color, Colors.black, 0.25)!.withValues(alpha: alpha),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: radius));
    canvas.drawCircle(c, radius, body);

    // Thinking: three dots orbiting the orb.
    if (phase == CallPhase.thinking ||
        phase == CallPhase.connecting ||
        phase == CallPhase.ending) {
      final dot = Paint()..color = Colors.white.withValues(alpha: 0.9);
      for (var i = 0; i < 3; i++) {
        final a = t * 2 * pi + i * 2 * pi / 3;
        final p = c + Offset(cos(a), sin(a)) * (radius * 0.55);
        canvas.drawCircle(p, radius * 0.07, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.t != t ||
      old.phase != phase ||
      old.color != color ||
      old.level != level;
}
