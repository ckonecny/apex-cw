package at.oe1cko.nextcwtrainer

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class CwTonePlugin(context: Context, private val channel: MethodChannel) : MethodChannel.MethodCallHandler, KeySink, GenTone {

    companion object {
        const val CHANNEL = "at.oe1cko.nextcwtrainer/cw_tone"
        private const val TAG = "CwTonePlugin"

        // Confirmation tone styles, same numbers as ConfirmTone in
        // lib/util/confirm_tone.dart (0 = off never reaches this side).
        const val STYLE_CLASSIC = 1
        const val STYLE_MARIMBA = 2
        const val STYLE_SANFT = 3
    }

    // Tracks the sidetone pitch so playConfirmTone() can restore it afterward.
    @Volatile private var lastFreqHz = 600.0

    // Follows setVolume: the Marimba/Sanft sounds play at the sidetone volume
    // (their level against the Morse tone is baked into the files, see
    // tools/make_confirm_tones.py). 0.7 = the native default.
    @Volatile private var volume = 0.7f

    // Marimba and Sanft are short recordings synthesised by
    // tools/make_confirm_tones.py (res/raw). Their own voice (SoundPool), so
    // they never touch the sidetone's pitch or state (CLAUDE.md rule 2). Not
    // yet loaded when played = silent for that one call.
    private val soundPool: SoundPool = SoundPool.Builder()
        .setMaxStreams(2)
        .setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build())
        .build()
    // style -> (right, wrong) sound ids
    private val confirmSounds: Map<Int, Pair<Int, Int>> = mapOf(
        STYLE_MARIMBA to (soundPool.load(context, R.raw.confirm_marimba_ok, 1) to
            soundPool.load(context, R.raw.confirm_marimba_err, 1)),
        STYLE_SANFT to (soundPool.load(context, R.raw.confirm_sanft_ok, 1) to
            soundPool.load(context, R.raw.confirm_sanft_err, 1)),
    )
    @Volatile private var confirmStream = 0

    // Timing jitter ("bad fist") of the other station, 0..1; read by CwGenerator.
    @Volatile override var jitter = 0f

    init {
        channel.setMethodCallHandler(this)
        val res = CwAudioNative.startStream()
        if (res != 0) Log.e(TAG, "AAudio startStream failed: $res")
        else Log.i(TAG, "AAudio started — hw latency ~${CwAudioNative.getLatencyMs()} ms")
    }

    // Called directly by CwKeyer/CwGenerator (no MethodChannel in the hot
    // path). Keying owns the audio: a running game sound effect stops at once
    // (MorseGame.cpp updateSound() drops its effect when the keyer leaves IDLE).
    override fun setPlaying(on: Boolean) {
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
     * Confirmation tone in the style the user picked. [STYLE_CLASSIC] is the
     * firmware tone (below); Marimba and Sanft are the SoundPool sounds.
     */
    fun playConfirmTone(ok: Boolean, style: Int = STYLE_CLASSIC) {
        val ids = confirmSounds[style]
        if (ids == null) {
            playClassicConfirmTone(ok)
            return
        }
        if (confirmStream != 0) soundPool.stop(confirmStream)
        val v = volume.coerceIn(0f, 1f)
        confirmStream = soundPool.play(if (ok) ids.first else ids.second, v, v, 1, 0, 1f)
    }

    /**
     * Echo Trainer "Confrm. Tone" — mirrors MorseOutput::soundSignalOK/ERR exactly:
     * OK = 440Hz/97ms then 587Hz/193ms (rising); ERR = 366Hz/97ms then 330Hz/193ms (falling).
     */
    private fun playClassicConfirmTone(ok: Boolean) {
        val restoreFreq = lastFreqHz
        val f1 = if (ok) 440.0 else 366.0
        val f2 = if (ok) 587.0 else 330.0
        Thread({
            CwAudioNative.setClean(true)
            CwAudioNative.setFreqHz(f1)
            CwAudioNative.setPlaying(true)
            Thread.sleep(97)
            CwAudioNative.setPlaying(false)
            CwAudioNative.setFreqHz(f2)
            CwAudioNative.setPlaying(true)
            Thread.sleep(193)
            CwAudioNative.setPlaying(false)
            Thread.sleep(60)   // let the release tail finish before the limiter is back
            CwAudioNative.setClean(false)
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
                volume = (call.arguments as? Number)?.toFloat() ?: 0.7f
                CwAudioNative.setVolume(volume)
                result.success(null)
            }
            "setEnvelopeMs" -> {
                CwAudioNative.setEnvelopeMs((call.arguments as? Number)?.toFloat() ?: 5.0f)
                result.success(null)
            }
            // [noise, qrm, qsb, drift, jitter, filter], each 0..1. Global user setting
            // pushed at app start and on change; the generator's rx flag
            // decides when it is audible.
            "setInterference" -> {
                val a = (call.arguments as? List<*>).orEmpty()
                    .map { (it as? Number)?.toFloat() ?: 0f }
                fun v(i: Int) = a.getOrElse(i) { 0f }.coerceIn(0f, 1f)
                CwAudioNative.setInterference(v(0), v(1), v(2), v(3), v(5), v(6))
                jitter = v(4)
                result.success(null)
            }
            "setAmbient" -> {
                CwAudioNative.setAmbient(call.arguments as? Boolean ?: false)
                result.success(null)
            }
            "playConfirmTone" -> {
                // {ok: Boolean, style: Int}; a bare Boolean = the classic tone.
                val a = call.arguments
                if (a is Map<*, *>) {
                    playConfirmTone(a["ok"] as? Boolean ?: true,
                        (a["style"] as? Number)?.toInt() ?: STYLE_CLASSIC)
                } else {
                    playConfirmTone(a as? Boolean ?: true)
                }
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
