import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import 'theme.dart';

class _Slide {
  const _Slide(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const _slides = [
  _Slide(
    Icons.flight_land_rounded,
    'قصة سالم في طوكيو',
    'رافق سالم من وصوله إلى مطار ناريتا حتى أول وظيفة له، وتعلّم اليابانية من مواقفه اليومية.',
  ),
  _Slide(
    Icons.menu_book_rounded,
    '40 حلقة بمستوى N5',
    'في كل حلقة: مشهد مصوّر، مفردات وقواعد، تمارين، ثم محادثة قصيرة.',
  ),
  _Slide(
    Icons.record_voice_over_rounded,
    'تحدّث مع معلم ذكي',
    'تدرّب على النطق بصوتك واحصل على تصحيح فوري بالعربية.',
  ),
];

/// First screen: short intro, optional name, then the placement test or a
/// direct start from episode 1.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  final _nameController = TextEditingController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _saveName() {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      ref.read(userStateProvider.notifier).setDisplayName(name);
    }
  }

  void _startTest() {
    _saveName();
    context.go('/placement');
  }

  void _startFromZero() {
    _saveName();
    ref.read(userStateProvider.notifier).skipPlacement();
    context.go('/'); // episode 1 opens with its own first letters
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) {
                    final s = _slides[i];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.brand.withValues(alpha: 0.1),
                          ),
                          child: Icon(s.icon, size: 64, color: AppColors.brand),
                        ),
                        const SizedBox(height: 28),
                        Text(s.title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text(s.body,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(height: 1.7)),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: i == _page
                            ? AppColors.brand
                            : AppColors.lockedGrey,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'اسمك (اختياري)',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _startTest,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('ابدأ اختبار تحديد المستوى',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('10 أسئلة - حوالي 3 دقائق',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _startFromZero,
                child: const Text('أنا مبتدئ تماماً: ابدأ من الصفر'),
              ),
              TextButton(
                onPressed: () => context.push('/account'),
                child: const Text('لديّ حساب؟ سجّل الدخول لاسترجاع تقدّمك'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
