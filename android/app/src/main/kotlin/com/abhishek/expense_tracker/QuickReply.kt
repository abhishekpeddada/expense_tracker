package com.abhishek.expense_tracker

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager

/**
 * Turning down a call with a text instead of silence.
 *
 * Sent from here rather than through Flutter: the phone is ringing, and
 * waiting on a Dart engine to start would leave the caller hanging. The
 * message is queued afterwards so the conversation picks it up whenever the
 * app next runs.
 */
object QuickReply {

    val canned = listOf(
        "Can't talk right now.",
        "Call you back in a few minutes.",
        "I'm in a meeting.",
        "On my way.",
    )

    fun canSend(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.SEND_SMS) ==
            PackageManager.PERMISSION_GRANTED

    /** Sends [text] to [number]. Answers whether it went out. */
    fun send(context: Context, number: String, text: String): Boolean {
        if (number.isBlank() || text.isBlank()) return false
        if (!canSend(context)) return false

        return runCatching {
            @Suppress("DEPRECATION")
            val sms = if (Build.VERSION.SDK_INT >= 31)
                context.getSystemService(SmsManager::class.java)
            else SmsManager.getDefault()
            sms.sendMultipartTextMessage(
                number, null, sms.divideMessage(text), null, null
            )
            SmsQueue.addSent(context, number, text, System.currentTimeMillis())
        }.isSuccess
    }
}
