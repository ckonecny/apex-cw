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
    external fun getLatencyMs(): Int
}
