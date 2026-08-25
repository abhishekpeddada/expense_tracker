package com.abhishek.expense_tracker

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import java.util.UUID

/**
 * Receives SMS_DELIVER while the app holds ROLE_SMS. Runs even when the
 * Flutter engine is dead. Every step is isolated so one failure (say, the
 * notification) can never lose the message itself.
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

        val preview = if (body.length > 60) body.take(60) + "…" else body
        runCatching {
            SmsQueue.add(context, entryId, sender, body, ts)
            SmsQueue.log(context, "received from $sender: $preview")
        }.onFailure {
            Log.e(TAG, "queue add failed", it)
            runCatching { SmsQueue.log(context, "QUEUE FAILED from $sender: $it") }
        }

        // The default SMS app is responsible for writing incoming messages
        // to the system SMS provider (AOSP Messaging does the same). This
        // also keeps history intact if the user switches SMS apps later.
        runCatching {
            val values = ContentValues().apply {
                put(Telephony.Sms.ADDRESS, sender)
                put(Telephony.Sms.BODY, body)
                put(Telephony.Sms.DATE, ts)
                put(Telephony.Sms.READ, 0)
                put(Telephony.Sms.SEEN, 0)
            }
            context.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, values)
        }.onFailure {
            Log.e(TAG, "telephony provider write failed", it)
            runCatching { SmsQueue.log(context, "provider write failed: $it") }
        }

        runCatching {
            val gate = TxnGate.check(body)
            if (gate != null) {
                Notifier.postTransaction(context, entryId, gate.amount, gate.isDebit, sender)
            } else {
                Notifier.postMessage(context, entryId, sender, body)
            }
        }.onFailure {
            Log.e(TAG, "notification failed", it)
            runCatching { SmsQueue.log(context, "notification failed: $it") }
            // Never let a notification problem hide the message entirely.
            runCatching { Notifier.postMessage(context, entryId, sender, body) }
        }

        runCatching { MainActivity.pingFlutter() }
            .onFailure { Log.e(TAG, "flutter ping failed", it) }
    }

    private companion object {
        const val TAG = "SmsReceiver"
    }
}
