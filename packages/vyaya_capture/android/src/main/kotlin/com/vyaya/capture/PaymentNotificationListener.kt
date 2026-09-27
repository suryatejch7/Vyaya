package com.vyaya.capture

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Reads notifications from payment apps (PhonePe, GPay, Paytm…) and queues
 * the ones that look like a payment. Runs even when Vyaya is closed once the
 * user grants "Notification access".
 */
class PaymentNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val n = sbn ?: return
        val pkg = n.packageName ?: return
        if (pkg == applicationContext.packageName) return
        if (pkg !in CaptureFilter.PAYMENT_APPS) return

        val notification = n.notification ?: return
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (notification.flags and Notification.FLAG_ONGOING_EVENT != 0) return

        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.joinToString(" ") { it.toString() }?.trim().orEmpty()

        val detail = when {
            big.isNotBlank() -> big
            text.isNotBlank() -> text
            else -> lines
        }
        // "Title — detail": lets the parser read e.g. "Rahul Kumar — Paid you ₹200".
        val body = listOf(title, detail).filter { it.isNotBlank() }.distinct().joinToString(" — ")
        if (!CaptureFilter.looksLikeTransaction(body)) return

        val postedAt = if (n.postTime > 0) n.postTime else System.currentTimeMillis()
        val store = CaptureStore.get(applicationContext)
        if (!store.insert("notification", pkg, body, postedAt, backfill = false)) return

        if (CaptureBus.hasListener()) {
            CaptureBus.publish("notification")
        } else {
            CaptureNotifier.notifyPending(applicationContext, store.pendingCount(), body)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) = Unit
}
