import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/enums.dart';
import '../providers/cloud.dart';
import '../providers/providers.dart';
import '../services/cloud_sync.dart';
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
            const SizedBox(height: 12),
            const _AccountTile(),
            const SizedBox(height: 20),
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

/// Sign-in status: guests are invited to save their progress in the cloud.
class _AccountTile extends ConsumerWidget {
  const _AccountTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(cloudSessionProvider);
    final sync = ref.watch(cloudSyncProvider);
    final theme = Theme.of(context);

    if (session == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.of(context).pop();
          context.push('/account');
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: const Color(0xFFF1EDFC),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_upload_rounded, color: Color(0xFF6C4CD9), size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('احفظ تقدّمك في السحابة',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text('سجّل الدخول لتبقى نجومك وحلقاتك محفوظة على أي جهاز',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded),
            ],
          ),
        ),
      );
    }

    final status = switch (sync.phase) {
      SyncPhase.syncing => 'جارٍ المزامنة...',
      SyncPhase.failed => 'تعذّرت المزامنة: ${sync.error ?? ''}',
      SyncPhase.done => 'تمّت المزامنة',
      SyncPhase.idle => 'متصل',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFFE2F6EC),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_done_rounded, color: Color(0xFF1FA971), size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(session.email,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(status, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: sync.phase == SyncPhase.syncing
                    ? null
                    : () => ref.read(cloudSyncProvider.notifier).syncNow(),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('مزامنة الآن'),
              ),
              TextButton.icon(
                onPressed: () => ref.read(cloudSyncProvider.notifier).signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
