import 'voice_parse_engine.dart';

/// Structured-extraction seam.
///
/// If a local on-device model is available in the future, it may implement
/// this interface to assist with extraction. The app always validates every
/// extracted value before saving — an AI model must never invent statistics,
/// and unvalidated model output is never stored. Today no model exists, so
/// [DeterministicVoiceExtractor] is the only implementation in use.
abstract class VoiceExtractor {
  Future<VoiceExtraction> extract(String transcript);
}

/// Default extractor: deterministic parsing, no network, no model.
class DeterministicVoiceExtractor implements VoiceExtractor {
  const DeterministicVoiceExtractor();

  @override
  Future<VoiceExtraction> extract(String transcript) async =>
      parseVoiceLog(transcript);
}

/// Microphone availability for voice input.
enum MicAvailability { available, unavailable, denied }

/// Speech-to-text seam. Production uses the on-device recognizer;
/// tests and mic-less environments inject fakes or the unavailable gateway.
/// Recordings are never uploaded and temporary audio is discarded after
/// processing (handled inside each implementation).
abstract class VoiceInputGateway {
  Future<MicAvailability> check();
  Future<String?> listenOnce({Duration timeout = const Duration(seconds: 30)});
}

/// Default gateway: speech input unavailable (no mic, denied permission, or
/// no recognizer). Typed input remains fully functional.
class UnavailableVoiceGateway implements VoiceInputGateway {
  final MicAvailability reason;
  const UnavailableVoiceGateway(
      {this.reason = MicAvailability.unavailable});

  @override
  Future<MicAvailability> check() async => reason;

  @override
  Future<String?> listenOnce(
          {Duration timeout = const Duration(seconds: 30)}) async =>
      null;
}

/// Scripted gateway for tests and demos.
class FakeVoiceGateway implements VoiceInputGateway {
  final String transcript;
  final MicAvailability availability;
  const FakeVoiceGateway(this.transcript,
      {this.availability = MicAvailability.available});

  @override
  Future<MicAvailability> check() async => availability;

  @override
  Future<String?> listenOnce(
      {Duration timeout = const Duration(seconds: 30)}) async {
    if (availability != MicAvailability.available) return null;
    return transcript;
  }
}
