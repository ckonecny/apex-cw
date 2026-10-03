package at.oe1cko.nextcwtrainer

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Optional daily practice reminder (issue #32, DECISIONS.md "Reminder").
 *
 * Dart decides when (it knows whether today's goal is met) and passes the next
 * few fire times plus the text. They are kept here so the chain survives the
 * app being closed and a reboot: one inexact alarm is armed for the earliest
 * time; when it fires, the notification is shown and the next one is armed.
 * No exact-alarm permission: the notification may arrive a few minutes late.
 * Nothing leaves the device.
 */
object Reminder {
    private const val PREFS = "reminder"
    private const val KEY_TIMES = "times"
    private const val KEY_TITLE = "title"
    private const val KEY_BODY = "body"
    private const val CHANNEL = "reminder"
    private const val NOTIF_ID = 3200
    private const val REQ_ALARM = 3201

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun times(c: Context): List<Long> =
        (prefs(c).getString(KEY_TIMES, "") ?: "").split(',').mapNotNull { it.toLongOrNull() }.sorted()

    private fun alarmIntent(c: Context) = PendingIntent.getBroadcast(
        c, REQ_ALARM, Intent(c, ReminderReceiver::class.java).setAction("at.oe1cko.nextcwtrainer.REMINDER"),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /** Replaces the stored times and arms the earliest future one. */
    fun schedule(c: Context, times: List<Long>, title: String, body: String) {
        prefs(c).edit().putString(KEY_TIMES, times.joinToString(","))
            .putString(KEY_TITLE, title).putString(KEY_BODY, body).apply()
        arm(c)
    }

    fun cancel(c: Context) {
        prefs(c).edit().remove(KEY_TIMES).apply()
        (c.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(alarmIntent(c))
    }

    /** Arms the earliest stored time still in the future (drops past ones). */
    fun arm(c: Context) {
        val now = System.currentTimeMillis()
        val future = times(c).filter { it > now }
        prefs(c).edit().putString(KEY_TIMES, future.joinToString(",")).apply()
        val am = c.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(alarmIntent(c))
        future.firstOrNull()?.let {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, it, alarmIntent(c))
        }
    }

    fun notifyNow(c: Context) {
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val p = prefs(c)
        nm.createNotificationChannel(NotificationChannel(CHANNEL,
            p.getString("channel", "Reminder"), NotificationManager.IMPORTANCE_DEFAULT))
        val open = c.packageManager.getLaunchIntentForPackage(c.packageName)?.let {
            PendingIntent.getActivity(c, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val n = android.app.Notification.Builder(c, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle(p.getString(KEY_TITLE, ""))
            .setContentText(p.getString(KEY_BODY, ""))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        nm.notify(NOTIF_ID, n)
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Reminder.arm(context)
        } else {
            Reminder.notifyNow(context)
            Reminder.arm(context)
        }
    }
}
