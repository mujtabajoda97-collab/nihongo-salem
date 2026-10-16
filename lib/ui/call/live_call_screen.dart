import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/persona_info.dart';
import '../../providers/live_call.dart';
import '../../providers/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/voice_orb.dart';

String _mmss(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String _phaseLabel(CallPhase p, bool heardSpeech) => switch (p) {
      CallPhase.connecting => 'جارٍ الاتصال…',
      CallPhase.listening =>
        heardSpeech ? 'أسمعك…' : 'تحدّث، ثم اضغط الدائرة عند الانتهاء',
      CallPhase.thinking => 'يفكّر…',
      CallPhase.speaking => 'يتحدّث',
      CallPhase.paused => 'المكالمة متوقفة مؤقتاً',
      CallPhase.error => 'حدثت مشكلة',
      CallPhase.ending => 'جارٍ إنهاء المكالمة…',
      CallPhase.ended => 'انتهت المكالمة',
    };

/// The live voice call: hands-free, turn by turn.
class LiveCallScreen extends ConsumerStatefulWidget {
  const LiveCallScreen({super.key});

  @override
  ConsumerState<LiveCallScreen> createState() => _LiveCallScreenState();
}

class _LiveCallScreenState extends ConsumerState<LiveCallScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(liveCallProvider.notifier).start();
    });
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(liveCallProvider);
    final controller = ref.read(liveCallProvider.notifier);
    final finished = call.phase == CallPhase.ended;

    return PopScope(
      // Back button = end the call (so the summary and the minutes are saved).
      canPop: finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.endCall();
      },
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(AppColors.ink, orbColorFor(call.tone), 0.28)!,
                AppColors.ink,
              ],
            ),
          ),
          child: SafeArea(
            child: finished
                ? _Summary(state: call, onClose: _leave)
                : _ActiveCall(state: call, controller: controller),
          ),
        ),
      ),
    );
  }
}

class _ActiveCall extends ConsumerWidget {
  const _ActiveCall({required this.state, required this.controller});

  final LiveCallState state;
  final LiveCallController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final info = PersonaInfo.of(state.persona);
    final busyEnding = state.phase == CallPhase.ending;

    return Column(
      children: [
        _TopBar(state: state, info: info, onPause: controller.togglePause),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              children: [
                _ReplyText(
                  state: state,
                  showRomaji: settings.showRomaji,
                  showArabic: settings.showArabicTranslation,
                ),
                const SizedBox(height: 16),
                VoiceOrb(
                  phase: state.phase,
                  tone: state.tone,
                  level: state.level,
                  size: 200,
                  onTap: controller.tapOrb,
                ),
                const SizedBox(height: 8),
                Text(
                  _phaseLabel(state.phase, state.heardSpeech),
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                if (state.phase == CallPhase.error && state.errorAr != null)
                  _ErrorBox(
                    message: state.errorAr!,
                    onRetry: controller.retry,
                    onSkip: controller.skipError,
                  ),
                if (state.learnerText != null &&
                    state.learnerText!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: [
                        const Text('أنت قلت',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 12)),
                        JpText(state.learnerText!,
                            size: 16,
                            weight: FontWeight.w400,
                            color: Colors.white60,
                            align: TextAlign.center),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => SlideTransition(
            position: Tween(begin: const Offset(0, 0.4), end: Offset.zero)
                .animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: state.correctionVisible && state.turn != null
              ? Padding(
                  key: ValueKey(state.turn),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: CorrectionBox(turn: state.turn!),
                )
              : const SizedBox(key: ValueKey('none'), height: 0),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            onPressed: busyEnding ? null : controller.endCall,
            icon: busyEnding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.call_end_rounded),
            label: const Text('إنهاء المكالمة'),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.state, required this.info, required this.onPause});

  final LiveCallState state;
  final PersonaInfo info;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final unlimited = state.remainingSeconds == null;
    final seconds = unlimited ? state.elapsedSeconds : state.remainingSeconds!;
    final red = state.lastMinute;
    final canPause = state.phase != CallPhase.connecting &&
        state.phase != CallPhase.ending &&
        state.phase != CallPhase.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: info.color.withValues(alpha: 0.3),
            child: ClipOval(
              child: SizedBox(
                width: 40,
                height: 40,
                child: SafeAssetImage(info.avatar,
                    fallback: Icon(info.icon, color: Colors.white)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.nameAr,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                Text(
                  unlimited ? 'مدة المكالمة' : 'الدقائق المجانية المتبقية',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: red ? const Color(0x33FF5252) : Colors.white12,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: red ? const Color(0xFFFF5252) : Colors.transparent),
              ),
              child: Text(
                _mmss(seconds),
                style: TextStyle(
                  color: red ? const Color(0xFFFF8A80) : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: canPause ? onPause : null,
            color: Colors.white,
            tooltip: state.paused ? 'استئناف' : 'إيقاف مؤقت',
            icon: Icon(state.paused
                ? Icons.play_arrow_rounded
                : Icons.pause_rounded),
          ),
        ],
      ),
    );
  }
}

class _ReplyText extends StatelessWidget {
  const _ReplyText({
    required this.state,
    required this.showRomaji,
    required this.showArabic,
  });

  final LiveCallState state;
  final bool showRomaji;
  final bool showArabic;

  @override
  Widget build(BuildContext context) {
    if (state.japanese.isEmpty) return const SizedBox(height: 60);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          JpText(state.japanese,
              size: 24, color: Colors.white, align: TextAlign.center),
          if (showRomaji && state.romaji.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  state.romaji,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white60,
                      fontStyle: FontStyle.italic,
                      fontSize: 14),
                ),
              ),
            ),
          if (showArabic && state.arabic.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                state.arabic,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, height: 1.6),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({
    required this.message,
    required this.onRetry,
    required this.onSkip,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x33FF5252),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.5)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(110, 40)),
                  onPressed: onRetry,
                  child: const Text('إعادة المحاولة'),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  onPressed: onSkip,
                  child: const Text('تخطَّ'),
                ),
              ],
            ),
          ],
        ),
      );
}

/// Shown when the call is over: the AI's closing summary and next steps.
class _Summary extends ConsumerWidget {
  const _Summary({required this.state, required this.onClose});

  final LiveCallState state;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(premiumProvider);
    final remaining = ref.watch(callRemainingSecondsProvider);
    final settings = ref.watch(appSettingsProvider);
    final outOfTime = remaining != null && remaining <= 0;
    final turn = state.summary;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        const Icon(Icons.check_circle_rounded,
            size: 64, color: Color(0xFF69F0AE)),
        const SizedBox(height: 8),
        const Text('انتهت المكالمة',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('المدة: ${_mmss(state.elapsedSeconds)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70)),
        if (state.errorAr != null && turn == null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(state.errorAr!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, height: 1.5)),
          ),
        if (turn != null) ...[
          const SizedBox(height: 16),
          _ReplyText(
            state: state,
            showRomaji: settings.showRomaji,
            showArabic: settings.showArabicTranslation,
          ),
          const SizedBox(height: 12),
          CorrectionBox(turn: turn),
        ],
        const SizedBox(height: 20),
        if (outOfTime)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.premium),
            onPressed: () => context.push('/paywall'),
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text('اشترك لمكالمات غير محدودة'),
          )
        else
          FilledButton.icon(
            onPressed: () => context.pushReplacement('/call'),
            icon: const Icon(Icons.call_rounded),
            label: const Text('مكالمة جديدة'),
          ),
        const SizedBox(height: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
          onPressed: () => context.go('/'),
          child: const Text('العودة إلى الرئيسية'),
        ),
        if (!premium && !outOfTime)
          TextButton(
            onPressed: () => context.push('/paywall'),
            child: const Text('جرّب الاشتراك: مكالمات بلا حدود'),
          ),
        TextButton(
          onPressed: onClose,
          style: TextButton.styleFrom(foregroundColor: Colors.white54),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}
