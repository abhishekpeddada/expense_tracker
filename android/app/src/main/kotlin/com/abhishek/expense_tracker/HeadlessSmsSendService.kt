package com.abhishek.expense_tracker

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.telephony.SmsManager

/**
 * Required for default-SMS-app eligibility: handles "respond via message"
 * from the dialer (declining a call with a text).
 */
class HeadlessSmsSendService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val text = intent?.getStringExtra(Intent.EXTRA_TEXT)
        val recipient = intent?.data?.schemeSpecificPart
        if (!text.isNullOrBlank() && !recipient.isNullOrBlank()) {
            runCatching {
                getSystemService(SmsManager::class.java)
                    .sendTextMessage(recipient, null, text, null, null)
            }
        }
        stopSelf(startId)
        return START_NOT_STICKY
    }
}
