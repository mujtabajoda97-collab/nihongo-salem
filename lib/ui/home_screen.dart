import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants.dart';
import '../models/episode.dart';
import '../providers/kana_course.dart';
import '../providers/providers.dart';
import '../services/access_policy.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Home: greeting, progress, "continue" card and the map of the 40 episodes
/// split into the four seasons.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userStateProvider);
    final premium = ref.watch(premiumProvider);
    final remaining = ref.watch(callRemainingSecondsProvider);
    final episodesAsync = ref.watch(episodeListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/call'),
        icon: const Icon(Icons.call_rounded),
        label: const Text('مكالمة حرة'),
      ),
      body: SafeArea(
        child: episodesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('تعذّر تحميل الحلقات:\n$e', textAlign: TextAlign.center),
            ),
          ),
          data: (episodes) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              _Header(userName: user.displayName),
              const SizedBox(height: 16),
              _ProgressCard(
                done: user.completedEpisodes.length,
                streak: user.streakDays,
                stars: user.totalStars,
              ),
              const SizedBox(height: 16),
              _ContinueCard(episodes: episodes),
              const SizedBox(height: 12),
              const _KanaCard(),
              const SizedBox(height: 10),
              _CallQuotaLine(premium: premium, remainingSeconds: remaining),
              const SizedBox(height: 8),
              for (var season = 1; season <= 4; season++)
                _SeasonSection(
                  season: season,
                  episodes: episodes
                      .where((e) => e.season == season)
                      .toList(growable: false),
                ),
              if (!premium)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/paywall'),
                    icon: const Icon(Icons.workspace_premium_rounded,
                        color: AppColors.premium),
                    label: const Text('افتح كل الحلقات بالاشتراك'),
                  ),
                ),
              const SizedBox(height: 8),
              Center(
                child: Text('نيهونغو مع سالم',
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = userName.trim().isEmpty ? 'س' : String.fromCharCode(userName.trim().runes.first);
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppColors.brand, Color(0xFFFF7A59)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
          child: Text(initial,
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('أهلاً، $userName',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text('تعلّم الياباني خطوة بخطوة',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted)),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => showSettingsSheet(context),
          style: IconButton.styleFrom(backgroundColor: Colors.white),
          icon: const Icon(Icons.settings_rounded),
          tooltip: 'الإعدادات',
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.done,
    required this.streak,
    required this.stars,
  });

  final int done;
  final int streak;
  final int stars;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _StatTile(
              icon: Icons.menu_book_rounded,
              color: AppColors.brand,
              value: '$done/${AppRules.totalEpisodes}',
              label: 'حلقات',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.local_fire_department_rounded,
              color: AppColors.warning,
              value: '$streak',
              label: 'أيام متتالية',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.star_rounded,
              color: AppColors.gold,
              value: '$stars',
              label: 'نجمة',
            ),
          ),
        ],
      );
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: kSoftShadow,
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(value,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppColors.muted)),
          ],
        ),
      );
}

class _CallQuotaLine extends StatelessWidget {
  const _CallQuotaLine({required this.premium, required this.remainingSeconds});

  final bool premium;
  final int? remainingSeconds;

  @override
  Widget build(BuildContext context) {
    final String text;
    if (remainingSeconds == null) {
      text = 'المكالمات الصوتية: بلا حدود';
    } else if (remainingSeconds == 0) {
      text = 'انتهى وقت المكالمة المجاني اليوم، ويتجدد غداً';
    } else {
      final m = remainingSeconds! ~/ 60;
      final s = (remainingSeconds! % 60).toString().padLeft(2, '0');
      text = 'المكالمة المجانية اليوم: $m:$s متبقية';
    }
    return Row(
      children: [
        Icon(premium ? Icons.all_inclusive_rounded : Icons.timer_outlined,
            size: 18),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.episodes});

  final List<Episode> episodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userStateProvider);
    if (user.finishedAllEpisodes) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('أكملت الحلقات الأربعين! يمكنك مراجعة أي حلقة أو التحدث في المكالمة الحرة.'),
        ),
      );
    }
    final id = user.reachedEpisode;
    final episode = episodes.firstWhere((e) => e.id == id);
    final access = ref.watch(episodeAccessProvider(id));

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SafeAssetImage(episode.backgroundImage),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC1E1B2E)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.completedEpisodes.isEmpty
                        ? 'ابدأ رحلتك'
                        : 'تابع من حيث توقفت',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    'الحلقة $id: ${episode.titleAr}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(160, 44),
                    ),
                    onPressed: () => openEpisode(context, id, access),
                    child: Text(access.needsPaywall
                        ? 'اشترك للمتابعة'
                        : 'ابدأ الحلقة'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens an episode, or the paywall / an explanation when it is closed.
void openEpisode(BuildContext context, int id, EpisodeAccess access) =>
    openEpisodeWith(
        GoRouter.of(context), ScaffoldMessenger.of(context), id, access);

/// Same, for callers whose own context is about to be closed (bottom sheet).
void openEpisodeWith(
  GoRouter router,
  ScaffoldMessengerState messenger,
  int id,
  EpisodeAccess access,
) {
  switch (access.lock) {
    case EpisodeLock.none:
      router.push('/episode/$id');
    case EpisodeLock.requiresPremium:
      router.push('/paywall');
    case EpisodeLock.notYetReached:
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('أكمل الحلقة السابقة أولاً لتفتح هذه الحلقة')));
    case EpisodeLock.placementRequired:
      router.go('/onboarding');
  }
}

class _SeasonSection extends ConsumerWidget {
  const _SeasonSection({required this.season, required this.episodes});

  final int season;
  final List<Episode> episodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userStateProvider);
    final done = episodes.where((e) => user.isCompleted(e.id)).length;
    final title = AppRules.seasonTitlesAr[season - 1];
    final first = episodes.first.id;
    final last = episodes.last.id;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('الفصل $season: $title',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text('$done/${episodes.length}',
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          Text('الحلقات $first - $last', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: episodes.isEmpty ? 0 : done / episodes.length,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.78,
            children: [for (final e in episodes) _EpisodeNode(episode: e)],
          ),
        ],
      ),
    );
  }
}

class _EpisodeNode extends ConsumerWidget {
  const _EpisodeNode({required this.episode});

  final Episode episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userStateProvider);
    final access = ref.watch(episodeAccessProvider(episode.id));
    final done = user.isCompleted(episode.id);
    final isCurrent =
        access.isUnlocked && !done && episode.id == user.reachedEpisode;

    final Color fill;
    final Color border;
    final Widget center;
    if (done) {
      fill = AppColors.success;
      border = AppColors.success;
      center = const Icon(Icons.check_rounded, color: Colors.white, size: 26);
    } else if (!access.isUnlocked) {
      fill = const Color(0xFFEFEDF3);
      border = access.needsPaywall ? AppColors.premium : AppColors.lockedGrey;
      center = Icon(
        access.needsPaywall ? Icons.workspace_premium_rounded : Icons.lock_rounded,
        color: border,
        size: 22,
      );
    } else {
      fill = isCurrent ? AppColors.brand : Colors.white;
      border = AppColors.brand;
      center = Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          '${episode.id}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: isCurrent ? Colors.white : AppColors.brand,
          ),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showSheet(context, ref),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(color: border, width: 2),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: AppColors.brand.withValues(alpha: 0.45),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(child: center),
          ),
          const SizedBox(height: 4),
          if (done)
            StarsRow(count: user.starsFor(episode.id), size: 12)
          else
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text('${episode.id}',
                  style: Theme.of(context).textTheme.labelSmall),
            ),
        ],
      ),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _EpisodeSheet(episode: episode),
    );
  }
}

class _EpisodeSheet extends ConsumerWidget {
  const _EpisodeSheet({required this.episode});

  final Episode episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userStateProvider);
    final access = ref.watch(episodeAccessProvider(episode.id));
    final free = ref.watch(freeEpisodeIdsProvider).contains(episode.id);
    final done = user.isCompleted(episode.id);
    final theme = Theme.of(context);

    final String buttonText;
    if (access.isUnlocked) {
      buttonText = done ? 'راجع الحلقة' : 'ابدأ الحلقة';
    } else if (access.needsPaywall) {
      buttonText = 'اشترك لفتح الحلقة';
    } else {
      buttonText = 'أكمل الحلقة السابقة أولاً';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('الحلقة ${episode.id}',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: AppColors.brand)),
                const SizedBox(width: 8),
                if (free)
                  const Chip(
                    label: Text('مجانية'),
                    visualDensity: VisualDensity.compact,
                  ),
                const Spacer(),
                if (done) StarsRow(count: user.starsFor(episode.id)),
              ],
            ),
            Text(episode.titleAr,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            JpText(episode.titleJp, size: 18, weight: FontWeight.w500),
            const SizedBox(height: 8),
            Text(
              '${episode.dialogues.length} جملة - ${episode.vocabulary.length} مفردات - '
              '${episode.grammarPoints.length} قواعد',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                final router = GoRouter.of(context);
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(context).pop();
                openEpisodeWith(router, messenger, episode.id, access);
              },
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}


/// Optional review of all the letters in one place (the letters themselves are
/// taught inside the episodes).
class _KanaCard extends ConsumerWidget {
  const _KanaCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(kanaCourseProvider).valueOrNull;
    final progress = ref.watch(kanaProgressProvider);
    final total = course?.lessons.length ?? 0;
    final done = progress.completed.length;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => context.push('/kana'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: kSoftShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.premium.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('あ',
                  style: TextStyle(fontSize: 28, color: AppColors.premium)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('دورة الحروف الكاملة',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    total == 0
                        ? 'الهيراغانا من الصفر، ثم كلمات وجمل'
                        : '$done من $total درساً — راجع كل الحروف في مكان واحد',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded, color: AppColors.lockedGrey),
          ],
        ),
      ),
    );
  }
}
