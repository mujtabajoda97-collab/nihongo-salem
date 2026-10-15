import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants.dart';
import '../models/placement_test.dart';
import '../providers/providers.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Score, level label, per-skill review and the two ways to start.
class PlacementOutcomeScreen extends ConsumerWidget {
  const PlacementOutcomeScreen({super.key});

  void _finish(
    BuildContext context,
    WidgetRef ref,
    PlacementResult result, {
    required bool fromBeginning,
  }) {
    ref
        .read(userStateProvider.notifier)
        .applyPlacement(result, startFromBeginning: fromBeginning);
    context.go('/');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(placementResultProvider);
    final testAsync = ref.watch(placementTestProvider);
    final user = ref.watch(userStateProvider);

    final test = testAsync.valueOrNull;
    if (result == null || test == null) {
      if (result == null && !testAsync.isLoading) {
        // Opened without a finished test (e.g. after a restart): go back.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => context.go('/placement'));
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final screen = test.resultScreen;
    final theme = Theme.of(context);
    final freeStart = user.freeWindowStart ?? result.startEpisode;
    final missedIds = {for (final q in result.missed) q.id};

    // Per-skill totals, in the order the skills first appear.
    final skills = <String, List<PlacementQuestion>>{};
    for (final q in test.questions) {
      skills.putIfAbsent(q.skillAr, () => []).add(q);
    }

    return Scaffold(
      appBar: AppBar(title: Text(screen.titleAr), automaticallyImplyLeading: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.brand, width: 8),
                ),
                child: Center(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '${result.score} / ${result.maxScore}',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              screen.scoreText(result.score, result.maxScore),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            if (result.rule != null)
              Center(
                child: Chip(
                  label: Text(result.rule!.labelAr),
                  backgroundColor: AppColors.brand.withValues(alpha: 0.12),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              result.rule?.messageAr ??
                  'سنبدأ بك من الحلقة الأولى لنبني الأساس خطوة بخطوة.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.premium.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_open_rounded, color: AppColors.premium),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'الحلقتان المجانيتان: $freeStart و${freeStart + AppRules.freeEpisodeCount - 1}. '
                      'تُحسبان من نقطة البدء التي تختارها الآن، وبقية الحلقات بالاشتراك الشهري.',
                      style: const TextStyle(height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
            if (screen.skillsBreakdown) ...[
              const SizedBox(height: 24),
              Text('مهاراتك', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(screen.skillsBreakdownNoteAr,
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              for (final entry in skills.entries)
                _SkillRow(
                  skillAr: entry.key,
                  total: entry.value.length,
                  correct:
                      entry.value.where((q) => !missedIds.contains(q.id)).length,
                  reviewEpisode: entry.value
                      .where((q) => missedIds.contains(q.id))
                      .map((q) => q.relatedEpisode)
                      .fold<int?>(null, (a, b) => a == null || b < a ? b : a),
                ),
            ],
            if (test.settings.showReviewAtEnd && result.missed.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('مراجعة الأسئلة التي أخطأت فيها أو تخطيتها',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final q in result.missed)
                Card(
                  child: ExpansionTile(
                    shape: const Border(),
                    title: Text(q.questionAr),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (q.promptJp.isNotEmpty) JpText(q.promptJp, size: 20),
                      const SizedBox(height: 6),
                      Text('الإجابة الصحيحة: ${q.options[q.correctIndex]}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(q.explanationAr, style: const TextStyle(height: 1.6)),
                      const SizedBox(height: 6),
                      Text('تُشرح في الحلقة ${q.relatedEpisode}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () =>
                  _finish(context, ref, result, fromBeginning: false),
              child: Text(screen.ctaText(result.startEpisode)),
            ),
            if (result.startEpisode != 1) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () =>
                    _finish(context, ref, result, fromBeginning: true),
                child: Text(screen.secondaryCtaAr),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({
    required this.skillAr,
    required this.total,
    required this.correct,
    required this.reviewEpisode,
  });

  final String skillAr;
  final int total;
  final int correct;
  final int? reviewEpisode;

  @override
  Widget build(BuildContext context) {
    final ok = correct == total;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
        color: ok ? AppColors.success : AppColors.warning,
      ),
      title: Text(skillAr),
      subtitle: ok || reviewEpisode == null
          ? null
          : Text('راجعها في الحلقة $reviewEpisode'),
      trailing: Directionality(
        textDirection: TextDirection.ltr,
        child: Text('$correct/$total',
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
