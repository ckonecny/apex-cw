package at.oe1cko.nextcwtrainer

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Spoken samples for the audio trainer (#139): a-z, 0-9, nine punctuation
 * words (. , : - / = ? @ +), ten prosign meanings and the words "Pro sign",
 * one short Ogg/Opus file per sample and voice (res/raw/voice_<voice>_<key>,
 * made by tools/make_voice_samples.py), plus three voice-independent tones
 * that can introduce a prosign (res/raw/prosign_tone_<name>.wav, made by
 * tools/make_prosign_tones.py). The keys come from Dart (`voiceSampleKey`).
 * Its own SoundPool and its own volume, so the sidetone and the shared
 * generator are never touched (CLAUDE.md rule 2).
 *
 * [play] answers the channel call when the sample has ended (its duration
 * is read once when the voice is loaded), or at once when [stop] is called.
 */
class VoiceSamples(private val context: Context) {

    /** Playback level 0..1 (the audio trainer's own setting, not the sidetone's). */
    @Volatile var volume = 0.7f

    private val pool: SoundPool = SoundPool.Builder()
        .setMaxStreams(1)
        .setAudioAttributes(AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build())
        .build()

    private class Sample(val soundId: Int, val durationMs: Long)

    private var voice: String? = null
    private val samples = HashMap<String, Sample>()
    private val main = Handler(Looper.getMainLooper())
    private var stream = 0
    private var pending: Runnable? = null
    private var pendingResult: MethodChannel.Result? = null

    /** Loads all samples and tones of [name]; [done] gets true when all are ready. */
    fun load(name: String, done: (Boolean) -> Unit) {
        if (voice == name && samples.size == KEYS.size) { done(true); return }
        stop()
        samples.values.forEach { pool.unload(it.soundId) }
        samples.clear()
        voice = null
        val ids = HashMap<Int, String>()
        var remaining = 0
        pool.setOnLoadCompleteListener { _, id, status ->
            main.post {
                if (!ids.containsKey(id)) return@post
                if (status != 0) { ids.clear(); done(false); return@post }
                remaining--
                if (remaining == 0) { voice = name; done(true) }
            }
        }
        for (key in KEYS) {
            val file = if (key.startsWith("tone_")) "prosign_$key" else "voice_${name}_$key"
            val res = context.resources.getIdentifier(file, "raw", context.packageName)
            if (res == 0) { done(false); return }
            val dur = durationMs(res)
            val id = pool.load(context, res, 1)
            ids[id] = key
            samples[key] = Sample(id, dur)
            remaining++
        }
    }

    private fun durationMs(res: Int): Long {
        val r = MediaMetadataRetriever()
        return try {
            context.resources.openRawResourceFd(res).use { r.setDataSource(it.fileDescriptor, it.startOffset, it.length) }
            r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 800L
        } catch (_: Exception) { 800L } finally { r.release() }
    }

    fun play(key: String, result: MethodChannel.Result) {
        val s = samples[key]
        if (s == null) { result.success(null); return }
        stop()
        val v = volume.coerceIn(0f, 1f)
        stream = pool.play(s.soundId, v, v, 1, 0, 1f)
        val finish = Runnable { pending = null; pendingResult = null; result.success(null) }
        pending = finish
        pendingResult = result
        // + a short tail so the sample is not cut by the next call
        main.postDelayed(finish, s.durationMs + 60)
    }

    /** Stops the running sample and answers its pending call. */
    fun stop() {
        if (stream != 0) { pool.stop(stream); stream = 0 }
        pending?.let { main.removeCallbacks(it) }
        pendingResult?.success(null)
        pending = null
        pendingResult = null
    }

    fun release() { stop(); pool.release() }

    companion object {
        /** Sample keys: letters, digits, symbol names, prosigns, tones. */
        private val KEYS: List<String> =
            ('a'..'z').map { it.toString() } + ('0'..'9').map { it.toString() } +
            listOf("period", "comma", "colon", "dash", "slash", "equals", "question", "at", "plus") +
            listOf("prosign_word", "prosign_as", "prosign_ka", "prosign_kn", "prosign_sk", "prosign_ve", "prosign_bk",
                   "prosign_ar", "prosign_bt", "prosign_hh", "prosign_sos") +
            listOf("tone_bell", "tone_harp", "tone_gong")
    }
}
