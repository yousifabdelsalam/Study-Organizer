// nova_audio_service.dart
// Handles playing local MP3 sound effects (e.g. ElevenLabs exports) and stopping them.
// FIX 1: Channel name corrected to match MainActivity ('com.example.study_organizer/volume_key').
// FIX 2: Now signals setAudioActive(true/false) so MainActivity only consumes
//         volume keys when NOVA audio is actually playing.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:study_organizer/features/speech_engine/data/services/eleven_labs_service.dart';

class NovaAudioService {
  static final AudioPlayer _player = AudioPlayer();
  static const MethodChannel _channel = MethodChannel(
    'com.example.study_organizer/volume_key',
  );

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVolumeDown') {
        await stop();
        // Also stop Nova's ElevenLabs TTS voice
        await NovaElevenLabsService.stop();
      }
    });
  }

  /// Play a sound from the assets folder. Path should be like 'sounds/nova_on.mp3'.
  static Future<void> playAsset(String path) async {
    try {
      await _player.stop();
      // Tell MainActivity to start consuming volume keys
      await _channel.invokeMethod('setAudioActive', true);
      await _player.play(AssetSource(path));
      // When playback ends naturally, release volume key intercept
      _player.onPlayerComplete.first.then((_) {
        _channel.invokeMethod('setAudioActive', false);
      });
    } catch (e) {
      // Ignore playback errors; ensure key intercept is released
      try {
        await _channel.invokeMethod('setAudioActive', false);
      } catch (_) {}
    }
  }

  /// Instantly stop any currently playing audio.
  static Future<void> stop() async {
    try {
      await _player.stop();
    } catch (e) {
      // Ignore
    } finally {
      // Always release volume key intercept on stop
      try {
        await _channel.invokeMethod('setAudioActive', false);
      } catch (_) {}
    }
  }
}
