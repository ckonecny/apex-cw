package at.oe1cko.nextcwtrainer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Keeps the own-texts player (issues #21, #22) alive with the screen off or
 * the app in the background: foreground service with a media notification, a
 * MediaSession for the lock screen and headset buttons, audio focus and a
 * partial wake lock. It plays nothing itself — the sound still comes from the
 * shared CwGenerator, driven by the Dart player. Every button press is handed
 * to [OwnTextPlayback.onCommand]; Dart answers with a new state via update.
 * Only the own-texts player starts it (nothing else uses it).
 */
class OwnTextPlaybackService : Service() {

    companion object {
        const val ACTION_UPDATE = "at.oe1cko.nextcwtrainer.OT_UPDATE"
        const val ACTION_STOP = "at.oe1cko.nextcwtrainer.OT_STOP"
        const val CMD_PLAY = "at.oe1cko.nextcwtrainer.OT_PLAY"
        const val CMD_PAUSE = "at.oe1cko.nextcwtrainer.OT_PAUSE"
        const val CMD_NEXT = "at.oe1cko.nextcwtrainer.OT_NEXT"
        const val CMD_PREV = "at.oe1cko.nextcwtrainer.OT_PREV"
        private const val CHANNEL = "own_text_playback"
        private const val NOTIF_ID = 4721
        // Safety net: a forgotten lock never holds the CPU awake for longer.
        private const val WAKE_LOCK_MS = 4L * 60 * 60 * 1000
    }

    private var session: MediaSession? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var focus: AudioFocusRequest? = null
    private var playing = false
    private var foreground = false
    private var title = ""
    private var labels = mapOf<String, String>()

    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            if (playing) OwnTextPlayback.onCommand?.invoke("pause")
        }
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        // A call or another player took over: stop, no automatic resume.
        if (change == AudioManager.AUDIOFOCUS_LOSS ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK) {
            if (playing) OwnTextPlayback.onCommand?.invoke("pause")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        session = MediaSession(this, "APEX CW own texts").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() { OwnTextPlayback.onCommand?.invoke("play") }
                override fun onPause() { OwnTextPlayback.onCommand?.invoke("pause") }
                override fun onSkipToNext() { OwnTextPlayback.onCommand?.invoke("next") }
                override fun onSkipToPrevious() { OwnTextPlayback.onCommand?.invoke("prev") }
                override fun onStop() { OwnTextPlayback.onCommand?.invoke("pause") }
            })
            isActive = true
        }
        registerReceiver(noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_UPDATE -> {
                title = intent.getStringExtra("title") ?: ""
                playing = intent.getBooleanExtra("playing", false)
                labels = mapOf(
                    "channel" to (intent.getStringExtra("channel") ?: "Playback"),
                    "play" to (intent.getStringExtra("play") ?: "Play"),
                    "pause" to (intent.getStringExtra("pause") ?: "Pause"),
                    "next" to (intent.getStringExtra("next") ?: "Next"),
                    "prev" to (intent.getStringExtra("prev") ?: "Previous"))
                refresh()
            }
            ACTION_STOP -> shutDown()
            CMD_PLAY -> OwnTextPlayback.onCommand?.invoke("play")
            CMD_PAUSE -> OwnTextPlayback.onCommand?.invoke("pause")
            CMD_NEXT -> OwnTextPlayback.onCommand?.invoke("next")
            CMD_PREV -> OwnTextPlayback.onCommand?.invoke("prev")
        }
        // Not restarted by the system: without the Dart player there is nothing to drive.
        return START_NOT_STICKY
    }

    private fun refresh() {
        val s = session ?: return
        s.setMetadata(MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, "APEX CW")
            .build())
        s.setPlaybackState(PlaybackState.Builder()
            .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_NEXT or
                PlaybackState.ACTION_SKIP_TO_PREVIOUS or PlaybackState.ACTION_STOP)
            .setState(if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                PlaybackState.PLAYBACK_POSITION_UNKNOWN, if (playing) 1f else 0f)
            .build())
        if (playing) { requestFocus(); holdWakeLock() } else { releaseWakeLock() }

        val notification = buildNotification()
        if (playing) {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(NOTIF_ID, notification)
            }
            foreground = true
        } else if (foreground) {
            // Paused: stay as a notification the user can swipe away, so the
            // play button on the lock screen keeps working.
            stopForeground(STOP_FOREGROUND_DETACH)
            foreground = false
            getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notification)
        } else {
            getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notification)
        }
    }

    private fun action(cmd: String, icon: Int, label: String): Notification.Action {
        val pi = PendingIntent.getService(this, cmd.hashCode(),
            Intent(this, OwnTextPlaybackService::class.java).setAction(cmd),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Action.Builder(
            android.graphics.drawable.Icon.createWithResource(this, icon), label, pi).build()
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, labels["channel"],
            NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
        val open = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val b = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_play)
            .setContentTitle(title)
            .setContentText("APEX CW")
            .setContentIntent(open)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(action(CMD_PREV, android.R.drawable.ic_media_previous, labels["prev"] ?: ""))
            .addAction(
                if (playing) action(CMD_PAUSE, android.R.drawable.ic_media_pause, labels["pause"] ?: "")
                else action(CMD_PLAY, android.R.drawable.ic_media_play, labels["play"] ?: ""))
            .addAction(action(CMD_NEXT, android.R.drawable.ic_media_next, labels["next"] ?: ""))
            .setStyle(Notification.MediaStyle()
                .setMediaSession(session?.sessionToken)
                .setShowActionsInCompactView(0, 1, 2))
        if (Build.VERSION.SDK_INT >= 31) {
            b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return b.build()
    }

    private fun requestFocus() {
        if (focus != null) return
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setOnAudioFocusChangeListener(focusListener)
            .build()
        getSystemService(AudioManager::class.java).requestAudioFocus(req)
        focus = req
    }

    private fun abandonFocus() {
        focus?.let { getSystemService(AudioManager::class.java).abandonAudioFocusRequest(it) }
        focus = null
    }

    private fun holdWakeLock() {
        if (wakeLock?.isHeld == true) return
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "apexcw:owntext")
            .apply { acquire(WAKE_LOCK_MS) }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
    }

    private fun shutDown() {
        playing = false
        releaseWakeLock()
        abandonFocus()
        stopForeground(STOP_FOREGROUND_REMOVE)
        getSystemService(NotificationManager::class.java).cancel(NOTIF_ID)
        foreground = false
        stopSelf()
    }

    override fun onDestroy() {
        getSystemService(NotificationManager::class.java).cancel(NOTIF_ID)
        releaseWakeLock()
        abandonFocus()
        try { unregisterReceiver(noisy) } catch (_: Exception) {}
        session?.release()
        session = null
        super.onDestroy()
    }
}

/** Bridge between the service and the Dart player (set by MainActivity). */
object OwnTextPlayback {
    /** "play" | "pause" | "next" | "prev"; null while no player listens. */
    @Volatile var onCommand: ((String) -> Unit)? = null
}
