package com.vyaya.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build

/** "New payment detected" notification shown while Vyaya is closed. */
object CaptureNotifier {
    private const val CHANNEL_ID = "vyaya_payment_detection"
    private const val NOTIFICATION_ID = 47110
    private const val PREFS = "vyaya_capture"
    private const val KEY_ENABLED = "notifier_enabled"

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (!enabled) clear(context)
    }

    private fun isEnabled(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, true)

    fun notifyPending(context: Context, count: Int, preview: String?) {
        if (count <= 0 || !isEnabled(context)) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(CHANNEL_ID) == null
        ) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Detected payments", NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = "Payments picked up from bank SMS and payment apps" }
            )
        }

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pending = launch?.let {
            PendingIntent.getActivity(
                context, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val title = if (count == 1) "New payment detected" else "$count new payments detected"
        // The raw message (amounts, account digits) isn't shown any more:
        // this notification also appears on the lock screen.
        // val text = preview?.take(140)
        val text = "Open Vyaya to review"

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(context, CHANNEL_ID) else Notification.Builder(context)
        builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
        if (!text.isNullOrBlank()) {
            builder.setContentText(text)
            builder.setStyle(Notification.BigTextStyle().bigText(text))
        }
        if (pending != null) builder.setContentIntent(pending)

        runCatching { manager.notify(NOTIFICATION_ID, builder.build()) }
    }

    fun clear(context: Context) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager)
            ?.cancel(NOTIFICATION_ID)
    }
}
