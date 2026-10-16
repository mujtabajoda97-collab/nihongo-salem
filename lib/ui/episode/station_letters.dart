import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/kana_course.dart';
import '../../providers/providers.dart';
import '../kana/kana_lesson_screen.dart';

/// Station 0: the 1-2 new letters of this episode, taken from its own words.
/// For each letter: how it sounds, a word of this episode that uses it, and a
/// tracing pad for how it is written.
class LettersStation extends ConsumerStatefulWidget {
  const LettersStation({super.key, required this.letters, required this.onDone});

  final List<KanaChar> letters;
  final VoidCallback onDone;

  @override
  ConsumerState<LettersStation> createState() => _LettersStationState();
}

class _LettersStationState extends ConsumerState<LettersStation> {
  int _step = 0; // 3 steps per letter: sound, word, writing

  int get _total => widget.letters.length * 3;

  void _play(String path) {
    final slow = ref.read(appSettingsProvider).slowAudio;
    ref.read(audioServiceProvider).playAsset(path, slow: slow);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _play(widget.letters.first.audio);
    });
  }

  void _next() {
    if (_step + 1 >= _total) {
      widget.onDone();
      return;
    }
    setState(() => _step++);
    final c = widget.letters[_step ~/ 3];
    switch (_step % 3) {
      case 0:
        _play(c.audio);
      case 1:
        _play(c.word.audio);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.letters[_step ~/ 3];
    final Widget body = switch (_step % 3) {
      0 => CharIntroStep(char: c),
      1 => CharWordStep(char: c),
      _ => TraceStep(char: c),
    };
    final last = _step + 1 >= _total;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(
            'حروف هذه الحلقة (${_step ~/ 3 + 1} من ${widget.letters.length})',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Expanded(child: KeyedSubtree(key: ValueKey(_step), child: body)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton(
            onPressed: _next,
            child: Text(last ? 'ابدأ المشهد' : 'التالي'),
          ),
        ),
      ],
    );
  }
}
