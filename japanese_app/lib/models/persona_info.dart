import 'package:flutter/material.dart';

import 'enums.dart';

/// What the selector screen shows for one persona. The greetings are the exact
/// first lines defined in free_talk_personas_prompt.txt.
class PersonaInfo {
  const PersonaInfo({
    required this.persona,
    required this.nameAr,
    required this.nameJp,
    required this.styleAr,
    required this.tagsAr,
    required this.greetingJp,
    required this.greetingRomaji,
    required this.greetingAr,
    required this.icon,
    required this.color,
    required this.avatar,
  });

  final Persona persona;
  final String nameAr;
  final String nameJp;
  final String styleAr;
  final List<String> tagsAr;
  final String greetingJp;
  final String greetingRomaji;
  final String greetingAr;
  final IconData icon;
  final Color color;

  /// Optional picture (falls back to [icon] when the file is missing).
  final String avatar;

  static PersonaInfo of(Persona p) => all.firstWhere((i) => i.persona == p);

  static const List<PersonaInfo> all = [
    PersonaInfo(
      persona: Persona.politeSensei,
      nameAr: 'الأستاذ المهذب',
      nameJp: '先生',
      styleAr: 'هادئ وصبور، يتكلم باليابانية المهذبة (です/ます).',
      tagsAr: ['مهذب', 'صبور', 'رسمي'],
      greetingJp: 'こんにちは！今日も一緒に日本語を練習しましょう。',
      greetingRomaji: 'Konnichiwa! Kyō mo issho ni nihongo o renshū shimashō.',
      greetingAr: 'مرحباً! لنتدرب على اليابانية معاً اليوم أيضاً.',
      icon: Icons.school_rounded,
      color: Color(0xFF2E7D9E),
      avatar: 'assets/images/characters/persona_polite_sensei.webp',
    ),
    PersonaInfo(
      persona: Persona.casualFriend,
      nameAr: 'الصديق العفوي',
      nameJp: '友だち',
      styleAr: 'شاب نشيط يتكلم بالعامية اليابانية اليومية.',
      tagsAr: ['شبابي', 'عفوي', 'نشيط'],
      greetingJp: 'よっ！元気？今何してるの？ご飯食べた？',
      greetingRomaji: 'Yo! Genki? Ima nani shiteru no? Gohan tabeta?',
      greetingAr: 'هلا! كيفك؟ شو تسوي الحين؟ أكلت؟',
      icon: Icons.emoji_emotions_rounded,
      color: Color(0xFFE8801A),
      avatar: 'assets/images/characters/persona_casual_friend.webp',
    ),
    PersonaInfo(
      persona: Persona.tsundere,
      nameAr: 'الشخصية الساخرة',
      nameJp: 'ツンデレ',
      styleAr: 'تتذمر بشكل كوميدي على طريقة الأنمي، لكنها تعلّمك بجد.',
      tagsAr: ['كوميدي', 'ساخر', 'أنمي'],
      greetingJp: 'はぁ？また来たの？まあいいよ、早く始めて！',
      greetingRomaji: 'Hā? Mata kita no? Mā ii yo, hayaku hajimete!',
      greetingAr: 'ها؟ جئت مجدداً؟ حسناً، هيا ابدأ بسرعة!',
      icon: Icons.mood_bad_rounded,
      color: Color(0xFFD7263D),
      avatar: 'assets/images/characters/persona_tsundere.webp',
    ),
    PersonaInfo(
      persona: Persona.kansai,
      nameAr: 'لهجة أوساكا',
      nameJp: '関西弁',
      styleAr: 'مرح ودافئ، بلهجة كانساي مع نكات سريعة.',
      tagsAr: ['مرح', 'لهجة', 'أوساكا'],
      greetingJp: 'まいど！元気しとる？今日も楽しくしゃべろか！',
      greetingRomaji: 'Maido! Genki shitoru? Kyō mo tanoshiku shaberoka!',
      greetingAr: 'أهلاً! كيف حالك؟ لنتحدث بمرح اليوم أيضاً!',
      icon: Icons.celebration_rounded,
      color: Color(0xFF8E44AD),
      avatar: 'assets/images/characters/persona_kansai.webp',
    ),
  ];
}
