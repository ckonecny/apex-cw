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

    // Called directly by CwKeyer/CwGenerator (no MethodChannel in the hot
    // path). Keying owns the audio: a running game sound effect stops at once
    // (MorseGame.cpp updateSound() drops its effect when the keyer leaves IDLE).
    fun setPlaying(on: Boolean) {
        if (on) cancelEffect()
        CwAudioNative.setPlaying(on)
    }

    // Game sound effects (Morse Invaders): a short note sequence, back to back
    // like MorseGame.cpp's startSound()/updateSound(). A new effect replaces
    // a running one; keying cancels it (setPlaying above).
    private val effectLock = Any()
    private var effectGen = 0
    private var effectActive = false

    fun playEffect(notes: List<Pair<Double, Long>>) {
        if (notes.isEmpty()) return
        val gen = synchronized(effectLock) { effectActive = true; ++effectGen }
        Thread({
            for ((f, ms) in notes) {
                synchronized(effectLock) {
                    if (effectGen != gen) return@Thread
                    CwAudioNative.setFreqHz(f)
                    CwAudioNative.setPlaying(true)
                }
                Thread.sleep(ms)
            }
            synchronized(effectLock) {
                if (effectGen != gen) return@Thread
                effectActive = false
                CwAudioNative.setPlaying(false)
                CwAudioNative.setFreqHz(lastFreqHz)
            }
        }, "game-effect").apply { isDaemon = true; start() }
    }

    fun cancelEffect() {
        synchronized(effectLock) {
            if (!effectActive) return
            effectActive = false
            effectGen++
            CwAudioNative.setPlaying(false)
            CwAudioNative.setFreqHz(lastFreqHz)
        }
    }

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
            "playEffect" -> {
                // [[freqHz, ms], ...]
                val notes = (call.arguments as? List<*>).orEmpty().mapNotNull { n ->
                    val l = n as? List<*> ?: return@mapNotNull null
                    val f = (l.getOrNull(0) as? Number)?.toDouble() ?: return@mapNotNull null
                    val ms = (l.getOrNull(1) as? Number)?.toLong() ?: return@mapNotNull null
                    f to ms
                }
                playEffect(notes)
                result.success(null)
            }
            "stopEffect" -> { cancelEffect(); result.success(null) }
            // CW decoder monitor tone: follows the decoded tone on/off.
            "setPlaying" -> { setPlaying(call.arguments as? Boolean ?: false); result.success(null) }
            else        -> result.notImplemented()
        }
    }
}
