package com.example.study_organizer

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {

    // ─────────────────────────────────────────────────────────────────────────
    // CHANNEL NAMES
    // ─────────────────────────────────────────────────────────────────────────
    private val VOLUME_CHANNEL  = "com.example.study_organizer/volume_key"
    private val VAD_CHANNEL     = "com.example.study_organizer/vad"      // MethodChannel
    private val VAD_EVENT_CHANNEL = "com.example.study_organizer/vad_events" // EventChannel

    private var volumeChannel: MethodChannel? = null
    private var vadChannel: MethodChannel? = null
    private var vadEventSink: EventChannel.EventSink? = null
    private var novaAudioActive = false

    // ─────────────────────────────────────────────────────────────────────────
    // NATIVE VAD — AudioRecord reads raw PCM silently (NO system ding/beep)
    // Because we use AudioRecord directly (not SpeechRecognizer / MediaRecorder)
    // Android never plays any UI sounds. The mic opens once and stays open
    // until Flutter calls "vad_stop". Flutter receives "voice_detected" events
    // via the EventChannel, then decides whether to run a Whisper burst.
    // ─────────────────────────────────────────────────────────────────────────
    private var audioRecord: AudioRecord? = null
    private var vadThread: Thread? = null
    @Volatile private var vadRunning = false

    // VAD tuning — adjust if too sensitive or not sensitive enough
    private val SAMPLE_RATE      = 16000          // Hz  — matches Whisper's preferred rate
    private val FRAME_MS         = 30             // ms per analysis frame
    private val FRAME_SIZE       = SAMPLE_RATE * FRAME_MS / 1000  // 480 samples
    private val RMS_THRESHOLD    = 600.0          // RMS amplitude threshold (0–32768 range)
    private val VOICE_FRAMES_REQ = 3              // consecutive loud frames before signalling
    private val SILENCE_FRAMES_RESET = 15         // frames of silence before resetting counter

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Volume key channel (from previous fix) ────────────────────────────
        volumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL)
        volumeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setAudioActive" -> { novaAudioActive = call.arguments as? Boolean ?: false; result.success(null) }
                else -> result.notImplemented()
            }
        }

        // ── VAD control channel (start / stop from Flutter) ───────────────────
        vadChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VAD_CHANNEL)
        vadChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "vad_start" -> { startVAD(); result.success(null) }
                "vad_stop"  -> { stopVAD();  result.success(null) }
                else -> result.notImplemented()
            }
        }

        // ── VAD event stream (native → Flutter: "voice_detected") ─────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, VAD_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { vadEventSink = sink }
                override fun onCancel(args: Any?) { vadEventSink = null }
            })
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VAD IMPLEMENTATION
    // ─────────────────────────────────────────────────────────────────────────
    private fun startVAD() {
        if (vadRunning) return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) return

        val bufSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            .coerceAtLeast(FRAME_SIZE * 2)

        val ar = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,  // uses hardware noise suppression
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufSize
        )

        if (ar.state != AudioRecord.STATE_INITIALIZED) {
            ar.release()
            return
        }

        audioRecord = ar
        vadRunning  = true
        ar.startRecording()

        vadThread = Thread {
            val buffer     = ShortArray(FRAME_SIZE)
            var voiceCount = 0
            var silCount   = 0

            while (vadRunning) {
                val read = ar.read(buffer, 0, FRAME_SIZE)
                if (read <= 0) continue

                // RMS energy of the frame
                var sum = 0.0
                for (i in 0 until read) sum += buffer[i].toLong() * buffer[i].toLong()
                val rms = sqrt(sum / read)

                if (rms > RMS_THRESHOLD) {
                    silCount = 0
                    voiceCount++
                    if (voiceCount == VOICE_FRAMES_REQ) {
                        // Send event to Flutter on the main thread
                        runOnUiThread { vadEventSink?.success("voice_detected") }
                    }
                } else {
                    voiceCount = 0
                    silCount++
                    // After enough silence, reset so we're ready for the next utterance
                    if (silCount >= SILENCE_FRAMES_RESET) silCount = 0
                }
            }

            ar.stop()
            ar.release()
        }.also { it.isDaemon = true; it.start() }
    }

    private fun stopVAD() {
        vadRunning = false
        vadThread  = null
        audioRecord = null
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VOLUME KEYS
    // ─────────────────────────────────────────────────────────────────────────
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (novaAudioActive) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> { volumeChannel?.invokeMethod("onVolumeDown", null); return true }
                KeyEvent.KEYCODE_VOLUME_UP   -> { volumeChannel?.invokeMethod("volumeUp", null);     return true }
            }
        }
        return super.onKeyDown(keyCode, event)
    }
}