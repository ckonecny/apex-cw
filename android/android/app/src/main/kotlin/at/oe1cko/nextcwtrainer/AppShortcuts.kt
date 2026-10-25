package at.oe1cko.nextcwtrainer

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon

/**
 * Launcher shortcuts (long-press on the app icon, issue #151). Dynamic rather
 * than static so the labels follow the app's own language setting: Dart
 * publishes them with labels and rendered icons on start and on every
 * language change. A tapped shortcut starts MainActivity with [EXTRA] set to
 * its id; Dart takes that id and opens the screen.
 */
object AppShortcuts {
    const val EXTRA = "at.oe1cko.nextcwtrainer.SHORTCUT"

    fun publish(ctx: Context, items: List<Map<String, Any?>>) {
        val sm = ctx.getSystemService(ShortcutManager::class.java) ?: return
        val list = items.take(sm.maxShortcutCountPerActivity).mapIndexedNotNull { rank, m ->
            val id = m["id"] as? String ?: return@mapIndexedNotNull null
            val short = m["short"] as? String ?: id
            val png = m["icon"] as? ByteArray
            val b = ShortcutInfo.Builder(ctx, id)
                .setShortLabel(short)
                .setLongLabel(m["long"] as? String ?: short)
                .setRank(rank)
                .setIntent(Intent(Intent.ACTION_VIEW, null, ctx, MainActivity::class.java)
                    .putExtra(EXTRA, id))
            if (png != null) {
                BitmapFactory.decodeByteArray(png, 0, png.size)
                    ?.let { b.setIcon(Icon.createWithAdaptiveBitmap(it)) }
            }
            b.build()
        }
        try {
            sm.dynamicShortcuts = list
            // Shortcuts already pinned to the home screen get the new labels too.
            sm.updateShortcuts(list)
        } catch (_: IllegalStateException) {
            // Rate-limited (only happens in the background): the next start retries.
        }
    }

    fun reportUsed(ctx: Context, id: String) {
        ctx.getSystemService(ShortcutManager::class.java)?.reportShortcutUsed(id)
    }
}
