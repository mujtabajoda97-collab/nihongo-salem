#!/usr/bin/env python3
"""Picks 1-2 NEW hiragana per episode, taken from the episode's own vocabulary
(base letters before their dakuten forms), and writes assets/data/episode_letters.json.

    python3 tool/make_episode_letters.py
"""
import json
import os
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
kc = json.load(open(os.path.join(ROOT, 'assets/data/kana_course.json'), encoding='utf-8'))
chars = {c['char'] for l in kc['lessons'] for c in l['chars'] if len(c['char']) == 1}


def base_of(ch):
    d = unicodedata.normalize('NFD', ch)
    return unicodedata.normalize('NFC', d[0]) if len(d) > 1 else ch


learned, out = set(), {}
for i in range(1, 41):
    ep = json.load(open(os.path.join(ROOT, 'assets/data/episodes/episode_%02d.json' % i), encoding='utf-8'))
    cands = []
    for v in ep['vocabulary']:
        for ch in v['kana']:
            if ch in chars and ch not in learned and ch not in [c for c, _ in cands]:
                if base_of(ch) != ch and base_of(ch) not in learned:
                    continue
                cands.append((ch, v))
    cands.sort(key=lambda t: base_of(t[0]) != t[0])  # base letters first (stable)
    pick = cands[:2]
    out[str(i)] = [{'char': c, 'example': {'jp': v['kana'], 'romaji': v['romaji'], 'ar': v['arabic'],
                                           'audio': v['audio']}} for c, v in pick]
    learned |= {c for c, _ in pick}

json.dump(out, open(os.path.join(ROOT, 'assets/data/episode_letters.json'), 'w', encoding='utf-8'),
          ensure_ascii=False, indent=1)
print('episodes with letters:', sum(1 for v in out.values() if v), 'letters:', len(learned))
