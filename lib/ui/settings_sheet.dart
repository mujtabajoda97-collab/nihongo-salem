import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/enums.dart';
import '../providers/providers.dart';
import '../services/entitlement_service.dart';

Future<void> showSettingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const SettingsSheet(),
    );

/// App preferences: coach tone, subtitles, slow audio, voice engine, retake
/// the placement test, reset progress.
class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final controller = ref.read(appSettingsProvider.notifier);
    final theme = Theme.of(context);
    final premium = ref.watch(premiumProvider);
    final service = ref.watch(entitlementServiceProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text('الإعدادات',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text('أسلوب المعلم داخل الحلقات', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<TutorTone>(
              showSelectedIcon: false,
              segments: [
                for (final t in TutorTone.values)
                  ButtonSegment(
                    value: t,
                    label: Text(t.labelAr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12)),
                  ),
              ],
              selected: {settings.tutorTone},
              onSelectionChanged: (s) => controller.setTutorTone(s.first),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار الروماجي (النطق بالحروف اللاتينية)'),
              value: settings.showRomaji,
              onChanged: controller.setShowRomaji,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار الترجمة العربية'),
              value: settings.showArabicTranslation,
              onChanged: controller.setShowArabicTranslation,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('الصوت البطيء (0.7x) افتراضياً'),
              value: settings.slowAudio,
              onChanged: controller.setSlowAudio,
            ),
            const SizedBox(height: 8),
            Text('محرّك الصوت (النطق)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<TtsProvider>(
              showSelectedIcon: false,
              segments: [
                for (final p in TtsProvider.values)
                  ButtonSegment(
                    value: p,
                    label: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(p == TtsProvider.openai ? 'OpenAI' : 'ElevenLabs'),
                    ),
                  ),
              ],
              selected: {settings.ttsProvider},
              onSelectionChanged: (s) => controller.setTtsProvider(s.first),
            ),
            const Divider(height: 32),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.quiz_outlined),
              title: const Text('إعادة اختبار تحديد المستوى'),
              onTap: () {
                Navigator.of(context).pop();
                context.go('/placement');
              },
            ),
            if (premium && service is MockEntitlementService)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.science_outlined),
                title: const Text('إلغاء الاشتراك التجريبي (وضع المحاكاة)'),
                onTap: () async {
                  await service.cancelMockSubscription();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline_rounded,
                  color: theme.colorScheme.error),
              title: Text('مسح التقدّم وإعادة البدء',
                  style: TextStyle(color: theme.colorScheme.error)),
              onTap: () => _confirmReset(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح كل التقدّم؟'),
        content: const Text('سيُحذف تقدّمك ونجومك وإعداداتك من هذا الجهاز.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('مسح')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    // Take the notifier first: this sheet's own ref dies when it closes.
    final notifier = ref.read(userStateProvider.notifier);
    Navigator.of(context).pop();
    await notifier.resetAll();
  }
}
