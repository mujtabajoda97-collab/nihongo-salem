import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/kana_course.dart';
import '../../providers/kana_course.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Map of the beginner course: stages with their lessons.
class KanaCourseScreen extends ConsumerWidget {
  const KanaCourseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courseAsync = ref.watch(kanaCourseProvider);
    final progress = ref.watch(kanaProgressProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('تعلّم الحروف اليابانية')),
      body: courseAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('تعذّر تحميل المنهج:\n$e', textAlign: TextAlign.center),
          ),
        ),
        data: (course) {
          final next = progress.nextLesson(course.lessons.length);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Summary(course: course, progress: progress),
              for (final stage in course.stages)
                _StageSection(
                  stage: stage,
                  lessons: course.inStage(stage.id),
                  progress: progress,
                  nextId: next,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.course, required this.progress});

  final KanaCourse course;
  final KanaProgress progress;

  @override
  Widget build(BuildContext context) {
    final total = course.lessons.length;
    final done = progress.completed.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('من الحروف إلى الجمل، خطوة بخطوة',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('٤٦ حرفاً أساسياً + العلامات والأصوات المركّبة، ثم كلمات وجمل خفيفة.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 10),
            ),
            const SizedBox(height: 6),
            Text('أنجزت $done من $total درساً'),
          ],
        ),
      ),
    );
  }
}

class _StageSection extends StatelessWidget {
  const _StageSection({
    required this.stage,
    required this.lessons,
    required this.progress,
    required this.nextId,
  });

  final KanaStage stage;
  final List<KanaLesson> lessons;
  final KanaProgress progress;
  final int? nextId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${stage.id}. ${stage.titleAr}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          Text(stage.descAr, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final l in lessons)
            _LessonTile(lesson: l, progress: progress, isNext: l.id == nextId),
        ],
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.lesson, required this.progress, required this.isNext});

  final KanaLesson lesson;
  final KanaProgress progress;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final done = progress.isCompleted(lesson.id);
    final unlocked = progress.isUnlocked(lesson.id);
    final stars = progress.starsFor(lesson.id);
    final theme = Theme.of(context);
    final icon = lesson.kind == KanaLessonKind.intro
        ? Icons.menu_book_rounded
        : lesson.kind == KanaLessonKind.letters
            ? Icons.draw_rounded
            : Icons.chrome_reader_mode_rounded;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isNext ? AppColors.brand : const Color(0xFFEAE6F0),
          width: isNext ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: () {
          if (!unlocked) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('أكمل الدرس السابق أولاً لفتح هذا الدرس')));
            return;
          }
          context.push('/kana/${lesson.id}');
        },
        leading: CircleAvatar(
          backgroundColor: done
              ? AppColors.successSoft
              : unlocked
                  ? AppColors.brand.withValues(alpha: 0.1)
                  : const Color(0xFFF0EEF3),
          child: done
              ? const Icon(Icons.check_rounded, color: AppColors.success)
              : unlocked
                  ? Icon(icon, color: AppColors.brand)
                  : const Icon(Icons.lock_rounded, color: AppColors.lockedGrey),
        ),
        title: lesson.kind == KanaLessonKind.letters
            ? JpText(lesson.titleAr, size: 20)
            : Text(lesson.titleAr, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(lesson.subtitleAr, style: theme.textTheme.bodySmall),
        trailing: done
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Icon(Icons.star_rounded,
                        size: 18, color: i < stars ? AppColors.gold : AppColors.lockedGrey),
                ],
              )
            : null,
      ),
    );
  }
}
