import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/constants.dart';
import '../../models/enums.dart';
import '../../models/episode.dart';
import '../../providers/providers.dart';
import '../../providers/tutor_session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Station D: a short role-play with the AI tutor, by voice or text.
///
/// Sensei Ken (the coach) shows the Arabic correction under each answer,
/// green when `has_mistake` is false and orange when it is true. The station
/// can always be skipped: without a server the lesson still completes.
class VoiceStation extends ConsumerStatefulWidget {
  const VoiceStation({super.key, required this.episode, required this.onDone});

  final Episode episode;

  /// `skipped` is true when the learner left without talking.
  final void Function({required bool skipped}) onDone;

  @override
  ConsumerState<VoiceStation> createState() => _VoiceStationState();
}

class _VoiceStationState extends ConsumerState<VoiceStation> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  bool _recording = false;
  late TutorTone _tone = ref.read(appSettingsProvider).tutorTone;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  TutorSessionController get _session =>
      ref.read(tutorSessionProvider(widget.episode.id).notifier);

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _start() {
    ref.read(appSettingsProvider.notifier).setTutorTone(_tone);
    _session.start(widget.episode, _tone);
  }

  Future<void> _sendText() async {
    final value = _text.text;
    if (value.trim().isEmpty) return;
    _text.clear();
    await _session.sendText(value);
  }

  Future<void> _toggleRecording() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_recording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() => _recording = false);
      if (path != null) await _session.sendVoice(path);
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        messenger.showSnackBar(const SnackBar(
            content: Text('فعّل إذن الميكروفون من إعدادات الجهاز لتتحدث بصوتك')));
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/turn_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path);
      if (mounted) setState(() => _recording = true);
    } on Object {
      messenger.showSnackBar(
          const SnackBar(content: Text('تعذّر تشغيل الميكروفون')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(tutorSessionProvider(widget.episode.id));
    ref.listen(tutorSessionProvider(widget.episode.id), (prev, next) {
      if (prev?.messages.length != next.messages.length || prev?.loading != next.loading) {
        _scrollToEnd();
      }
    });

    if (!session.started) return _buildIntro(context);
    return _buildChat(context, session);
  }

  // ---- before the conversation starts ------------------------------------

  Widget _buildIntro(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          Center(
            child: CharacterAvatar(
                path: AppRules.senseiKenAvatar, name: 'ケン', radius: 44),
          ),
          const SizedBox(height: 12),
          Text('محادثة مع المعلم',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'ستتحدث مع شخصية الحلقة باليابانية، وسينسي كين يصحّح لك بالعربية بعد كل إجابة.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
          ),
          const SizedBox(height: 20),
          Text('اختر أسلوب سينسي كين', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final t in TutorTone.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _tone = t),
                child: Ink(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _tone == t
                        ? AppColors.brand.withValues(alpha: 0.08)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _tone == t
                          ? AppColors.brand
                          : const Color(0xFFD9D4E3),
                      width: _tone == t ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _tone == t
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: _tone == t ? AppColors.brand : AppColors.lockedGrey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(t.labelAr)),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('ابدأ المحادثة'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => widget.onDone(skipped: true),
            child: const Text('تخطي هذه المحطة وإنهاء الدرس'),
          ),
        ],
      ),
    );
  }

  // ---- the conversation ---------------------------------------------------

  Widget _buildChat(BuildContext context, TutorSessionState session) {
    final counterpart = widget.episode.dialogues.firstWhere(
      (d) => !d.isLearnerLine,
      orElse: () => widget.episode.dialogues.first,
    );
    final settings = ref.watch(appSettingsProvider);

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            children: [
              for (final m in session.messages)
                _MessageView(
                  message: m,
                  counterpartAvatar: counterpart.characterAvatar,
                  counterpartName: counterpart.speakerNameJp,
                  showRomaji: settings.showRomaji,
                  showArabic: settings.showArabicTranslation,
                ),
              if (session.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                ),
              if (session.errorAr != null) _ErrorBanner(
                message: session.errorAr!,
                onRetry: _session.retry,
                onDismiss: _session.dismissError,
              ),
            ],
          ),
        ),
        _buildInputArea(context, session),
      ],
    );
  }

  Widget _buildInputArea(BuildContext context, TutorSessionState session) {
    if (session.completed) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () => widget.onDone(skipped: false),
            icon: const Icon(Icons.flag_rounded),
            label: const Text('أنهِ الدرس'),
          ),
        ),
      );
    }
    final busy = session.loading;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton.filled(
                  onPressed: busy ? null : _toggleRecording,
                  style: IconButton.styleFrom(
                    backgroundColor:
                        _recording ? AppColors.warning : AppColors.brand,
                    minimumSize: const Size(52, 52),
                  ),
                  icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                  tooltip: _recording ? 'إيقاف وإرسال' : 'تحدث',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: _text,
                      enabled: !busy && !_recording,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: InputDecoration(
                        hintText: _recording
                            ? '... جارٍ التسجيل'
                            : 'اكتب بالياباني أو بالروماجي',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(26)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: busy || _recording ? null : _sendText,
                  icon: const Icon(Icons.send_rounded),
                  tooltip: 'إرسال',
                ),
              ],
            ),
            if (session.learnerTurns > 0)
              TextButton(
                onPressed: () => widget.onDone(skipped: false),
                child: const Text('أنهِ الدرس الآن'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.message,
    required this.counterpartAvatar,
    required this.counterpartName,
    required this.showRomaji,
    required this.showArabic,
  });

  final TutorMessage message;
  final String counterpartAvatar;
  final String counterpartName;
  final bool showRomaji;
  final bool showArabic;

  @override
  Widget build(BuildContext context) {
    final isAi = message.sender == TutorSender.ai;
    final bubbleColor = isAi ? Colors.white : AppColors.brand.withValues(alpha: 0.12);

    final bubble = Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAE6F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          JpText(message.japanese, size: 19),
          if (isAi && showRomaji && (message.romaji ?? '').isNotEmpty)
            RomajiText(message.romaji!, size: 13),
          if (isAi && showArabic && (message.arabic ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(message.arabic!, style: const TextStyle(height: 1.5)),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:
                isAi ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              if (isAi) ...[
                CharacterAvatar(
                    path: counterpartAvatar, name: counterpartName, radius: 20),
                const SizedBox(width: 8),
              ],
              bubble,
            ],
          ),
          if (message.turn != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CharacterAvatar(
                    path: AppRules.senseiKenAvatar, name: 'ケン', radius: 18),
                const SizedBox(width: 8),
                Expanded(child: CorrectionBox(turn: message.turn!)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warningSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
                TextButton(onPressed: onDismiss, child: const Text('إغلاق')),
              ],
            ),
          ],
        ),
      );
}
