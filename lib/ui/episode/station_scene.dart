import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/episode.dart';
import '../../providers/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Station A: the visual-novel scene. One line at a time over the episode
/// background, with the speaker's picture, text and audio. Missing pictures
/// or audio files fall back quietly.
class SceneStation extends ConsumerStatefulWidget {
  const SceneStation({super.key, required this.episode, required this.onDone});

  final Episode episode;
  final VoidCallback onDone;

  @override
  ConsumerState<SceneStation> createState() => _SceneStationState();
}

class _SceneStationState extends ConsumerState<SceneStation> {
  int _index = 0;
  bool _autoPlay = true;

  List<Dialogue> get _lines => widget.episode.dialogues;
  Dialogue get _line => _lines[_index];

  void _playCurrent() {
    final slow = ref.read(appSettingsProvider).slowAudio;
    unawaited(ref.read(audioServiceProvider).playAsset(_line.audioFile, slow: slow));
  }

  void _move(int delta) {
    final next = _index + delta;
    if (next < 0) return;
    if (next >= _lines.length) {
      widget.onDone();
      return;
    }
    setState(() => _index = next);
    if (_autoPlay) _playCurrent();
  }

  void _showScript() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView.separated(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: _lines.length,
          separatorBuilder: (_, __) => const Divider(height: 24),
          itemBuilder: (_, i) {
            final d = _lines[i];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CharacterAvatar(
                    path: d.characterAvatar, name: d.speakerNameJp, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.speakerNameAr,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      JpText(d.japanese, size: 18),
                      Text(d.arabic),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final line = _line;
    final isLast = _index == _lines.length - 1;
    final theme = Theme.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        SafeAssetImage(widget.episode.backgroundImage),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x33000000), Color(0x99000000)],
            ),
          ),
        ),
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text('${_index + 1} / ${_lines.length}',
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    onPressed: () => setState(() => _autoPlay = !_autoPlay),
                    icon: Icon(_autoPlay
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded),
                    tooltip: 'تشغيل الصوت تلقائياً',
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    onPressed: _showScript,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    icon: const Icon(Icons.article_outlined),
                    label: const Text('النص كاملاً'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    key: ValueKey(line.speakerNameJp),
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: CharacterAvatar(
                      path: line.characterAvatar,
                      name: line.speakerNameJp,
                      radius: 62,
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              margin: EdgeInsets.fromLTRB(
                  12, 0, 12, 12 + MediaQuery.of(context).padding.bottom),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: line.isLearnerLine
                    ? const Color(0xFFFFF1F3)
                    : Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.42,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(line.speakerNameAr,
                            style: theme.textTheme.titleSmall?.copyWith(
                                color: AppColors.brand,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        JpText(line.speakerNameJp,
                            size: 13, weight: FontWeight.w500),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            JpText(line.japanese, size: 24),
                            if (settings.showRomaji) RomajiText(line.romaji),
                            if (settings.showArabicTranslation) ...[
                              const SizedBox(height: 6),
                              Text(line.arabic,
                                  style: const TextStyle(fontSize: 16, height: 1.6)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton.outlined(
                          onPressed: _index == 0 ? null : () => _move(-1),
                          icon: const Icon(Icons.arrow_back_rounded),
                          tooltip: 'السابق',
                        ),
                        const SizedBox(width: 8),
                        AudioButton(
                            key: ValueKey('line-$_index'),
                            assetPath: line.audioFile),
                        const SizedBox(width: 8),
                        AudioButton(
                            key: ValueKey('slow-$_index'),
                            assetPath: line.audioFile,
                            slow: true,
                            label: '0.7x'),
                        const Spacer(),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 48)),
                          onPressed: () => _move(1),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(isLast ? 'المفردات والقواعد' : 'التالي'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
