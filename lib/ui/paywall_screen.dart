import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../services/entitlement_service.dart';
import 'theme.dart';

const _features = <(IconData, String)>[
  (Icons.menu_book_rounded, 'كل الحلقات الـ 40 بالترتيب، بلا قفل'),
  (Icons.call_rounded, 'مكالمات صوتية غير محدودة مع الذكاء الاصطناعي'),
  (Icons.theater_comedy_rounded, 'كل الشخصيات: الساخرة ولهجة أوساكا'),
  (Icons.record_voice_over_rounded, 'تصحيح فوري لنطقك وأخطائك بالعربية'),
  (Icons.workspace_premium_rounded, 'ادعم تطوير التطبيق وحلقات جديدة قادمة'),
];

/// Subscription screen: features, two plans, restore. Works against
/// RevenueCat, or against the mock service during testing.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String? _selectedId;
  bool _busy = false;

  PaywallPlan? _pick(List<PaywallPlan> plans) {
    if (plans.isEmpty) return null;
    for (final p in plans) {
      if (p.identifier == _selectedId) return p;
    }
    // Default: the annual plan (best value).
    return plans.firstWhere((p) => p.period == PlanPeriod.annual,
        orElse: () => plans.first);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _subscribe(PaywallPlan plan) async {
    if (_busy) return;
    setState(() => _busy = true);
    final premiumCtl = ref.read(premiumProvider.notifier);
    PurchaseOutcome outcome;
    try {
      outcome = await premiumCtl.purchase(plan);
    } on Object {
      outcome = PurchaseOutcome.failed;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case PurchaseOutcome.purchased:
        _snack('تم الاشتراك! استمتع بكل المزايا 🎉');
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.failed:
        _snack('تعذّرت عملية الشراء. حاول مرة أخرى.');
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    final premiumCtl = ref.read(premiumProvider.notifier);
    var found = false;
    var failed = false;
    try {
      found = await premiumCtl.restore();
    } on Object {
      failed = true;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (failed) {
      _snack('تعذّرت استعادة المشتريات. تحقق من الاتصال وحاول مجدداً.');
    } else if (found) {
      _snack('تمت استعادة اشتراكك.');
    } else {
      _snack('لم نجد اشتراكاً فعّالاً على هذا الحساب.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(premiumProvider);
    final isMock = ref.watch(isMockPurchasesProvider);
    final plansAsync = ref.watch(paywallPlansProvider);

    return Scaffold(
      body: Stack(
        children: [
          const _HeroBackground(),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IconButton(
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/'),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'إغلاق',
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    children: [
                      const _Hero(),
                      if (isMock) const _MockBanner(),
                      const SizedBox(height: 16),
                      _FeatureCard(),
                      const SizedBox(height: 16),
                      if (premium)
                        const _AlreadySubscribed()
                      else
                        plansAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white)),
                          ),
                          error: (_, __) => _PlansProblem(
                            text: 'تعذّر تحميل الباقات.',
                            onRetry: () => ref.invalidate(paywallPlansProvider),
                          ),
                          data: (plans) {
                            if (plans.isEmpty) {
                              return _PlansProblem(
                                text:
                                    'الاشتراك غير متاح حالياً. حاول لاحقاً أو أعد المحاولة.',
                                onRetry: () =>
                                    ref.invalidate(paywallPlansProvider),
                              );
                            }
                            return _Plans(
                              plans: plans,
                              selected: _pick(plans)!,
                              busy: _busy,
                              onSelect: (p) =>
                                  setState(() => _selectedId = p.identifier),
                              onSubscribe: _subscribe,
                            );
                          },
                        ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _restore,
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.white),
                        child: const Text('استعادة المشتريات'),
                      ),
                      const _Legal(),
                    ],
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

class _HeroBackground extends StatelessWidget {
  const _HeroBackground();

  @override
  Widget build(BuildContext context) => const SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF3B2A8C), AppColors.premium, Color(0xFFD7263D)],
            ),
          ),
        ),
      );
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) => const Column(
        children: [
          Icon(Icons.workspace_premium_rounded, size: 72, color: AppColors.gold),
          SizedBox(height: 8),
          Text('افتح كل شيء مع سالم',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text('تعلّم اليابانية بلا حدود: القصة كاملة والمكالمات والشخصيات.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.5)),
        ],
      );
}

class _MockBanner extends StatelessWidget {
  const _MockBanner();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.gold,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.science_rounded, color: AppColors.ink),
            SizedBox(width: 8),
            Expanded(
              child: Text('وضع المحاكاة - لن يُحصَّل أي مبلغ',
                  style: TextStyle(
                      color: AppColors.ink, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
}

class _FeatureCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            for (final (icon, text) in _features)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.premium.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 20, color: AppColors.premium),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _AlreadySubscribed extends StatelessWidget {
  const _AlreadySubscribed();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            const Icon(Icons.verified_rounded, size: 48, color: AppColors.success),
            const SizedBox(height: 8),
            const Text('أنت مشترك بالفعل 🎉',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('كل الحلقات والشخصيات والمكالمات مفتوحة لك.',
                textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => context.canPop() ? context.pop() : context.go('/'),
              child: const Text('متابعة التعلّم'),
            ),
          ],
        ),
      );
}

class _PlansProblem extends StatelessWidget {
  const _PlansProblem({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
}

class _Plans extends StatelessWidget {
  const _Plans({
    required this.plans,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onSubscribe,
  });

  final List<PaywallPlan> plans;
  final PaywallPlan selected;
  final bool busy;
  final ValueChanged<PaywallPlan> onSelect;
  final ValueChanged<PaywallPlan> onSubscribe;

  /// "Save x%" of the annual plan against 12 monthly payments.
  int? _savePercent() {
    PaywallPlan? annual;
    PaywallPlan? monthly;
    for (final p in plans) {
      if (p.period == PlanPeriod.annual) annual = p;
      if (p.period == PlanPeriod.monthly) monthly = p;
    }
    final a = annual?.priceAmount;
    final m = monthly?.priceAmount;
    if (a == null || m == null || m <= 0) return null;
    final pct = ((1 - a / (m * 12)) * 100).round();
    return pct > 0 ? pct : null;
  }

  @override
  Widget build(BuildContext context) {
    final save = _savePercent();
    // Annual first, then monthly, then any other.
    int rank(PaywallPlan p) => switch (p.period) {
          PlanPeriod.annual => 0,
          PlanPeriod.monthly => 1,
          PlanPeriod.other => 2,
        };
    final sorted = [...plans]..sort((a, b) => rank(a).compareTo(rank(b)));
    return Column(
      children: [
        for (final p in sorted) ...[
          _PlanTile(
            plan: p,
            selected: p.identifier == selected.identifier,
            badge: p.period == PlanPeriod.annual
                ? (save != null ? 'الأفضل قيمة • وفّر $save%' : 'الأفضل قيمة')
                : null,
            onTap: busy ? null : () => onSelect(p),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: AppColors.ink,
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: busy ? null : () => onSubscribe(selected),
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('اشترك الآن',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final PaywallPlan plan;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final per = switch (plan.period) {
      PlanPeriod.annual => 'في السنة',
      PlanPeriod.monthly => 'في الشهر',
      PlanPeriod.other => '',
    };
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.gold : Colors.transparent,
              width: 3,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.premium : AppColors.lockedGrey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    if (badge != null)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(badge!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(plan.priceString,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  if (per.isNotEmpty)
                    Text(per, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legal extends StatelessWidget {
  const _Legal();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'يتجدد الاشتراك تلقائياً ما لم تلغِه قبل 24 ساعة على الأقل من نهاية الفترة. '
          'يمكنك إدارته أو إلغاؤه في أي وقت من إعدادات حسابك في المتجر.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.6),
        ),
      );
}
