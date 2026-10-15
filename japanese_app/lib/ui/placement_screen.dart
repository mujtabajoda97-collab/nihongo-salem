import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/placement_test.dart';
import '../providers/providers.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// The 10-question placement test. No feedback after each answer; the review
/// comes on the result screen.
class PlacementScreen extends ConsumerStatefulWidget {
  const PlacementScreen({super.key});

  @override
  ConsumerState<PlacementScreen> createState() => _PlacementScreenState();
}

class _PlacementScreenState extends ConsumerState<PlacementScreen> {
  /// Display order of the options of each question (indexes into `options`).
  Map<int, List<int>>? _orders;
  final Map<int, int?> _answers = {};
  int _index = 0;

  /// Selected option, as an index in the ORIGINAL options order.
  int? _selected;

  @override
  void initState() {
    super.initState();
    // A retake starts clean: forget the previous result.
    Future.microtask(
        () => ref.read(placementResultProvider.notifier).state = null);
  }

  void _ensureOrders(PlacementTest test) {
    if (_orders != null) return;
    final random = Random();
    _orders = {
      for (final q in test.questions)
        q.id: test.settings.shuffleOptions
            ? q.shuffledOptionOrder(random)
            : [for (var i = 0; i < q.options.length; i++) i],
    };
  }

  void _advance(PlacementTest test, int? answer) {
    final q = test.questions[_index];
    _answers[q.id] = answer;
    if (_index == test.questions.length - 1) {
      ref.read(placementResultProvider.notifier).state = test.evaluate(_answers);
      context.go('/placement/result');
      return;
    }
    setState(() {
      _index++;
      _selected = null;
    });
  }

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الخروج من الاختبار؟'),
        content: const Text('ستفقد إجاباتك الحالية.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('متابعة الاختبار')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('خروج')),
        ],
      ),
    );
    if (leave == true && mounted) {
      final done = ref.read(userStateProvider).placementCompleted;
      context.go(done ? '/' : '/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(placementTestProvider);
    return Scaffold(
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('تعذّر تحميل الاختبار:\n$e', textAlign: TextAlign.center),
            ),
          ),
          data: (test) {
            _ensureOrders(test);
            return _buildTest(context, test);
          },
        ),
      ),
    );
  }

  Widget _buildTest(BuildContext context, PlacementTest test) {
    final q = test.questions[_index];
    final order = _orders![q.id]!;
    final isLast = _index == test.questions.length - 1;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _confirmExit,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'إغلاق',
              ),
              Expanded(
                child: Text(
                  'السؤال ${_index + 1} من ${test.questions.length}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (_index + 1) / test.questions.length,
              minHeight: 8,
            ),
          ),
          if (_index == 0) ...[
            const SizedBox(height: 12),
            Text(test.instructionsAr,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.6)),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Chip(label: Text(q.skillAr)),
                ),
                const SizedBox(height: 8),
                Text(q.questionAr,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold, height: 1.5)),
                if (q.promptJp.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(child: JpText(q.promptJp, size: 26)),
                  ),
                ],
                const SizedBox(height: 18),
                for (final optionIndex in order)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OptionTile(
                      text: q.options[optionIndex],
                      selected: _selected == optionIndex,
                      onTap: () => setState(() => _selected = optionIndex),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (test.settings.allowSkip)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _advance(test, null),
                    child: Text(test.settings.skipLabelAr),
                  ),
                ),
              if (test.settings.allowSkip) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed:
                      _selected == null ? null : () => _advance(test, _selected),
                  child: Text(isLast ? 'إنهاء الاختبار' : 'التالي'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  /// Options that are Japanese (no Arabic letters) are shown left-to-right.
  static bool _isArabic(String s) => RegExp(r'[؀-ۿ]').hasMatch(s);

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.brand : const Color(0xFFD9D4E3);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _isArabic(text)
                  ? Text(text, style: const TextStyle(fontSize: 17))
                  : JpText(text, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
