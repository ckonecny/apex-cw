package at.oe1cko.nextcwtrainer

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.provider.Settings

/**
 * Optional "do not disturb while training" (issue #55). Switches the system
 * interruption filter to Priority (the user's own DND exceptions, e.g. starred
 * callers, still get through) and puts the previous filter back afterwards.
 * Needs the user's "Do Not Disturb access" grant; without it nothing happens.
 *
 * The filter in place before we changed it is kept in our own prefs, so a
 * crash or kill while engaged is repaired by [restore] on the next start.
 */
class FocusMode(private val ctx: Context) {
    private val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val prefs = ctx.getSharedPreferences("focus_mode", Context.MODE_PRIVATE)

    fun hasAccess(): Boolean = nm.isNotificationPolicyAccessGranted

    /** Opens the system page where the user grants DND access to the app. */
    fun openAccessSettings() {
        ctx.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Opens the general DND settings (fallback hint). */
    fun openDndSettings() {
        ctx.startActivity(Intent(Settings.ACTION_ZEN_MODE_PRIORITY_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Returns true if the filter is now (or already was) under our control. */
    fun engage(): Boolean {
        if (!hasAccess()) return false
        if (prefs.contains(KEY_PREV)) return true // already engaged
        val cur = nm.currentInterruptionFilter
        // Never loosen a stricter mode the user chose themselves.
        if (cur == NotificationManager.INTERRUPTION_FILTER_NONE ||
            cur == NotificationManager.INTERRUPTION_FILTER_ALARMS ||
            cur == NotificationManager.INTERRUPTION_FILTER_PRIORITY) return true
        prefs.edit().putInt(KEY_PREV, cur).commit()
        nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
        return true
    }

    /** Puts the saved filter back. No-op if we did not change anything. */
    fun restore() {
        if (!prefs.contains(KEY_PREV)) return
        val prev = prefs.getInt(KEY_PREV, NotificationManager.INTERRUPTION_FILTER_ALL)
        prefs.edit().remove(KEY_PREV).commit()
        // The user may have revoked access in the meantime.
        if (hasAccess()) nm.setInterruptionFilter(prev)
    }

    private companion object { const val KEY_PREV = "prev_filter" }
}
