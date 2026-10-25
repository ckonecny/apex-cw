package at.oe1cko.nextcwtrainer

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Spoken spelling-alphabet samples for the audio trainer (#139): a-z, 0-9 and
 * nine punctuation words (. , : - / = ? @ +), one short Ogg/Opus file per
 * character and voice (res/raw/voice_<voice>_<key>, key = the character or
 * the name in [KEYS],
 * made by tools/make_voice_samples.py). Its own SoundPool and its own volume,
 * so the sidetone and the shared generator are never touched (CLAUDE.md rule 2).
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
    private val samples = HashMap<Char, Sample>()
    private val main = Handler(Looper.getMainLooper())
    private var stream = 0
    private var pending: Runnable? = null
    private var pendingResult: MethodChannel.Result? = null

    /** Loads all samples of [name]; [done] gets true when all are ready. */
    fun load(name: String, done: (Boolean) -> Unit) {
        if (voice == name && samples.size == KEYS.size) { done(true); return }
        stop()
        samples.values.forEach { pool.unload(it.soundId) }
        samples.clear()
        voice = null
        val ids = HashMap<Int, Char>()
        var remaining = 0
        pool.setOnLoadCompleteListener { _, id, status ->
            main.post {
                if (!ids.containsKey(id)) return@post
                if (status != 0) { ids.clear(); done(false); return@post }
                remaining--
                if (remaining == 0) { voice = name; done(true) }
            }
        }
        for ((c, key) in KEYS) {
            val res = context.resources.getIdentifier("voice_${name}_$key", "raw", context.packageName)
            if (res == 0) { done(false); return }
            val dur = durationMs(res)
            val id = pool.load(context, res, 1)
            ids[id] = c
            samples[c] = Sample(id, dur)
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

    fun play(char: String, result: MethodChannel.Result) {
        val s = samples[char.lowercase().firstOrNull() ?: ' ']
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
        /** Character -> file-name key (letters and digits are their own key). */
        private val KEYS: Map<Char, String> =
            ('a'..'z').associateWith { it.toString() } +
            ('0'..'9').associateWith { it.toString() } +
            mapOf('.' to "period", ',' to "comma", ':' to "colon", '-' to "dash",
                '/' to "slash", '=' to "equals", '?' to "question", '@' to "at", '+' to "plus")
    }
}
