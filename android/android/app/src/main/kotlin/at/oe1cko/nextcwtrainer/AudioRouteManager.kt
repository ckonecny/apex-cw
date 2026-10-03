package at.oe1cko.nextcwtrainer

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.util.Log

/**
 * Keeps the AAudio sidetone stream bound to the right output device as USB
 * audio adapters or Bluetooth headsets come and go. AAudio does not re-route
 * an already-open stream by itself (see cw_tone_jni.cpp errorCallback) — every
 * device change needs an explicit stream restart, which this class drives.
 */
class AudioRouteManager(
    private val context: Context,
    private val onRouteChanged: (String) -> Unit,
) {
    companion object {
        private const val TAG = "AudioRouteManager"
        private const val PREFS_NAME = "next_cw_trainer_prefs"
        private const val PREF_OUTPUT_KIND = "audio_output_kind"

        // Persisted preference categories — stable across reconnects, unlike
        // AudioDeviceInfo ids, which Android reassigns each time a device is
        // plugged in or paired.
        const val KIND_AUTO = 0
        const val KIND_SPEAKER = 1
        const val KIND_WIRED_USB = 2
        const val KIND_BLUETOOTH = 3
    }

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var preferredKind = loadPref()

    // Kind of the output the sidetone actually plays on right now (null until
    // the first resolveAndApply). Used by the Send-mode Bluetooth latency hint.
    @Volatile private var activeKind: Int? = null

    fun isBluetoothActive() = activeKind == KIND_BLUETOOTH

    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) = resolveAndApply()
        override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) = resolveAndApply()
    }

    fun start() {
        audioManager.registerAudioDeviceCallback(callback, null)
        resolveAndApply()
    }

    fun stop() = audioManager.unregisterAudioDeviceCallback(callback)

    fun getPreferredKind() = preferredKind

    fun setPreferredKind(kind: Int) {
        preferredKind = kind
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putInt(PREF_OUTPUT_KIND, kind).apply()
        resolveAndApply()
    }

    // Kinds worth offering in Settings: Auto plus whatever is actually
    // connected right now (no point showing "Bluetooth" if nothing is paired).
    fun listAvailableKinds(): List<Int> {
        val kinds = sortedSetOf(KIND_AUTO)
        for (d in audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
            kindOf(d)?.let { kinds.add(it) }
        }
        return kinds.toList()
    }

    private fun loadPref(): Int =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getInt(PREF_OUTPUT_KIND, KIND_AUTO)

    private fun kindOf(d: AudioDeviceInfo): Int? = when (d.type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> KIND_SPEAKER
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> KIND_WIRED_USB
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> KIND_BLUETOOTH
        else -> null
    }

    // Priority Android itself uses when routing with no explicit device id:
    // a wired/USB connection wins over Bluetooth, which wins over the speaker.
    private fun routePriority(kind: Int?): Int = when (kind) {
        KIND_WIRED_USB -> 3
        KIND_BLUETOOTH -> 2
        KIND_SPEAKER -> 1
        else -> 0
    }

    private fun labelFor(kind: Int?): String = when (kind) {
        KIND_SPEAKER -> "Lautsprecher"
        KIND_WIRED_USB -> "Kabel/USB"
        KIND_BLUETOOTH -> "Bluetooth"
        else -> "Lautsprecher"
    }

    private fun resolveAndApply() {
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val explicitMatch = if (preferredKind == KIND_AUTO) null
            else outputs.firstOrNull { kindOf(it) == preferredKind }

        CwAudioNative.setPreferredDeviceId(explicitMatch?.id ?: 0)
        val res = CwAudioNative.restartStream()
        if (res != 0) Log.e(TAG, "restartStream failed: $res")

        val resolved = if (explicitMatch != null) kindOf(explicitMatch)
            else outputs.maxByOrNull { routePriority(kindOf(it)) }?.let { kindOf(it) }
        activeKind = resolved
        onRouteChanged(labelFor(resolved))
    }
}
