import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../models/enums.dart';
import '../../models/persona_info.dart';
import '../../providers/providers.dart';
import '../../services/access_policy.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Before the call: pick the persona / dialect. Free: polite_sensei and
/// casual_friend. Tsundere and Kansai carry a purple crown and open the
/// paywall for non-subscribers.
class PersonaSelectorScreen extends ConsumerStatefulWidget {
  const PersonaSelectorScreen({super.key});

  @override
  ConsumerState<PersonaSelectorScreen> createState() =>
      _PersonaSelectorScreenState();
}

class _PersonaSelectorScreenState extends ConsumerState<PersonaSelectorScreen> {
  late Persona _selected;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(appSettingsProvider).persona;
    final premium = ref.read(premiumProvider);
    _selected = AccessPolicy.canUsePersona(saved, isPremium: premium)
        ? saved
        : Persona.politeSensei;
  }

  void _pick(PersonaInfo info) {
    final premium = ref.read(premiumProvider);
    if (!AccessPolicy.canUsePersona(info.persona, isPremium: premium)) {
      context.push('/paywall');
      return;
    }
    setState(() => _selected = info.persona);
  }

  void _start() {
    final ok = ref.read(appSettingsProvider.notifier).setPersona(_selected);
    if (!ok) {
      context.push('/paywall');
      return;
    }
    context.push('/call/live');
  }

  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(premiumProvider);
    final remaining = ref.watch(callRemainingSecondsProvider);
    final settings = ref.watch(appSettingsProvider);
    final settingsCtl = ref.read(appSettingsProvider.notifier);
    final theme = Theme.of(context);
    final outOfTime = remaining != null && remaining <= 0;

    return Scaffold(
      appBar: AppBar(title: const Text('اختر شخصية المكالمة')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'تحدّث مع شخصية بأسلوب مختلف. يمكنك تغييرها في أي مكالمة.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                children: [
                  for (final info in PersonaInfo.all) ...[
                    _PersonaCard(
                      info: info,
                      selected: info.persona == _selected,
                      locked: !AccessPolicy.canUsePersona(info.persona,
                          isPremium: premium),
                      onTap: () => _pick(info),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('إظهار الروماجي'),
                    value: settings.showRomaji,
                    onChanged: settingsCtl.setShowRomaji,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('إظهار الترجمة العربية'),
                    value: settings.showArabicTranslation,
                    onChanged: settingsCtl.setShowArabicTranslation,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TimeInfo(remaining: remaining, premium: premium),
                  const SizedBox(height: 10),
                  if (outOfTime)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.premium),
                      onPressed: () => context.push('/paywall'),
                      icon: const Icon(Icons.workspace_premium_rounded),
                      label: const Text('اشترك لمكالمات غير محدودة'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('ابدأ المكالمة'),
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

class _TimeInfo extends StatelessWidget {
  const _TimeInfo({required this.remaining, required this.premium});

  final int? remaining;
  final bool premium;

  @override
  Widget build(BuildContext context) {
    if (premium || remaining == null) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.all_inclusive_rounded, size: 18, color: AppColors.premium),
          SizedBox(width: 6),
          Text('مكالمات غير محدودة'),
        ],
      );
    }
    final mins = (remaining! / 60).ceil();
    final text = remaining! <= 0
        ? 'انتهت دقائقك المجانية اليوم، وتتجدد غداً.'
        : 'متبقّي اليوم: $mins من ${AppRules.freeDailyCallSeconds ~/ 60} دقائق مجانية';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.timer_outlined, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(text, textAlign: TextAlign.center)),
      ],
    );
  }
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.info,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final PersonaInfo info;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = selected ? info.color : const Color(0xFFEAE6F0);
    return Semantics(
      button: true,
      selected: selected,
      label: locked ? '${info.nameAr}، للمشتركين فقط' : info.nameAr,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? info.color.withValues(alpha: 0.07) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: info.color.withValues(alpha: 0.15),
                        child: ClipOval(
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: SafeAssetImage(
                              info.avatar,
                              fallback:
                                  Icon(info.icon, color: info.color, size: 30),
                            ),
                          ),
                        ),
                      ),
                      if (locked)
                        const PositionedDirectional(
                          bottom: -4,
                          end: -4,
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: AppColors.premium,
                            child: Icon(Icons.workspace_premium_rounded,
                                size: 15, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(info.nameAr,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 8),
                            JpText(info.nameJp, size: 14, weight: FontWeight.w500),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(info.styleAr, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (locked)
                    const _Badge(
                        label: 'للمشتركين',
                        color: AppColors.premium,
                        icon: Icons.lock_rounded)
                  else if (selected)
                    Icon(Icons.check_circle_rounded, color: info.color)
                  else
                    const _Badge(label: 'مجاني', color: AppColors.success),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in info.tagsAr)
                    Chip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      backgroundColor: info.color.withValues(alpha: 0.1),
                      side: BorderSide.none,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F3FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    JpText(info.greetingJp, size: 15, weight: FontWeight.w500),
                    RomajiText(info.greetingRomaji, size: 12),
                    const SizedBox(height: 2),
                    Text(info.greetingAr, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 3),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      );
}
