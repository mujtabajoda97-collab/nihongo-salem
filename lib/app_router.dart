import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'services/access_policy.dart';
import 'providers/providers.dart';
import 'ui/call/live_call_screen.dart';
import 'ui/call/persona_selector_screen.dart';
import 'ui/episode/episode_screen.dart';
import 'ui/home_screen.dart';
import 'ui/kana/kana_course_screen.dart';
import 'ui/kana/kana_lesson_screen.dart';
import 'ui/onboarding_screen.dart';
import 'ui/paywall_screen.dart';
import 'ui/placement_result_screen.dart';
import 'ui/placement_screen.dart';

/// App navigation.
///
///   /onboarding         intro + name        (only before the placement step)
///   /placement          10-question test
///   /placement/result   score + choose where to start
///   /                   home / episode map
///   /kana, /kana/:id    the beginner letters course (hiragana -> words -> sentences)
///   /episode/:id        the 4-station lesson (guarded: locked => home/paywall)
///   /call               pick the persona / dialect
///   /call/live          the live voice call (guarded: locked persona or no minutes => /call)
///   /paywall            subscription
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<bool>(
    userStateProvider.select((u) => u.placementCompleted),
    (_, __) => refresh.value++,
  );
  ref.onDispose(refresh.dispose);

  bool isPlacementPath(String loc) =>
      loc == '/onboarding' || loc.startsWith('/placement');

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final done = ref.read(userStateProvider).placementCompleted;
      final loc = state.matchedLocation;
      if (!done && !isPlacementPath(loc)) return '/onboarding';
      if (done && loc == '/onboarding') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(
          path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(
        path: '/placement',
        builder: (_, __) => const PlacementScreen(),
        routes: [
          GoRoute(
            path: 'result',
            builder: (_, __) => const PlacementOutcomeScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/episode/:id',
        redirect: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          if (id == null || id < 1 || id > AppRules.totalEpisodes) return '/';
          final access = ref.read(episodeAccessProvider(id));
          if (access.isUnlocked) return null;
          return access.needsPaywall ? '/paywall' : '/';
        },
        builder: (_, state) =>
            EpisodeScreen(episodeId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/kana',
        builder: (_, __) => const KanaCourseScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 1;
              return KanaLessonScreen(lessonId: id);
            },
          ),
        ],
      ),
      GoRoute(path: '/paywall', builder: (_, __) => const PaywallScreen()),
      GoRoute(
        path: '/call',
        builder: (_, __) => const PersonaSelectorScreen(),
        routes: [
          GoRoute(
            path: 'live',
            redirect: (context, state) {
              final premium = ref.read(premiumProvider);
              final persona = ref.read(appSettingsProvider).persona;
              if (!AccessPolicy.canUsePersona(persona, isPremium: premium)) {
                return '/call';
              }
              final remaining = ref.read(callRemainingSecondsProvider);
              if (remaining != null && remaining <= 0) return '/call';
              return null;
            },
            builder: (_, __) => const LiveCallScreen(),
          ),
        ],
      ),
    ],
  );
});
