package com.vyaya.capture

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/** Queues incoming bank SMS that look like transactions (needs RECEIVE_SMS). */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val parts = runCatching { Telephony.Sms.Intents.getMessagesFromIntent(intent) }
            .getOrNull() ?: return

        // Long SMS arrive in parts; join them per sender.
        val assembled = LinkedHashMap<String, StringBuilder>()
        var timestamp = System.currentTimeMillis()
        for (msg in parts) {
            if (msg == null) continue
            val sender = msg.displayOriginatingAddress ?: msg.originatingAddress ?: continue
            timestamp = msg.timestampMillis
            assembled.getOrPut(sender) { StringBuilder() }.append(msg.displayMessageBody ?: "")
        }

        val store = CaptureStore.get(context)
        var preview: String? = null
        for ((sender, sb) in assembled) {
            val body = sb.toString().trim()
            if (!CaptureFilter.looksLikeTransaction(body)) continue
            if (!store.insert("sms", sender, body, timestamp, backfill = false)) continue
            if (preview == null) preview = body
        }
        if (preview == null) return

        if (CaptureBus.hasListener()) {
            CaptureBus.publish("sms")
        } else {
            CaptureNotifier.notifyPending(context, store.pendingCount(), preview)
        }
    }
}
