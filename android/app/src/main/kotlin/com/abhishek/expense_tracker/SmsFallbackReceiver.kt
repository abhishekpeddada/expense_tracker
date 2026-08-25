package com.abhishek.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import java.util.UUID

/**
 * Listens to SMS_RECEIVED, which every app holding RECEIVE_SMS gets —
 * unlike SMS_DELIVER, which only the default SMS app gets. AOSP Messaging
 * registers both for the same reason: if SMS_DELIVER is not delivered for
 * any reason, the message is still seen here.
 *
 * When both fire for one message (the normal case while we are default),
 * [SmsQueue.markSeen] keeps only the first.
 */
class SmsFallbackReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val msgs = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (msgs.isEmpty()) return

        val sender = msgs[0].displayOriginatingAddress ?: "Unknown"
        val body = msgs.joinToString("") { it.messageBody ?: "" }
        val ts = msgs[0].timestampMillis

        runCatching {
            if (!SmsQueue.markSeen(context, sender, body, ts)) {
                // SMS_DELIVER already handled this one.
                return
            }
            val entryId = UUID.randomUUID().toString()
            val preview = if (body.length > 60) body.take(60) + "…" else body
            SmsQueue.add(context, entryId, sender, body, ts)
            SmsQueue.log(context, "via SMS_RECEIVED from $sender: $preview")

            runCatching {
                val gate = TxnGate.check(body)
                if (gate != null) {
                    Notifier.postTransaction(
                        context, entryId, gate.amount, gate.isDebit, sender
                    )
                } else {
                    Notifier.postMessage(context, entryId, sender, body)
                }
            }.onFailure {
                runCatching { SmsQueue.log(context, "fallback notify failed: $it") }
            }
            MainActivity.pingFlutter()
        }.onFailure { Log.e("SmsFallbackReceiver", "failed", it) }
    }
}
