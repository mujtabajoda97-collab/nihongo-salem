import 'dart:convert';

import '../core/constants.dart';
import 'enums.dart';
import 'json_helpers.dart';

/// One AI answer. Same 7 keys in ai_tutor_system_prompt.txt and
/// free_talk_personas_prompt.txt.
class AiTurnResponse {
  const AiTurnResponse({
    required this.correctionAr,
    required this.replyJapanese,
    required this.replyRomaji,
    required this.replyArabic,
    required this.emotionTone,
    required this.hasMistake,
    required this.conversationCompleted,
  });

  factory AiTurnResponse.fromJson(Map<String, dynamic> j) => AiTurnResponse(
        correctionAr: reqString(j, 'correction_ar', ctx: 'ai turn: '),
        replyJapanese: reqString(j, 'reply_japanese', ctx: 'ai turn: '),
        replyRomaji: reqString(j, 'reply_romaji', ctx: 'ai turn: '),
        replyArabic: reqString(j, 'reply_arabic', ctx: 'ai turn: '),
        emotionTone: EmotionTone.fromWire(optString(j, 'emotion_tone')),
        hasMistake: readBool(j['has_mistake']),
        conversationCompleted: readBool(j['conversation_completed']),
      );

  /// Parses raw model text. Tolerates a stray code fence or text around the
  /// JSON object (the prompts forbid it, but a model can still slip).
  factory AiTurnResponse.fromRawText(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw FormatException('AI answer has no JSON object', raw);
    }
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('AI answer is not a JSON object', raw);
    }
    return AiTurnResponse.fromJson(decoded);
  }

  /// Arabic correction / encouragement shown in the correction box.
  final String correctionAr;
  final String replyJapanese;
  final String replyRomaji;
  final String replyArabic;
  final EmotionTone emotionTone;

  /// true => orange warning box; false => green box.
  final bool hasMistake;

  /// true on the last turn: the screen shows the summary and ends the session.
  final bool conversationCompleted;

  Map<String, dynamic> toJson() => {
        'correction_ar': correctionAr,
        'reply_japanese': replyJapanese,
        'reply_romaji': replyRomaji,
        'reply_arabic': replyArabic,
        'emotion_tone': emotionTone.wire,
        'has_mistake': hasMistake,
        'conversation_completed': conversationCompleted,
      };
}

/// Server answer to one tutor turn: the AI turn plus optional extras.
class TutorReply {
  const TutorReply({required this.turn, this.userTranscript, this.audioUrl});

  factory TutorReply.fromJson(Map<String, dynamic> j) => TutorReply(
        turn: AiTurnResponse.fromJson(j),
        userTranscript: optString(j, 'user_transcript'),
        audioUrl: optString(j, 'audio_url'),
      );

  final AiTurnResponse turn;

  /// What speech-to-text heard (voice turns only).
  final String? userTranscript;

  /// Spoken reply (text-to-speech), if the server produced one.
  final String? audioUrl;
}

/// Request for one turn of the in-episode tutor (station D).
///
/// [userMessage] is the typed/transcribed text. For voice turns the audio is
/// uploaded separately by the API client (batch 3) and this stays null.
class TutorTurnRequest {
  const TutorTurnRequest({
    required this.sessionId,
    required this.episodeId,
    required this.tone,
    required this.userName,
    required this.variables,
    required this.ttsProvider,
    this.userMessage,
    this.isFirstTurn = false,
  });

  final String sessionId;
  final int episodeId;
  final TutorTone tone;
  final String userName;

  /// From [Episode.tutorVariables].
  final Map<String, String> variables;
  final TtsProvider ttsProvider;
  final String? userMessage;
  final bool isFirstTurn;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'mode': 'episode_tutor',
        'episode_id': episodeId,
        'tone': tone.wire,
        'user_name': userName,
        'variables': variables,
        'tts_provider': ttsProvider.wire,
        'is_first_turn': isFirstTurn,
        if (userMessage != null) 'user_message': userMessage,
      };
}

/// Request for one turn of the free live call.
class FreeTalkTurnRequest {
  const FreeTalkTurnRequest({
    required this.sessionId,
    required this.persona,
    required this.userName,
    required this.userProgress,
    required this.knownVocab,
    required this.localTime,
    required this.ttsProvider,
    this.userMessage,
    this.isFirstTurn = false,
  });

  /// Final turn of a call: [AppRules.endCallControlMessage] as the message.
  factory FreeTalkTurnRequest.endCall({
    required String sessionId,
    required Persona persona,
    required String userName,
    required int userProgress,
    required String knownVocab,
    required String localTime,
    required TtsProvider ttsProvider,
  }) =>
      FreeTalkTurnRequest(
        sessionId: sessionId,
        persona: persona,
        userName: userName,
        userProgress: userProgress,
        knownVocab: knownVocab,
        localTime: localTime,
        ttsProvider: ttsProvider,
        userMessage: AppRules.endCallControlMessage,
      );

  final String sessionId;
  final Persona persona;
  final String userName;

  /// Last completed episode number (0 if none).
  final int userProgress;
  final String knownVocab;

  /// `HH:mm`, see `hhmm()` in core/date_utils.dart.
  final String localTime;
  final TtsProvider ttsProvider;
  final String? userMessage;
  final bool isFirstTurn;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'mode': 'free_talk',
        'persona': persona.wire,
        'tts_provider': ttsProvider.wire,
        'variables': {
          'PERSONA': persona.wire,
          'USER_NAME': userName,
          'USER_PROGRESS': '$userProgress',
          'KNOWN_VOCAB': knownVocab,
          'LOCAL_TIME': localTime,
          'IS_FIRST_TURN': '$isFirstTurn',
        },
        'is_first_turn': isFirstTurn,
        if (userMessage != null) 'user_message': userMessage,
      };
}
