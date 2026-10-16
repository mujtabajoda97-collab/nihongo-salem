import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/kana_course.dart';
import '../../providers/kana_course.dart';
import '../../providers/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'trace_pad.dart';

/// One lesson of the beginner course.
///
/// Letters lesson: for every letter -> sound, key word, writing practice; then
/// a short quiz. Review / words / sentences: study cards then a quiz.
class KanaLessonScreen extends ConsumerWidget {
  const KanaLessonScreen({super.key, required this.lessonId});

  final int lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courseAsync = ref.watch(kanaCourseProvider);
    return courseAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('تعذّر تحميل الدرس:\n$e', textAlign: TextAlign.center)),
      ),
      data: (course) {
        if (lessonId < 1 || lessonId > course.lessons.length) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('هذا الدرس غير موجود')));
        }
        return _LessonFlow(course: course, lesson: course.lessonById(lessonId));
      },
    );
  }
}

enum _StepKind { note, page, charIntro, charWord, charTrace, item, quiz, done }

class _Step {
  const _Step(this.kind, {this.text, this.page, this.char, this.item});

  final _StepKind kind;
  final String? text;
  final KanaPage? page;
  final KanaChar? char;
  final KanaWord? item;

  String? get audio => char != null && kind == _StepKind.charIntro
      ? char!.audio
      : kind == _StepKind.charWord
          ? char!.word.audio
          : kind == _StepKind.item
              ? item!.audio
              : null;
}

List<_Step> _stepsFor(KanaLesson lesson) {
  final steps = <_Step>[];
  if (lesson.noteAr.isNotEmpty) steps.add(_Step(_StepKind.note, text: lesson.noteAr));
  for (final p in lesson.pages) {
    steps.add(_Step(_StepKind.page, page: p));
  }
  for (final c in lesson.chars) {
    steps
      ..add(_Step(_StepKind.charIntro, char: c))
      ..add(_Step(_StepKind.charWord, char: c))
      ..add(_Step(_StepKind.charTrace, char: c));
  }
  for (final w in lesson.items) {
    steps.add(_Step(_StepKind.item, item: w));
  }
  if (lesson.kind != KanaLessonKind.intro) steps.add(const _Step(_StepKind.quiz));
  steps.add(const _Step(_StepKind.done));
  return steps;
}

class _LessonFlow extends ConsumerStatefulWidget {
  const _LessonFlow({required this.course, required this.lesson});

  final KanaCourse course;
  final KanaLesson lesson;

  @override
  ConsumerState<_LessonFlow> createState() => _LessonFlowState();
}

class _LessonFlowState extends ConsumerState<_LessonFlow> {
  late final List<_Step> _steps = _stepsFor(widget.lesson);
  late final List<KanaQuestion> _questions =
      buildKanaQuiz(widget.lesson, widget.course, Random());
  int _index = 0;
  int _mistakes = 0;
  bool _saved = false;

  _Step get _step => _steps[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoPlay());
  }

  void _autoPlay() {
    final a = _step.audio;
    if (a == null || !mounted) return;
    final slow = ref.read(appSettingsProvider).slowAudio;
    ref.read(audioServiceProvider).playAsset(a, slow: slow);
  }

  void _next() {
    if (_index >= _steps.length - 1) return;
    setState(() => _index++);
    if (_step.kind == _StepKind.done) _save();
    _autoPlay();
  }

  void _save() {
    if (_saved) return;
    _saved = true;
    ref
        .read(kanaProgressProvider.notifier)
        .complete(widget.lesson.id, stars: starsForMistakes(_mistakes));
  }

  void _quizFinished(int mistakes) {
    _mistakes = mistakes;
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    final progressValue = (_index + 1) / _steps.length;
    final isQuiz = _step.kind == _StepKind.quiz;
    final isDone = _step.kind == _StepKind.done;
    return Scaffold(
      appBar: AppBar(
        title: Text(lesson.kind == KanaLessonKind.letters ? 'الدرس ${lesson.id}' : lesson.titleAr),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(value: progressValue, minHeight: 6),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(_index),
                  child: switch (_step.kind) {
                    _StepKind.note => _NoteStep(text: _step.text!),
                    _StepKind.page => _PageStep(page: _step.page!),
                    _StepKind.charIntro => _CharIntroStep(char: _step.char!),
                    _StepKind.charWord => _CharWordStep(char: _step.char!),
                    _StepKind.charTrace => _TraceStep(char: _step.char!),
                    _StepKind.item => _ItemStep(item: _step.item!),
                    _StepKind.quiz => _QuizStep(questions: _questions, onFinished: _quizFinished),
                    _StepKind.done => _DoneStep(
                        lesson: lesson,
                        course: widget.course,
                        stars: starsForMistakes(_mistakes),
                      ),
                  },
                ),
              ),
            ),
            if (!isQuiz && !isDone)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton(onPressed: _next, child: const Text('التالي')),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step views
// ---------------------------------------------------------------------------

class _NoteStep extends StatelessWidget {
  const _NoteStep({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Card(
            color: AppColors.warningSoft,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lightbulb_rounded, size: 42, color: AppColors.warning),
                  const SizedBox(height: 12),
                  Text('قبل أن نبدأ',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(text,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.8)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _PageStep extends StatelessWidget {
  const _PageStep({required this.page});

  final KanaPage page;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 12),
          Center(child: JpText(page.glyph, size: 56, align: TextAlign.center)),
          const SizedBox(height: 20),
          Text(page.titleAr,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Text(page.bodyAr,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.9)),
        ],
      );
}

class _CharIntroStep extends StatelessWidget {
  const _CharIntroStep({required this.char});

  final KanaChar char;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                JpText(char.char, size: char.char.runes.length > 1 ? 96 : 130, align: TextAlign.center, color: AppColors.brand),
                const SizedBox(height: 4),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(char.romaji,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                Text('يُنطق: ${char.soundAr}', style: theme.textTheme.titleMedium),
                const SizedBox(height: 14),
                AudioButton(assetPath: char.audio, label: 'استمع', size: 48),
              ],
            ),
          ),
        ),
        if (char.noteAr.isNotEmpty) ...[
          const SizedBox(height: 10),
          Card(
            color: AppColors.warningSoft,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.hearing_rounded, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(child: Text(char.noteAr)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.draw_rounded, color: AppColors.premium),
                const SizedBox(width: 10),
                Expanded(child: Text('${char.strokes} ضربات — ${char.tipAr}')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CharWordStep extends StatelessWidget {
  const _CharWordStep({required this.char});

  final KanaChar char;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = char.word;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('كلمة تحمل الحرف', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Column(
              children: [
                Text(w.emoji, style: const TextStyle(fontSize: 84)),
                const SizedBox(height: 10),
                _HighlightedWord(word: w.jp, target: char.char),
                const SizedBox(height: 4),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(w.romaji,
                      style: theme.textTheme.titleMedium?.copyWith(fontStyle: FontStyle.italic)),
                ),
                const SizedBox(height: 8),
                Text(w.ar, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                AudioButton(assetPath: w.audio, label: 'استمع للكلمة', size: 48),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HighlightedWord extends StatelessWidget {
  const _HighlightedWord({required this.word, required this.target});

  final String word;
  final String target;

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.notoSansJp(fontSize: 44, fontWeight: FontWeight.w700, color: AppColors.ink);
    final spans = <TextSpan>[];
    var i = 0;
    while (i < word.length) {
      if (target.isNotEmpty && word.startsWith(target, i)) {
        spans.add(TextSpan(text: target, style: base.copyWith(color: AppColors.brand)));
        i += target.length;
      } else {
        spans.add(TextSpan(text: word[i], style: base));
        i++;
      }
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text.rich(TextSpan(children: spans), textAlign: TextAlign.center),
    );
  }
}

class _TraceStep extends StatelessWidget {
  const _TraceStep({required this.char});

  final KanaChar char;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('تدرّب على الكتابة',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('تتبّع الشكل الباهت بإصبعك. ${char.tipAr}',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          TracePad(glyph: char.char, strokes: char.strokes),
        ],
      );
}

class _ItemStep extends StatelessWidget {
  const _ItemStep({required this.item});

  final KanaWord item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            child: Column(
              children: [
                Text(item.emoji, style: const TextStyle(fontSize: 76)),
                const SizedBox(height: 10),
                JpText(item.jp, size: item.jp.length > 8 ? 30 : 42, align: TextAlign.center),
                const SizedBox(height: 4),
                RomajiText(item.romaji, size: 16, align: TextAlign.center),
                const SizedBox(height: 8),
                Text(item.ar,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                AudioButton(assetPath: item.audio, label: 'استمع', size: 48),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Quiz
// ---------------------------------------------------------------------------

class _QuizStep extends ConsumerStatefulWidget {
  const _QuizStep({required this.questions, required this.onFinished});

  final List<KanaQuestion> questions;
  final void Function(int mistakes) onFinished;

  @override
  ConsumerState<_QuizStep> createState() => _QuizStepState();
}

class _QuizStepState extends ConsumerState<_QuizStep> {
  int _q = 0;
  int? _picked;
  int _mistakes = 0;

  KanaQuestion get _question => widget.questions[_q];

  @override
  void initState() {
    super.initState();
    if (widget.questions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onFinished(0));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  void _play() {
    final a = _question.audio;
    if (a == null || !mounted) return;
    ref.read(audioServiceProvider).playAsset(a, slow: ref.read(appSettingsProvider).slowAudio);
  }

  void _pick(int i) {
    if (_picked != null) return;
    setState(() {
      _picked = i;
      if (i != _question.answer) _mistakes++;
    });
  }

  void _advance() {
    if (_q + 1 >= widget.questions.length) {
      widget.onFinished(_mistakes);
      return;
    }
    setState(() {
      _q++;
      _picked = null;
    });
    _play();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) return const SizedBox.shrink();
    final q = _question;
    final theme = Theme.of(context);
    final answered = _picked != null;
    final correct = _picked == q.answer;
    final promptIsJapanese =
        q.kind == KanaQuestionKind.charPickSound || q.kind == KanaQuestionKind.wordPickMeaning;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            children: [
              Text('سؤال ${_q + 1} من ${widget.questions.length}',
                  textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              if (promptIsJapanese) ...[
                Center(child: JpText(q.prompt, size: q.prompt.length > 1 ? 56 : 96, color: AppColors.brand)),
                if (q.hint != null)
                  Text(q.hint!, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
              ] else
                Text(q.prompt,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              if (q.audio != null) ...[
                const SizedBox(height: 10),
                Center(child: AudioButton(assetPath: q.audio!, label: 'استمع', size: 46)),
              ],
              const SizedBox(height: 16),
              for (var i = 0; i < q.options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _OptionButton(
                    text: q.options[i],
                    japanese: q.japaneseOptions,
                    state: !answered
                        ? _OptState.idle
                        : i == q.answer
                            ? _OptState.right
                            : i == _picked
                                ? _OptState.wrong
                                : _OptState.dim,
                    onTap: () => _pick(i),
                  ),
                ),
              if (answered)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    correct ? 'أحسنت! ✅' : 'الإجابة الصحيحة: ${q.correct}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: correct ? AppColors.success : AppColors.brand,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton(
            onPressed: answered ? _advance : null,
            child: Text(_q + 1 >= widget.questions.length ? 'إنهاء الاختبار' : 'التالي'),
          ),
        ),
      ],
    );
  }
}

enum _OptState { idle, right, wrong, dim }

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.text,
    required this.japanese,
    required this.state,
    required this.onTap,
  });

  final String text;
  final bool japanese;
  final _OptState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color border) = switch (state) {
      _OptState.right => (AppColors.successSoft, AppColors.success),
      _OptState.wrong => (const Color(0xFFFFE3E6), AppColors.brand),
      _OptState.dim => (const Color(0xFFF6F4F8), const Color(0xFFEAE6F0)),
      _OptState.idle => (Colors.white, const Color(0xFFD9D3E3)),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 2),
        ),
        child: japanese
            ? JpText(text, size: 34, align: TextAlign.center)
            : Text(text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Completion
// ---------------------------------------------------------------------------

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.lesson, required this.course, required this.stars});

  final KanaLesson lesson;
  final KanaCourse course;
  final int stars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNext = lesson.id < course.lessons.length;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 72)),
          const SizedBox(height: 8),
          Text('أنجزت الدرس!',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Icon(Icons.star_rounded,
                    size: 44, color: i < stars ? AppColors.gold : AppColors.lockedGrey),
            ],
          ),
          const SizedBox(height: 28),
          if (hasNext)
            FilledButton(
              onPressed: () => context.pushReplacement('/kana/${lesson.id + 1}'),
              child: const Text('الدرس التالي'),
            ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => context.pop(),
            child: const Text('العودة إلى الخريطة'),
          ),
        ],
      ),
    );
  }
}
