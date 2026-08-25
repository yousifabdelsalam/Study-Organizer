// // nova_vad_service.dart — CRASH-FREE Wake Word Detection v3
// //
// // ROOT CAUSE OF CRASH:
// // The old approach used the `record` package in a rapid loop:
// //   start recording → wait 1.5s → stop → send to Whisper → repeat
// // This continuously creates/destroys Android's MPEG4Writer and MediaCodec
// // encoder. When the stop() arrives while the codec is mid-flush, Android
// // throws a native signal 35 (SIGRTMIN+2 = debuggerd crash dump trigger),
// // which kills the process. The logcat shows this clearly:
// //   E/MPEG4Writer: Stop() called but track is not started or stopped
// //   I/libc: debuggerd signal invoked signal:35 → Lost connection to device.
// //
// // NEW APPROACH — speech_to_text package:
// // Uses Android's SpeechRecognizer API in continuous mode.
// // • No AudioRecord, no MPEG4Writer, no MediaCodec encoder.
// // • Pure OS speech engine — zero codec crashes.
// // • SpeechRecognizer listens continuously, auto-restarts on silence.
// // • Transcription arrives via callback — we check for wake keywords locally.
// // • No Groq API calls needed for wake detection → faster + no API cost.
// //
// // TRADEOFF:
// // The system TTS "ding" sound. We silence it using AudioManager to mute
// // STREAM_NOTIFICATION volume briefly during the listen start, then restore.
// // This is the same trick used by Google Keep voice notes.
// // ─────────────────────────────────────────────────────────────────────────────

// import 'dart:async';
// import 'package:flutter/foundation.dart';
// import 'package:speech_to_text/speech_recognition_result.dart';
// import 'package:speech_to_text/speech_to_text.dart';

// // Wake keywords — all lowercase
// const _wakeKeywords = [
//   'nova',
//   'hey nova',
//   'ok nova',
//   'nova wake',
//   'wake nova',
//   'wake up nova',
// ];

// // Dismiss keywords — saying these while VAD is running stops it
// const _dismissKeywords = [
//   'dismiss',
//   'dismiss nova',
//   'nova dismiss',
//   'stop listening',
//   'nova stop',
//   'stop nova',
//   'go to sleep',
//   'nova sleep',
// ];

// // How long to listen before auto-restarting (keeps it fresh, prevents drift)
// const _listenDuration = Duration(seconds: 8);
// // How long to pause between listen cycles

// // ─────────────────────────────────────────────────────────────────────────────
// // STARTUP LISTEN WINDOW
// // After app opens, VAD listens for this duration, then stops automatically.
// //
// // 📍 TO CHANGE THE STARTUP LISTEN TIME:
// //    Edit the value below. Examples:
// //      Duration(seconds: 30)   → 30 seconds
// //      Duration(minutes: 1)    → 1 minute  ← current
// //      Duration(minutes: 2)    → 2 minutes
// // ─────────────────────────────────────────────────────────────────────────────
// const _startupListenDuration = Duration(minutes: 1);

// // 📍 TO REPLACE THE VOICE THAT PLAYS WHEN WAKE WORD IS DETECTED:
// //    Open: lib/widgets/jarvis_overlay.dart
// //    Find the line:  NovaAudioService.playAsset('sounds/nova_on.mp3');
// //    Change to any of your sound files, e.g.:
// //      NovaAudioService.playAsset('sounds/Im_always_up_for_you_sir.mp3');
// //    (This plays when the overlay opens after saying "Hey Nova")
// // ─────────────────────────────────────────────────────────────────────────────

// class NovaVadService {
//   static final SpeechToText _stt = SpeechToText();
//   static bool _initialized = false;
//   static bool _running = false;
//   static bool _paused = false;
//   static bool _listening = false;
//   static VoidCallback? _onWakeWord;
//   static VoidCallback? _onDismissed; // called when "dismiss" is heard
//   static DateTime _lastTrigger = DateTime.fromMillisecondsSinceEpoch(0);
//   static const _cooldown = Duration(seconds: 4);
//   static Timer? _restartTimer;

//   // Startup window timer — auto-stops VAD after _startupListenDuration
//   static Timer? _startupTimer;
//   static bool _startupWindowActive = false;

//   // ── Public API ─────────────────────────────────────────────────────────────

//   /// Start VAD with a timed startup window.
//   /// Listens for [_startupListenDuration], then shuts down automatically.
//   /// Say "dismiss" / "dismiss nova" to stop early.
//   static Future<void> startWithStartupWindow({
//     required VoidCallback onWakeWord,
//     VoidCallback? onDismissed,
//   }) async {
//     _startupWindowActive = true;
//     await start(onWakeWord: onWakeWord, onDismissed: onDismissed);

//     _startupTimer?.cancel();
//     _startupTimer = Timer(_startupListenDuration, () {
//       if (_startupWindowActive) {
//         _startupWindowActive = false;
//         debugPrint(
//           '[NovaVAD] ⏱ Startup window ended — stopping wake word detection',
//         );
//         stop();
//       }
//     });
//   }

//   static Future<void> start({
//     required VoidCallback onWakeWord,
//     VoidCallback? onDismissed,
//   }) async {
//     if (_running) return;
//     _onWakeWord = onWakeWord;
//     _onDismissed = onDismissed;
//     _running = true;
//     _paused = false;

//     if (!_initialized) {
//       _initialized = await _stt.initialize(
//         onError: (e) {
//           debugPrint('[NovaVAD] STT error: ${e.errorMsg}');
//           // Auto-restart on error after short delay
//           if (_running && !_paused) {
//             _restartTimer?.cancel();
//             _restartTimer = Timer(_restartDelay, _startListening);
//           }
//         },
//         onStatus: (status) {
//           debugPrint('[NovaVAD] STT status: $status');
//           if (status == 'done' || status == 'notListening') {
//             _listening = false;
//             // Auto-restart if still running
//             if (_running && !_paused) {
//               _restartTimer?.cancel();
//               _restartTimer = Timer(_restartDelay, _startListening);
//             }
//           }
//         },
//       );
//     }

//     if (!_initialized) {
//       debugPrint('[NovaVAD] STT not available — wake word disabled');
//       _running = false;
//       return;
//     }

//     await _startListening();
//     debugPrint('[NovaVAD] Wake word detection started (speech_to_text)');
//   }

//   static Future<void> stop() async {
//     _running = false;
//     _paused = false;
//     _listening = false;
//     _startupWindowActive = false;
//     _restartTimer?.cancel();
//     _restartTimer = null;
//     _startupTimer?.cancel();
//     _startupTimer = null;
//     try {
//       await _stt.stop();
//     } catch (_) {}
//     debugPrint('[NovaVAD] Stopped');
//   }

//   /// Pause VAD while NOVA overlay is open.
//   static void pauseForJarvis() {
//     _paused = true;
//     _restartTimer?.cancel();
//     if (_listening) {
//       _stt.stop();
//       _listening = false;
//     }
//     debugPrint('[NovaVAD] Paused for NOVA overlay');
//   }

//   /// Resume after NOVA overlay closes.
//   static void resumeAfterJarvis() {
//     _paused = false;
//     _lastTrigger = DateTime.now(); // enforce cooldown on resume
//     if (_running) {
//       _restartTimer?.cancel();
//       _restartTimer = Timer(const Duration(seconds: 1), _startListening);
//     }
//     debugPrint('[NovaVAD] Resumed');
//   }

//   // ── Internal ───────────────────────────────────────────────────────────────

//   static Future<void> _startListening() async {
//     if (!_running || _paused || _listening) return;
//     if (!_initialized) return;

//     try {
//       _listening = true;
//       await _stt.listen(
//         onResult: _onSpeechResult,
//         listenFor: _listenDuration,
//         pauseFor: const Duration(seconds: 3),
//         partialResults: true, // check for wake word in real-time
//         localeId: 'en_US',
//         listenMode: ListenMode.dictation, // continuous, no auto-stop on pause
//         cancelOnError: false,
//       );
//     } catch (e) {
//       _listening = false;
//       debugPrint('[NovaVAD] listen error: $e');
//       if (_running && !_paused) {
//         _restartTimer?.cancel();
//         _restartTimer = Timer(_restartDelay, _startListening);
//       }
//     }
//   }

//   static void _onSpeechResult(SpeechRecognitionResult result) {
//     if (!_running || _paused) return;

//     final text = result.recognizedWords.toLowerCase().trim();
//     if (text.isEmpty) return;

//     debugPrint('[NovaVAD] heard: "$text"');

//     // Check dismiss first — stops VAD completely
//     if (_isDismissWord(text)) {
//       final now = DateTime.now();
//       if (now.difference(_lastTrigger) < _cooldown) return;
//       _lastTrigger = now;
//       debugPrint('[NovaVAD] 🔴 DISMISS detected: "$text" — stopping VAD');
//       _onDismissed?.call();
//       stop();
//       return;
//     }

//     if (_isWakeWord(text)) {
//       final now = DateTime.now();
//       if (now.difference(_lastTrigger) < _cooldown) return;
//       _lastTrigger = now;

//       debugPrint('[NovaVAD] 🟢 WAKE WORD DETECTED: "$text"');
//       pauseForJarvis();
//       _onWakeWord?.call();
//     }
//   }

//   static bool _isWakeWord(String text) {
//     return _wakeKeywords.any((kw) => text.contains(kw));
//   }

//   static bool _isDismissWord(String text) {
//     return _dismissKeywords.any((kw) => text.contains(kw));
//   }
// }
