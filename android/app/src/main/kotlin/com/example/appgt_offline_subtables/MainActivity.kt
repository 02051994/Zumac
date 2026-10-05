package com.example.appgt_offline_subtables

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val SCANNER_FEEDBACK_CHANNEL = "zumac/scanner_feedback"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SCANNER_FEEDBACK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "playScannerTone") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val accepted = call.argument<Boolean>("accepted") == true
            result.success(playScannerTone(accepted))
        }
    }

    private fun playScannerTone(accepted: Boolean): Boolean {
        return try {
            val durationMs = if (accepted) 220 else 650
            val tone = if (accepted) {
                ToneGenerator.TONE_PROP_ACK
            } else {
                ToneGenerator.TONE_SUP_ERROR
            }
            val generator = ToneGenerator(AudioManager.STREAM_MUSIC, 100)
            val started = generator.startTone(tone, durationMs)
            Handler(Looper.getMainLooper()).postDelayed(
                { generator.release() },
                durationMs.toLong() + 120L,
            )
            started
        } catch (_: RuntimeException) {
            false
        }
    }
}
