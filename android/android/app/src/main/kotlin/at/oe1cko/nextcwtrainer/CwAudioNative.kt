package at.oe1cko.nextcwtrainer

object CwAudioNative {
    init {
        System.loadLibrary("cw_audio")
    }

    external fun startStream(): Int
    external fun stopStream()
    // Closes and reopens the stream against the current setPreferredDeviceId()
    // value — needed because AAudio doesn't re-route an already-open stream
    // when the output device changes (see cw_tone_jni.cpp errorCallback).
    external fun restartStream(): Int
    external fun setPreferredDeviceId(deviceId: Int)
    external fun setPlaying(on: Boolean)
    external fun setFreqHz(hz: Double)
    external fun setVolume(vol: Float)
    external fun setEnvelopeMs(ms: Float)
    // Interference on the other station's signal, levels 0..1 (QRM is accepted
    // but not generated yet; filter = receiver filter narrowness, color = noise treble cut-off).
    external fun setInterference(noise: Float, qrm: Float, qsb: Float, drift: Float, filter: Float, color: Float)
    // True while CwGenerator plays the other station; the user's own keying
    // never gets interference.
    external fun setRx(on: Boolean)
    // Screen-level switch: band noise and QRM keep running, also under the
    // user's own keying (the sidetone itself stays clean).
    external fun setAmbient(on: Boolean)
    external fun getLatencyMs(): Int
}
