package at.oe1cko.nextcwtrainer

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log

/**
 * Microphone capture for the CW decoder (backlog #8). Only delivers raw PCM16
 * mono chunks; the Goertzel tone detection and the decoder itself run in Dart
 * (lib/keyer/cw_audio_decoder.dart), so they can be tested with synthesized
 * audio.
 *
 * Prefers the UNPROCESSED source (no AGC / noise suppression, which would
 * pump or chop a steady CW tone), then VOICE_RECOGNITION (AGC off on most
 * devices), then plain MIC.
 */
class MicInput(private val context: Context) {

    companion object {
        private const val TAG = "MicInput"
        const val SAMPLE_RATE = 16000
        private const val CHUNK = 320          // 20 ms
    }

    /** Called on the capture thread with little-endian PCM16 bytes. */
    var onPcm: ((ByteArray) -> Unit)? = null

    @Volatile private var running = false
    private var thread: Thread? = null
    private var record: AudioRecord? = null

    val isRunning get() = running

    private fun sources(): List<Int> {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val unprocessed = am.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true"
        return listOfNotNull(
            if (unprocessed) MediaRecorder.AudioSource.UNPROCESSED else null,
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            MediaRecorder.AudioSource.MIC)
    }

    /** Returns the sample rate on success, or 0 if no source could be opened. */
    @SuppressLint("MissingPermission")   // checked by the caller (MainActivity)
    @Synchronized
    fun start(): Int {
        if (running) return SAMPLE_RATE
        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minBuf <= 0) return 0
        var rec: AudioRecord? = null
        for (src in sources()) {
            try {
                val r = AudioRecord(src, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, maxOf(minBuf, CHUNK * 8))
                if (r.state == AudioRecord.STATE_INITIALIZED) { rec = r; Log.i(TAG, "source $src"); break }
                r.release()
            } catch (e: Exception) {
                Log.w(TAG, "source $src failed: $e")
            }
        }
        if (rec == null) return 0
        record = rec
        rec.startRecording()
        running = true
        thread = Thread({
            val buf = ShortArray(CHUNK)
            while (running) {
                val n = rec.read(buf, 0, CHUNK)
                if (n <= 0) continue
                val bytes = ByteArray(n * 2)
                for (i in 0 until n) {
                    val v = buf[i].toInt()
                    bytes[2 * i] = (v and 0xFF).toByte()
                    bytes[2 * i + 1] = ((v shr 8) and 0xFF).toByte()
                }
                onPcm?.invoke(bytes)
            }
        }, "mic-input").apply { priority = Thread.MAX_PRIORITY; isDaemon = true; start() }
        return SAMPLE_RATE
    }

    @Synchronized
    fun stop() {
        if (!running) return
        running = false
        thread?.join(500)
        thread = null
        record?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        record = null
    }
}
