import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/episode.dart';
import '../../models/episode_warmup.dart';
import '../../models/kana_course.dart';
import '../../providers/kana_course.dart';
import '../kana/kana_lesson_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Station C: the episode's quiz questions (multiple choice, word order),
/// one at a time with instant feedback, then a score summary.
class QuizStation extends ConsumerStatefulWidget {
  const QuizStation({
    super.key,
    required this.episode,
    required this.onFinished,
    this.letters = const [],
  });

  final Episode episode;

  /// New letters of this episode (used to build the gentle warm-up).
  final List<KanaChar> letters;

  /// Called with the number of correct answers when the learner moves on.
  final void Function(int correct) onFinished;

  @override
  ConsumerState<QuizStation> createState() => _QuizStationState();
}

class _QuizStationState extends ConsumerState<QuizStation> {
  /// Level 1-2 warm-up (letters and single words) comes before the sentence questions.
  List<KanaQuestion>? _warmup;
  bool _warmupDone = false;
  int _index = 0;
  int _correct = 0;
  bool _answered = false;
  bool _summary = false;

  /// The first episodes keep the sentence questions short: a beginner has just
  /// met the letters, so only a few easy ones follow the warm-up.
  List<QuizItem> get _items => widget.episode.id <= 5
      ? widget.episode.quiz.take(3).toList(growable: false)
      : widget.episode.quiz;

  void _onAnswered(bool correct) {
    setState(() {
      _answered = true;
      if (correct) _correct++;
    });
  }

  void _next() {
    if (_index + 1 >= _items.length) {
      setState(() => _summary = true);
      return;
    }
    setState(() {
      _index++;
      _answered = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _warmupDone = false;
  }

  List<KanaQuestion> _buildWarmup() {
    final course = ref.read(kanaCourseProvider).valueOrNull;
    final all = course == null
        ? widget.letters
        : [for (final l in course.lessons) ...l.chars];
    return buildEpisodeWarmup(
      episode: widget.episode,
      letters: widget.letters,
      allLetters: all,
      rnd: Random(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_warmupDone) {
      final warm = _warmup ??= _buildWarmup();
      if (warm.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _warmupDone = true);
        });
        return const SizedBox.shrink();
      }
      return Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text('إحماء خفيف: استمع واختر، حرف حرفاً وكلمة كلمة 🌱'),
          ),
          Expanded(
            child: KanaQuizView(
              questions: warm,
              onFinished: (_) => setState(() => _warmupDone = true),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      // Defensive: an episode without questions skips straight on.
      return Center(
        child: FilledButton(
          onPressed: () => widget.onFinished(0),
          child: const Text('متابعة'),
        ),
      );
    }
    if (_summary) return _buildSummary(context);

    final q = _items[_index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('السؤال ${_index + 1} من ${_items.length}',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              const Icon(Icons.check_circle_outline_rounded,
                  size: 18, color: AppColors.success),
              const SizedBox(width: 4),
              Text('$_correct'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              // A new key per question => fresh state (shuffle, selection).
              child: switch (q) {
                final MultipleChoiceQuiz mc => _McQuestion(
                    key: ValueKey('mc-${mc.id}-$_index'),
                    quiz: mc,
                    onAnswered: _onAnswered,
                  ),
                final WordOrderQuiz wo => _WordOrderQuestion(
                    key: ValueKey('wo-${wo.id}-$_index'),
                    quiz: wo,
                    onAnswered: _onAnswered,
                  ),
              },
            ),
          ),
          if (_answered) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _next,
              child: Text(_index + 1 >= _items.length ? 'عرض النتيجة' : 'السؤال التالي'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final total = _items.length;
    final perfect = _correct == total;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            perfect ? Icons.emoji_events_rounded : Icons.thumb_up_alt_rounded,
            size: 72,
            color: perfect ? AppColors.gold : AppColors.brand,
          ),
          const SizedBox(height: 16),
          Text(
            perfect ? 'ممتاز! كل إجاباتك صحيحة' : 'أحسنت المحاولة',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('الإجابات الصحيحة: $_correct من $total',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => widget.onFinished(_correct),
            child: const Text('التالي: المحادثة'),
          ),
        ],
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.correct, required this.explanation});

  final bool correct;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    final color = correct ? AppColors.success : AppColors.warning;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  color: color),
              const SizedBox(width: 8),
              Text(correct ? 'إجابة صحيحة' : 'ليست صحيحة',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          Text(explanation, style: const TextStyle(height: 1.7)),
        ],
      ),
    );
  }
}

class _McQuestion extends StatefulWidget {
  const _McQuestion({super.key, required this.quiz, required this.onAnswered});

  final MultipleChoiceQuiz quiz;
  final void Function(bool correct) onAnswered;

  @override
  State<_McQuestion> createState() => _McQuestionState();
}

class _McQuestionState extends State<_McQuestion> {
  late final List<int> _order = [
    for (var i = 0; i < widget.quiz.options.length; i++) i,
  ]..shuffle(Random());
  int? _selected;

  void _choose(int optionIndex) {
    if (_selected != null) return;
    setState(() => _selected = optionIndex);
    widget.onAnswered(widget.quiz.isCorrect(optionIndex));
  }

  @override
  Widget build(BuildContext context) {
    final quiz = widget.quiz;
    final answered = _selected != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(quiz.questionAr,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold, height: 1.6)),
        const SizedBox(height: 16),
        for (final i in _order)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AnswerTile(
              text: quiz.options[i],
              state: !answered
                  ? _TileState.idle
                  : i == quiz.correctIndex
                      ? _TileState.right
                      : i == _selected
                          ? _TileState.wrong
                          : _TileState.dim,
              onTap: () => _choose(i),
            ),
          ),
        if (answered)
          _Feedback(
            correct: quiz.isCorrect(_selected!),
            explanation: quiz.explanationAr,
          ),
      ],
    );
  }
}

enum _TileState { idle, right, wrong, dim }

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String text;
  final _TileState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData? icon;
    switch (state) {
      case _TileState.right:
        color = AppColors.success;
        icon = Icons.check_circle_rounded;
      case _TileState.wrong:
        color = AppColors.warning;
        icon = Icons.cancel_rounded;
      case _TileState.dim:
        color = const Color(0xFFE2DEEA);
        icon = null;
      case _TileState.idle:
        color = const Color(0xFFD9D4E3);
        icon = null;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: state == _TileState.idle ? onTap : null,
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: (state == _TileState.right || state == _TileState.wrong)
              ? color.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: color,
              width: (state == _TileState.right || state == _TileState.wrong) ? 2 : 1),
        ),
        child: Row(
          children: [
            Expanded(child: MixedText(text)),
            if (icon != null) Icon(icon, color: color),
          ],
        ),
      ),
    );
  }
}

class _WordOrderQuestion extends StatefulWidget {
  const _WordOrderQuestion({
    super.key,
    required this.quiz,
    required this.onAnswered,
  });

  final WordOrderQuiz quiz;
  final void Function(bool correct) onAnswered;

  @override
  State<_WordOrderQuestion> createState() => _WordOrderQuestionState();
}

class _WordOrderQuestionState extends State<_WordOrderQuestion> {
  /// Tile bank: indexes into quiz.words (indexes, so repeated words work).
  late final List<int> _bank = [
    for (var i = 0; i < widget.quiz.words.length; i++) i,
  ]..shuffle(Random());
  final List<int> _chosen = [];
  bool? _result;

  List<String> get _answer => [for (final i in _chosen) widget.quiz.words[i]];

  void _check() {
    final ok = widget.quiz.isCorrect(_answer);
    setState(() => _result = ok);
    widget.onAnswered(ok);
  }

  Widget _tile(int wordIndex, VoidCallback? onTap, {Color? color}) {
    return Material(
      color: color ?? Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color == null ? const Color(0xFFD9D4E3) : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: JpText(widget.quiz.words[wordIndex], size: 22),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quiz = widget.quiz;
    final checked = _result != null;
    final tileColor = !checked
        ? null
        : (_result! ? AppColors.successSoft : AppColors.warningSoft);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(quiz.questionAr,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold, height: 1.6)),
        const SizedBox(height: 16),
        // Answer line (Japanese reads left to right).
        Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD9D4E3)),
            ),
            child: _chosen.isEmpty
                ? Center(
                    child: Text('اضغط على الكلمات لترتيب الجملة',
                        textDirection: TextDirection.rtl,
                        style: Theme.of(context).textTheme.bodySmall),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final i in _chosen)
                        _tile(
                          i,
                          checked ? null : () => setState(() => _chosen.remove(i)),
                          color: tileColor,
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        // Word bank.
        Directionality(
          textDirection: TextDirection.ltr,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final i in _bank)
                Opacity(
                  opacity: _chosen.contains(i) ? 0.25 : 1,
                  child: _tile(
                    i,
                    (checked || _chosen.contains(i))
                        ? null
                        : () => setState(() => _chosen.add(i)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!checked)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _chosen.isEmpty ? null : () => setState(_chosen.clear),
                  child: const Text('مسح'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _chosen.length == quiz.words.length ? _check : null,
                  child: const Text('تحقق'),
                ),
              ),
            ],
          )
        else ...[
          if (!_result!)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الترتيب الصحيح:'),
                const SizedBox(height: 4),
                JpText(quiz.correctOrder.join(' '), size: 22),
              ],
            ),
          _Feedback(correct: _result!, explanation: quiz.explanationAr),
        ],
      ],
    );
  }
}
