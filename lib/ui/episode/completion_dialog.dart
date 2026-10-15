import 'package:flutter/material.dart';

import '../../services/access_policy.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum LessonExit { backToMap, nextEpisode, paywall }

/// Shown when a lesson is finished: stars, quiz score and where to go next.
Future<LessonExit> showLessonComplete(
  BuildContext context, {
  required int episodeId,
  required String titleAr,
  required int stars,
  required int quizCorrect,
  required int quizTotal,
  required int vocabCount,
  required EpisodeAccess? next,
}) async {
  final result = await showDialog<LessonExit>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration_rounded, size: 64, color: AppColors.gold),
            const SizedBox(height: 8),
            Text('أكملت الحلقة $episodeId',
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(titleAr, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            StarsRow(count: stars, size: 36),
            const SizedBox(height: 12),
            Text('التمارين: $quizCorrect من $quizTotal'),
            Text('مفردات جديدة: $vocabCount'),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          if (next != null && next.isUnlocked)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, LessonExit.nextEpisode),
              child: const Text('الحلقة التالية'),
            ),
          if (next != null && next.needsPaywall)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, LessonExit.paywall),
              child: const Text('اشترك لمتابعة القصة'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, LessonExit.backToMap),
            child: const Text('العودة إلى الخريطة'),
          ),
        ],
      ),
    ),
  );
  return result ?? LessonExit.backToMap;
}
