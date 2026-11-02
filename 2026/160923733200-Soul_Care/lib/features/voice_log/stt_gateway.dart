import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import 'voice_gateway.dart';

/// On-device speech recognition gateway (no audio leaves the device;
/// the plugin streams microphone audio to the platform recognizer only —
/// nothing is uploaded by SoulCare, and no audio is retained afterwards).
class SpeechToTextGateway implements VoiceInputGateway {
  final SpeechToText _stt = SpeechToText();

  @override
  Future<MicAvailability> check() async {
    try {
      final ok = await _stt.initialize();
      if (ok) return MicAvailability.available;
      if (!await _hasPermission()) return MicAvailability.denied;
      return MicAvailability.unavailable;
    } catch (_) {
      return MicAvailability.unavailable;
    }
  }

  Future<bool> _hasPermission() async {
    try {
      return _stt.hasPermission;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> listenOnce(
      {Duration timeout = const Duration(seconds: 30)}) async {
    try {
      final ok = await _stt.initialize();
      if (!ok) return null;
      final done = Completer<String?>();
      var last = '';
      await _stt.listen(
        onResult: (r) {
          last = r.recognizedWords;
          if (r.finalResult && !done.isCompleted) {
            done.complete(last.isEmpty ? null : last);
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: timeout,
          pauseFor: const Duration(seconds: 3),
        ),
      );
      final result = await done.future.timeout(
        timeout + const Duration(seconds: 5),
        onTimeout: () => last.isEmpty ? null : last,
      );
      try {
        await _stt.stop();
      } catch (_) {}
      return (result == null || result.trim().isEmpty) ? null : result;
    } catch (_) {
      return null;
    }
  }
}
