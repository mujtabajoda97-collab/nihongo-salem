import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/episode.dart';
import '../../providers/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum _CardsTab { vocabulary, grammar }

/// Station B: vocabulary flash cards and grammar cards.
class CardsStation extends ConsumerStatefulWidget {
  const CardsStation({super.key, required this.episode, required this.onDone});

  final Episode episode;
  final VoidCallback onDone;

  @override
  ConsumerState<CardsStation> createState() => _CardsStationState();
}

class _CardsStationState extends ConsumerState<CardsStation> {
  _CardsTab _tab = _CardsTab.vocabulary;
  final PageController _pages = PageController();
  int _page = 0;
  final Set<int> _known = {};

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vocab = widget.episode.vocabulary;
    final grammar = widget.episode.grammarPoints;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<_CardsTab>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _CardsTab.vocabulary,
                icon: const Icon(Icons.style_rounded),
                label: Text('المفردات (${vocab.length})'),
              ),
              ButtonSegment(
                value: _CardsTab.grammar,
                icon: const Icon(Icons.auto_stories_rounded),
                label: Text('القواعد (${grammar.length})'),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _tab == _CardsTab.vocabulary
                ? _buildVocabulary(vocab)
                : _buildGrammar(grammar),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: widget.onDone,
            child: const Text('التالي: التمارين'),
          ),
        ],
      ),
    );
  }

  Widget _buildVocabulary(List<VocabItem> vocab) {
    final showRomaji = ref.watch(appSettingsProvider).showRomaji;
    return Column(
      children: [
        Row(
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text('${_page + 1} / ${vocab.length}'),
            ),
            const Spacer(),
            Text('عرفتُ ${_known.length} من ${vocab.length}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: vocab.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final v = vocab[i];
              final known = _known.contains(i);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                     child: SingleChildScrollView(
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        JpText(v.headline,
                            size: 44, align: TextAlign.center),
                        if (v.hasKanji)
                          JpText(v.kana,
                              size: 24,
                              weight: FontWeight.w500,
                              color: AppColors.brand,
                              align: TextAlign.center),
                        if (showRomaji) RomajiText(v.romaji, size: 16),
                        const SizedBox(height: 14),
                        Text(v.arabic,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 20, height: 1.5)),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            AudioButton(
                                key: ValueKey('v$i'),
                                assetPath: v.audio,
                                slow: false,
                                label: '1.0x'),
                            AudioButton(
                                key: ValueKey('vs$i'),
                                assetPath: v.audio,
                                slow: true,
                                label: '0.7x'),
                          ],
                        ),
                        const SizedBox(height: 14),
                        FilterChip(
                          selected: known,
                          label: const Text('عرفتها'),
                          avatar: Icon(
                            known
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            size: 18,
                          ),
                          onSelected: (on) => setState(() {
                            if (on) {
                              _known.add(i);
                            } else {
                              _known.remove(i);
                            }
                          }),
                        ),
                      ],
                    ),
                   ),
                  ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text('اسحب لرؤية البطاقة التالية',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildGrammar(List<GrammarPoint> grammar) {
    return ListView.separated(
      itemCount: grammar.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final g = grammar[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('القاعدة ${i + 1}',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: AppColors.brand)),
                const SizedBox(height: 2),
                Text(g.titleAr,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: JpText(g.pattern, size: 17),
                ),
                const SizedBox(height: 12),
                Text(g.explanationAr,
                    style: const TextStyle(fontSize: 15, height: 1.8)),
              ],
            ),
          ),
        );
      },
    );
  }
}
