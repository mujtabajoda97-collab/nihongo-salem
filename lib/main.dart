import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_router.dart';
import 'providers/providers.dart';
import 'services/entitlement_service.dart';
import 'services/tutor_api.dart';
import 'ui/theme.dart';
import 'providers/cloud.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final entitlement = await createEntitlementService(prefs);

  unawaited(wakeUpServer()); // wakes the (free-plan) server while the app opens

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        entitlementServiceProvider.overrideWithValue(entitlement),
      ],
      child: const NihongoApp(),
    ),
  );
}

class NihongoApp extends ConsumerWidget {
  const NihongoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(cloudSyncProvider); // keeps the cloud sync running while the app is open
    return MaterialApp.router(
      title: 'نيهونغو مع سالم',
      debugShowCheckedModeBanner: false,
      // Arabic UI => right-to-left layout everywhere.
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
