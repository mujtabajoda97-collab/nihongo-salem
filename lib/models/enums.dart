/// Voice tone returned by the AI on every turn; drives the TTS engine and the
/// colour of the voice orb.
enum EmotionTone {
  happy,
  strict,
  sigh,
  excited,
  calm;

  /// The exact string used in the JSON contract.
  String get wire => name;

  static EmotionTone fromWire(String? v) => values.firstWhere(
        (e) => e.name == v,
        orElse: () => calm,
      );
}

/// Coaching tone chosen inside the episode (ai_tutor_system_prompt.txt -> {{TONE}}).
enum TutorTone {
  politeEncouraging('polite_encouraging', 'الأستاذ الهادئ المشجع'),
  strictTsundere('strict_tsundere', 'المدرّب الصارم الكوميدي'),
  friendlyPeer('friendly_peer', 'الصديق البسيط');

  const TutorTone(this.wire, this.labelAr);
  final String wire;
  final String labelAr;

  static TutorTone fromWire(String? v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => politeEncouraging,
      );
}

/// Persona of the free live call (free_talk_personas_prompt.txt -> {{PERSONA}}).
enum Persona {
  politeSensei('polite_sensei', 'الأستاذ المهذب', true),
  casualFriend('casual_friend', 'الصديق العفوي', true),
  tsundere('tsundere', 'الشخصية الساخرة', false),
  kansai('kansai', 'لهجة أوساكا', false);

  const Persona(this.wire, this.labelAr, this.isFree);
  final String wire;
  final String labelAr;

  /// Free plan: only the first two personas.
  final bool isFree;

  static Persona fromWire(String? v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => politeSensei,
      );
}

/// Text-to-speech engine. Switchable from the settings; sent to the server on
/// every turn. STT is always OpenAI Whisper.
enum TtsProvider {
  openai('openai', 'OpenAI (gpt-4o-mini-tts)'),
  elevenlabs('elevenlabs', 'ElevenLabs');

  const TtsProvider(this.wire, this.labelEn);
  final String wire;
  final String labelEn;

  static TtsProvider fromWire(String? v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => openai,
      );
}
