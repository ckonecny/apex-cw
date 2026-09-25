package at.oe1cko.nextcwtrainer

import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CwTonePlugin(private val channel: MethodChannel) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "at.oe1cko.nextcwtrainer/cw_tone"
        private const val TAG = "CwTonePlugin"
    }

    // Tracks the sidetone pitch so playConfirmTone() can restore it afterward.
    @Volatile private var lastFreqHz = 600.0

    init {
        channel.setMethodCallHandler(this)
        val res = CwAudioNative.startStream()
        if (res != 0) Log.e(TAG, "AAudio startStream failed: $res")
        else Log.i(TAG, "AAudio started — hw latency ~${CwAudioNative.getLatencyMs()} ms")
    }

    // Called directly by CwKeyer (no MethodChannel in the hot path)
    fun setPlaying(on: Boolean) = CwAudioNative.setPlaying(on)

    /**
     * Echo Trainer "Confrm. Tone" — mirrors MorseOutput::soundSignalOK/ERR exactly:
     * OK = 440Hz/97ms then 587Hz/193ms (rising); ERR = 366Hz/97ms then 330Hz/193ms (falling).
     */
    fun playConfirmTone(ok: Boolean) {
        val restoreFreq = lastFreqHz
        val f1 = if (ok) 440.0 else 366.0
        val f2 = if (ok) 587.0 else 330.0
        Thread({
            CwAudioNative.setFreqHz(f1)
            CwAudioNative.setPlaying(true)
            Thread.sleep(97)
            CwAudioNative.setPlaying(false)
            CwAudioNative.setFreqHz(f2)
            CwAudioNative.setPlaying(true)
            Thread.sleep(193)
            CwAudioNative.setPlaying(false)
            CwAudioNative.setFreqHz(restoreFreq)
        }, "confirm-tone").apply { isDaemon = true; start() }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setFreq"   -> {
                lastFreqHz = (call.arguments as? Number)?.toDouble() ?: 600.0
                CwAudioNative.setFreqHz(lastFreqHz)
                result.success(null)
            }
            "setVolume" -> {
                CwAudioNative.setVolume((call.arguments as? Number)?.toFloat() ?: 0.7f)
                result.success(null)
            }
            "setEnvelopeMs" -> {
                CwAudioNative.setEnvelopeMs((call.arguments as? Number)?.toFloat() ?: 5.0f)
                result.success(null)
            }
            "playConfirmTone" -> {
                playConfirmTone(call.arguments as? Boolean ?: true)
                result.success(null)
            }
            else        -> result.notImplemented()
        }
    }
}
