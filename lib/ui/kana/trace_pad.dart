import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

/// Drawing area for practising how a letter is written: a faint model of the
/// letter sits behind, the learner traces it with a finger.
class TracePad extends StatefulWidget {
  const TracePad({super.key, required this.glyph, required this.strokes});

  final String glyph;

  /// Number of strokes the real letter has (shown as a hint).
  final int strokes;

  @override
  State<TracePad> createState() => _TracePadState();
}

class _TracePadState extends State<TracePad> {
  final List<List<Offset>> _lines = [];

  @override
  void didUpdateWidget(TracePad old) {
    super.didUpdateWidget(old);
    if (old.glyph != widget.glyph) _lines.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final big = widget.glyph.runes.length <= 1;
    final matches = _lines.length == widget.strokes;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFEAE6F0), width: 2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _GuidePainter()),
                  Center(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        widget.glyph,
                        style: GoogleFonts.notoSansJp(
                          fontSize: big ? 190 : 120,
                          color: AppColors.ink.withValues(alpha: 0.12),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => setState(() => _lines.add([d.localPosition])),
                    onPanUpdate: (d) => setState(() {
                      if (_lines.isNotEmpty) _lines.last.add(d.localPosition);
                    }),
                    child: CustomPaint(painter: _InkPainter(_lines)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(matches ? Icons.check_circle_rounded : Icons.edit_rounded,
                size: 20, color: matches ? AppColors.success : AppColors.lockedGrey),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'عدد ضربات الحرف: ${widget.strokes}  ·  رسمتَ: ${_lines.length}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton.icon(
              onPressed: _lines.isEmpty ? null : () => setState(_lines.clear),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('مسح'),
            ),
          ],
        ),
      ],
    );
  }
}

class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFEAE6F0)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), p);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.lines);

  final List<List<Offset>> lines;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.brand
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final line in lines) {
      if (line.length == 1) {
        canvas.drawCircle(line.first, 4.5, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(line.first.dx, line.first.dy);
      for (final o in line.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) => true;
}
