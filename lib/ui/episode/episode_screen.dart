import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../models/episode.dart';
import '../../providers/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'completion_dialog.dart';
import 'station_cards.dart';
import 'station_quiz.dart';
import 'station_scene.dart';
import 'station_voice.dart';

const _stationLabels = ['المشهد', 'المفردات والقواعد', 'التمارين', 'المحادثة'];

/// The interactive lesson: four stations in order.
///   A scene  ->  B vocabulary & grammar cards  ->  C quizzes  ->  D voice role-play
class EpisodeScreen extends ConsumerWidget {
  const EpisodeScreen({super.key, required this.episodeId});

  final int episodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(episodeProvider(episodeId));
    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('تعذّر تحميل الحلقة:\n$e', textAlign: TextAlign.center),
          ),
        ),
      ),
      data: (episode) => _EpisodeBody(episode: episode),
    );
  }
}

class _EpisodeBody extends ConsumerStatefulWidget {
  const _EpisodeBody({required this.episode});

  final Episode episode;

  @override
  ConsumerState<_EpisodeBody> createState() => _EpisodeBodyState();
}

class _EpisodeBodyState extends ConsumerState<_EpisodeBody> {
  final _pages = PageController();
  int _station = 0;
  int _furthest = 0;
  int _quizCorrect = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goTo(int station) {
    if (station < 0 || station > _furthest) return;
    setState(() => _station = station);
    _pages.animateToPage(
      station,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _advance() {
    final next = _station + 1;
    if (next >= _stationLabels.length) return;
    setState(() {
      _station = next;
      if (next > _furthest) _furthest = next;
    });
    _pages.animateToPage(
      next,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final episode = widget.episode;
    final stars = (1 + _quizCorrect).clamp(1, 3).toInt();

    ref.read(userStateProvider.notifier).completeEpisode(episode.id, stars: stars);

    final nextId = episode.id + 1;
    final next = nextId <= AppRules.totalEpisodes
        ? ref.read(episodeAccessProvider(nextId))
        : null;

    final exit = await showLessonComplete(
      context,
      episodeId: episode.id,
      titleAr: episode.titleAr,
      stars: stars,
      quizCorrect: _quizCorrect,
      quizTotal: episode.quiz.length,
      vocabCount: episode.vocabulary.length,
      next: next,
    );
    if (!mounted) return;
    switch (exit) {
      case LessonExit.nextEpisode:
        context.pushReplacement('/episode/$nextId');
      case LessonExit.paywall:
        context.pushReplacement('/paywall');
      case LessonExit.backToMap:
        context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    return Scaffold(
      appBar: AppBar(
        title: Text('الحلقة ${episode.id}: ${episode.titleAr}',
            overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'خروج',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: Column(
        children: [
          _StationStepper(
            current: _station,
            furthest: _furthest,
            onTap: _goTo,
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                KeepAlivePage(
                  child: SceneStation(episode: episode, onDone: _advance),
                ),
                KeepAlivePage(
                  child: CardsStation(episode: episode, onDone: _advance),
                ),
                KeepAlivePage(
                  child: QuizStation(
                    episode: episode,
                    onFinished: (correct) {
                      _quizCorrect = correct;
                      _advance();
                    },
                  ),
                ),
                KeepAlivePage(
                  child: VoiceStation(
                    episode: episode,
                    onDone: ({required bool skipped}) => _finish(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StationStepper extends StatelessWidget {
  const _StationStepper({
    required this.current,
    required this.furthest,
    required this.onTap,
  });

  final int current;
  final int furthest;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          for (var i = 0; i < _stationLabels.length; i++) ...[
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: i <= furthest ? () => onTap(i) : null,
                child: Column(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == current
                            ? AppColors.brand
                            : i < current || i <= furthest
                                ? AppColors.success
                                : const Color(0xFFE2DEEA),
                      ),
                      child: Center(
                        child: i < current
                            ? const Icon(Icons.check_rounded,
                                size: 18, color: Colors.white)
                            : Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: i <= furthest
                                      ? Colors.white
                                      : AppColors.lockedGrey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _stationLabels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight:
                            i == current ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
