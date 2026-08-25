package com.abhishek.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import java.util.UUID

/**
 * Receives SMS_DELIVER while the app holds ROLE_SMS. Runs even when the
 * Flutter engine is dead: enqueue the message, post a notification, and ping
 * the UI if it happens to be alive.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) return
        val msgs = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (msgs.isEmpty()) return

        // Multipart SMS arrive as several PDUs from the same sender.
        val sender = msgs[0].displayOriginatingAddress ?: "Unknown"
        val body = msgs.joinToString("") { it.messageBody ?: "" }
        val ts = msgs[0].timestampMillis
        val entryId = UUID.randomUUID().toString()

        SmsQueue.add(context, entryId, sender, body, ts)

        val gate = TxnGate.check(body)
        if (gate != null) {
            Notifier.postTransaction(context, entryId, gate.amount, gate.isDebit, sender)
        } else {
            Notifier.postMessage(context, entryId, sender, body)
        }

        MainActivity.pingFlutter()
    }
}
