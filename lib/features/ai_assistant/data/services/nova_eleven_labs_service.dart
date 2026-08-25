// nova_elevenlabs_service.dart — ElevenLabs AI Voice for NOVA
//
// Replaces Flutter TTS with ElevenLabs API for high-quality AI voice.
// Falls back to Flutter TTS if ElevenLabs key is missing or call fails.
//
// FIX (voice cut-off): long texts are split into sentence chunks (≤500 chars).
// Chunks are added to a queue and played back-to-back. No truncation of content.
//
// HOW IT WORKS:
// 1. User sets their ElevenLabs API key + Voice ID in NOVA Settings.
// 2. When NOVA speaks, this service splits text into sentence chunks.
// 3. Each chunk is sent to /v1/text-to-speech/{voice_id} and queued for playback.
// 4. Uses "eleven_turbo_v2_5" model — lowest latency, best for chat (~400ms).
// 5. Caches audio bytes in memory (last 10 phrases) to avoid re-fetching.
//
// SETUP FOR USER:
// 1. Go to elevenlabs.io → sign in → My Voices → your Jarvis voice
// 2. Copy Voice ID (looks like: "AbCdEfGhIjKlMnOp1234")
// 3. Go to Profile → API Key → copy key (starts with "sk_")
// 4. Paste both in NOVA Settings → Voice section
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';

const _prefElevenLabsKey = 'elevenlabs_api_key';
const _prefElevenVoiceId = 'elevenlabs_voice_id';
const _prefUseElevenLabs = 'use_elevenlabs_tts';

// ElevenLabs model — turbo_v2_5 has lowest latency (~300-500ms) for chat
const _kModel = 'eleven_turbo_v2_5';

// Maximum characters per chunk sent to ElevenLabs
// ElevenLabs API accepts up to 5000 chars; we chunk at 500 for fast response start
const _kMaxChunkChars = 500;

class NovaElevenLabsService {
  // ── Settings ───────────────────────────────────────────────────────────────
  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final k = prefs.getString(_prefElevenLabsKey)?.trim() ?? '';
    return k.isEmpty ? null : k;
  }

  static Future<String?> getVoiceId() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_prefElevenVoiceId)?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefUseElevenLabs) ?? false;
    if (!enabled) return false;
    final key = await getApiKey();
    final vid = await getVoiceId();
    return key != null && vid != null;
  }

  static Future<void> setApiKey(String key) async =>
      (await SharedPreferences.getInstance()).setString(
        _prefElevenLabsKey,
        key.trim(),
      );

  static Future<void> setVoiceId(String id) async =>
      (await SharedPreferences.getInstance()).setString(
        _prefElevenVoiceId,
        id.trim(),
      );

  static Future<void> setEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        _prefUseElevenLabs,
        value,
      );

  // ── Audio player ──────────────────────────────────────────────────────────
  static final AudioPlayer _player = AudioPlayer();
  static bool _playing = false;

  // ── Chunk queue ───────────────────────────────────────────────────────────
  // Queue of text chunks waiting to be spoken
  static final List<String> _queue = [];
  static bool _queueRunning = false;

  // Volume key channel — shared with NovaAudioService
  static const MethodChannel _volumeChannel = MethodChannel(
    'com.example.study_organizer/volume_key',
  );

  // Simple in-memory cache: text hash → temp file path (last 10 phrases)
  static final Map<int, String> _cache = {};

  // ── Fallback Flutter TTS ──────────────────────────────────────────────────
  static final FlutterTts _fallbackTts = FlutterTts();
  static bool _fallbackSetup = false;

  static Future<void> _setupFallback() async {
    if (_fallbackSetup) return;
    await _fallbackTts.setLanguage('en-US');
    await _fallbackTts.setSpeechRate(0.52);
    await _fallbackTts.setPitch(0.65);
    await _fallbackTts.awaitSpeakCompletion(false);
    _fallbackSetup = true;
  }

  // ── Split text into sentence-level chunks ─────────────────────────────────
  /// Splits a long text into chunks of ≤ [maxChars] characters.
  /// Tries to split at sentence boundaries (. ! ?) first, then at word boundaries.
  static List<String> _splitIntoChunks(
    String text, {
    int maxChars = _kMaxChunkChars,
  }) {
    if (text.length <= maxChars) return [text];

    final chunks = <String>[];
    // Sentence-level tokenization: split at . ! ? followed by space or end
    final sentenceRegex = RegExp(r'(?<=[.!?])\s+');
    final sentences = text.split(sentenceRegex);

    final buffer = StringBuffer();
    for (final sentence in sentences) {
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;

      // If single sentence exceeds limit, split it at word boundaries
      if (trimmed.length > maxChars) {
        // Flush buffer first
        if (buffer.isNotEmpty) {
          chunks.add(buffer.toString().trim());
          buffer.clear();
        }
        // Word-level split for very long sentences
        final words = trimmed.split(' ');
        final wordBuffer = StringBuffer();
        for (final word in words) {
          if (wordBuffer.length + word.length + 1 > maxChars &&
              wordBuffer.isNotEmpty) {
            chunks.add(wordBuffer.toString().trim());
            wordBuffer.clear();
          }
          if (wordBuffer.isNotEmpty) wordBuffer.write(' ');
          wordBuffer.write(word);
        }
        if (wordBuffer.isNotEmpty) chunks.add(wordBuffer.toString().trim());
        continue;
      }

      // Check if adding this sentence exceeds the limit
      final tentative = buffer.isEmpty
          ? trimmed
          : '${buffer.toString()} $trimmed';
      if (tentative.length > maxChars && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
        buffer.write(trimmed);
      } else {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(trimmed);
      }
    }

    if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
    return chunks.where((c) => c.isNotEmpty).toList();
  }

  // ── Main speak method ─────────────────────────────────────────────────────
  /// Speak text using ElevenLabs if enabled, else Flutter TTS.
  /// Splits long text into sentence chunks for seamless sequential playback.
  /// Non-blocking — returns immediately, audio plays in background.
  static Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Stop anything currently playing and clear old queue
    await stop();

    if (await isEnabled()) {
      // Split into chunks and enqueue all
      final chunks = _splitIntoChunks(trimmed);
      _queue.addAll(chunks);
      _processQueue();
    } else {
      await _setupFallback();
      // For fallback TTS, just speak the full text (TTS handles streaming internally)
      _fallbackTts.speak(trimmed);
    }
  }

  /// Process the chunk queue: speak one chunk at a time sequentially.
  static void _processQueue() {
    if (_queueRunning || _queue.isEmpty) return;
    _queueRunning = true;
    _speakNextChunk();
  }

  static Future<void> _speakNextChunk() async {
    if (_queue.isEmpty) {
      _queueRunning = false;
      return;
    }

    final chunk = _queue.removeAt(0);
    if (chunk.isEmpty) {
      _speakNextChunk(); // skip empty chunks
      return;
    }

    try {
      await _speakElevenLabsChunk(chunk);
    } catch (e) {
      debugPrint('[ElevenLabs] chunk error: $e — skipping');
      _speakNextChunk();
    }
  }

  /// Stop any ongoing speech and clear the queue.
  static Future<void> stop() async {
    _queue.clear();
    _queueRunning = false;
    _playing = false;
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _fallbackTts.stop();
    } catch (_) {}
    // Release volume key intercept
    try {
      await _volumeChannel.invokeMethod('setAudioActive', false);
    } catch (_) {}
  }

  // ── ElevenLabs API call (single chunk) ───────────────────────────────────
  static Future<void> _speakElevenLabsChunk(String chunk) async {
    try {
      // Check cache first
      final cacheKey = chunk.hashCode;
      if (_cache.containsKey(cacheKey)) {
        final cachedPath = _cache[cacheKey]!;
        if (File(cachedPath).existsSync()) {
          await _playFileAndWait(cachedPath);
          return;
        }
      }

      final key = await getApiKey();
      final voiceId = await getVoiceId();
      if (key == null || voiceId == null) {
        // Fallback TTS for this chunk
        await _setupFallback();
        await _fallbackTts.awaitSpeakCompletion(true);
        await _fallbackTts.speak(chunk);
        await Future.delayed(const Duration(milliseconds: 200));
        _speakNextChunk();
        return;
      }

      final uri = Uri.parse(
        'https://api.elevenlabs.io/v1/text-to-speech/$voiceId?optimize_streaming_latency=2',
      );

      final response = await http
          .post(
            uri,
            headers: {
              'xi-api-key': key,
              'Content-Type': 'application/json',
              'Accept': 'audio/mpeg',
            },
            body:
                '''{
  "text": ${_jsonString(chunk)},
  "model_id": "$_kModel",
  "voice_settings": {
    "stability": 0.4,
    "similarity_boost": 0.9,
    "style": 0.1,
    "use_speaker_boost": true
  }
}''',
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final audioBytes = response.bodyBytes;
        final path = await _saveToTemp(audioBytes, cacheKey);
        _cache[cacheKey] = path;
        // Keep cache small
        if (_cache.length > 10) {
          final oldest = _cache.keys.first;
          try {
            File(_cache[oldest]!).deleteSync();
          } catch (_) {}
          _cache.remove(oldest);
        }
        // Play and WAIT for completion before next chunk
        await _playFileAndWait(path);
      } else {
        debugPrint(
          '[ElevenLabs] Error ${response.statusCode}: ${response.body.substring(0, 200.clamp(0, response.body.length))}',
        );
        // Fallback to Flutter TTS on any error
        await _setupFallback();
        await _fallbackTts.awaitSpeakCompletion(true);
        await _fallbackTts.speak(chunk);
        await Future.delayed(const Duration(milliseconds: 200));
        _speakNextChunk();
      }
    } catch (e) {
      debugPrint('[ElevenLabs] chunk speak error: $e');
      await _setupFallback();
      try {
        await _fallbackTts.awaitSpeakCompletion(true);
        await _fallbackTts.speak(chunk);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
      _speakNextChunk();
    }
  }

  static Future<String> _saveToTemp(Uint8List bytes, int key) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/nova_voice_$key.mp3';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Play a file and WAIT for it to complete, then trigger the next chunk.
  static Future<void> _playFileAndWait(String path) async {
    try {
      await _player.stop();
      _playing = true;
      try {
        await _volumeChannel.invokeMethod('setAudioActive', true);
      } catch (_) {}

      final completer = Completer<void>();
      StreamSubscription? sub;
      sub = _player.onPlayerComplete.listen((_) {
        sub?.cancel();
        _playing = false;
        try {
          _volumeChannel.invokeMethod('setAudioActive', false);
        } catch (_) {}
        if (!completer.isCompleted) completer.complete();
      });

      await _player.play(DeviceFileSource(path));

      // Wait for completion (with timeout safety of 60 seconds per chunk)
      await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          sub?.cancel();
          _playing = false;
        },
      );

      // Small gap between chunks for natural speech rhythm
      if (_queue.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 120));
      }

      // Proceed to the next chunk
      _speakNextChunk();
    } catch (e) {
      debugPrint('[ElevenLabs] playFileAndWait error: $e');
      _playing = false;
      try {
        _volumeChannel.invokeMethod('setAudioActive', false);
      } catch (_) {}
      _speakNextChunk();
    }
  }

  /// Encode text as a JSON string (handles quotes, backslashes, newlines).
  static String _jsonString(String text) {
    final escaped = text
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', ' ')
        .replaceAll('\r', '');
    return '"$escaped"';
  }

  /// Test the ElevenLabs connection — returns error message or null on success.
  static Future<String?> testConnection() async {
    final key = await getApiKey();
    final voiceId = await getVoiceId();
    if (key == null) return 'No API key set.';
    if (voiceId == null) return 'No Voice ID set.';

    try {
      final response = await http
          .get(
            Uri.parse('https://api.elevenlabs.io/v1/voices/$voiceId'),
            headers: {'xi-api-key': key},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        await speak('Online and ready, sir.');
        return null; // success
      }
      if (response.statusCode == 401) return 'Invalid API key.';
      if (response.statusCode == 404)
        return 'Voice ID not found. Double-check your Voice ID.';
      return 'Error ${response.statusCode}. Check your key and voice ID.';
    } catch (e) {
      return 'Connection failed: ${e.toString().split('\n').first}';
    }
  }

  static bool get isPlaying => _playing;
}
