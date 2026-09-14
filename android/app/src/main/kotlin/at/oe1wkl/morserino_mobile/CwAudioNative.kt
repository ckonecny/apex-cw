package at.oe1wkl.morserino_mobile

object CwAudioNative {
    init {
        System.loadLibrary("cw_audio")
    }

    external fun startStream(): Int
    external fun stopStream()
    external fun setPlaying(on: Boolean)
    external fun setFreqHz(hz: Double)
    external fun setVolume(vol: Float)
    external fun setEnvelopeMs(ms: Float)
    external fun getLatencyMs(): Int
}
