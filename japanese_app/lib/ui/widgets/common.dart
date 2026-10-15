import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/ai_turn.dart';
import '../../providers/providers.dart';
import '../theme.dart';

/// Japanese text: always left-to-right inside the right-to-left Arabic UI.
class JpText extends StatelessWidget {
  const JpText(
    this.text, {
    super.key,
    this.size = 22,
    this.weight = FontWeight.w600,
    this.color,
    this.align = TextAlign.start,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final Color? color;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          text,
          textAlign: align,
          style: GoogleFonts.notoSansJp(
            fontSize: size,
            fontWeight: weight,
            color: color,
            height: 1.5,
          ),
        ),
      );
}

/// Romaji / any Latin helper line (left-to-right, muted).
class RomajiText extends StatelessWidget {
  const RomajiText(this.text,
      {super.key, this.size = 14, this.align = TextAlign.start});

  final String text;
  final double size;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(
            fontSize: size,
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

/// Image from the bundle, with an elegant placeholder when the file is
/// missing (the artwork is delivered separately from the app code).
class SafeAssetImage extends StatelessWidget {
  const SafeAssetImage(
    this.path, {
    super.key,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  final String path;
  final BoxFit fit;

  /// Shown when the file cannot be loaded. Default: a soft gradient.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) => Image.asset(
        path,
        fit: fit,
        errorBuilder: (_, __, ___) => fallback ?? const GradientPlaceholder(),
      );
}

class GradientPlaceholder extends StatelessWidget {
  const GradientPlaceholder({super.key, this.icon = Icons.landscape_rounded});

  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFD9DE), Color(0xFFE6DDFB)],
          ),
        ),
        child: Center(
          child: Icon(icon, size: 56, color: Colors.white.withValues(alpha: 0.8)),
        ),
      );
}

/// Round character picture; a coloured circle with the first letter when the
/// image is missing.
class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar({
    super.key,
    required this.path,
    required this.name,
    this.radius = 28,
  });

  final String path;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial =
        trimmed.isEmpty ? '?' : String.fromCharCode(trimmed.runes.first);
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: SafeAssetImage(
          path,
          fallback: ColoredBox(
            color: AppColors.brand.withValues(alpha: 0.15),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: radius * 0.9,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Speaker button. If the audio file does not exist yet, it shows a quiet
/// message instead of failing.
class AudioButton extends ConsumerStatefulWidget {
  const AudioButton({
    super.key,
    required this.assetPath,
    this.slow,
    this.size = 44,
    this.label,
  });

  final String assetPath;

  /// null => follow the "slow audio" setting.
  final bool? slow;
  final double size;
  final String? label;

  @override
  ConsumerState<AudioButton> createState() => _AudioButtonState();
}

class _AudioButtonState extends ConsumerState<AudioButton> {
  bool _missing = false;

  Future<void> _play() async {
    final slow = widget.slow ?? ref.read(appSettingsProvider).slowAudio;
    final ok =
        await ref.read(audioServiceProvider).playAsset(widget.assetPath, slow: slow);
    if (!mounted) return;
    if (!ok) {
      setState(() => _missing = true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('ملف الصوت غير متوفر بعد'),
          duration: Duration(seconds: 2),
        ));
    } else if (_missing) {
      setState(() => _missing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _missing ? Icons.volume_off_rounded : Icons.volume_up_rounded;
    if (widget.label != null) {
      return OutlinedButton.icon(
        onPressed: _play,
        icon: Icon(icon),
        label: Text(widget.label!),
        style: OutlinedButton.styleFrom(minimumSize: Size(0, widget.size)),
      );
    }
    return IconButton.filledTonal(
      onPressed: _play,
      icon: Icon(icon),
      iconSize: widget.size * 0.55,
      constraints: BoxConstraints.tightFor(width: widget.size, height: widget.size),
      tooltip: 'استمع',
    );
  }
}

class StarsRow extends StatelessWidget {
  const StarsRow({super.key, required this.count, this.max = 3, this.size = 18});

  final int count;
  final int max;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < max; i++)
            Icon(
              i < count ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: i < count ? AppColors.gold : AppColors.lockedGrey,
            ),
        ],
      );
}

/// The AI's correction: green when there is no mistake, orange with a warning
/// when `has_mistake` is true.
class CorrectionBox extends StatelessWidget {
  const CorrectionBox({super.key, required this.turn});

  final AiTurnResponse turn;

  @override
  Widget build(BuildContext context) {
    final bad = turn.hasMistake;
    final color = bad ? AppColors.warning : AppColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bad ? AppColors.warningSoft : AppColors.successSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            bad ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              turn.correctionAr,
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// Text that may be Arabic or Japanese (quiz options): picks the right
/// direction and font automatically.
class MixedText extends StatelessWidget {
  const MixedText(this.text, {super.key, this.size = 18});

  final String text;
  final double size;

  static final RegExp _arabic = RegExp(r'[\u0600-\u06FF]');

  @override
  Widget build(BuildContext context) => _arabic.hasMatch(text)
      ? Text(text, style: TextStyle(fontSize: size, height: 1.5))
      : JpText(text, size: size + 2, weight: FontWeight.w500);
}

/// Keeps a PageView page alive so its state survives switching pages.
class KeepAlivePage extends StatefulWidget {
  const KeepAlivePage({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
