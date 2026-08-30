package com.abhishek.expense_tracker

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.UUID

/**
 * Reads notifications posted by payment and banking apps, so a transaction
 * is captured even when the bank sends no SMS. Some banks (SBI, notably)
 * skip SMS for small UPI debits entirely, which leaves SMS parsing blind.
 *
 * Only notifications from a known set of payment apps are inspected, and
 * only their text is read — nothing else is stored or forwarded.
 */
class TxnNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName ?: return
        if (pkg !in watchedPackages) return
        // Our own notifications would otherwise loop straight back in.
        if (pkg == packageName) return

        runCatching {
            val extras = sbn.notification?.extras ?: return
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
            val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
            val body = listOf(title, big.ifEmpty { text })
                .filter { it.isNotBlank() }
                .joinToString(" - ")
            if (body.isBlank()) return

            val gate = TxnGate.check(body) ?: return

            // The same payment usually also produces an SMS; markSeen keeps
            // whichever arrives first and drops the other.
            val ts = sbn.postTime
            if (!SmsQueue.markSeen(this, "notif:$pkg", body, ts)) return

            val entryId = UUID.randomUUID().toString()
            SmsQueue.addNotification(this, entryId, appLabel(pkg), body, ts)
            SmsQueue.log(this, "notification from ${appLabel(pkg)}: " +
                if (body.length > 60) body.take(60) + "…" else body)

            Notifier.postTransaction(
                this, entryId, gate.amount, gate.isDebit, appLabel(pkg)
            )
            MainActivity.pingFlutter()
        }.onFailure { Log.e(TAG, "notification handling failed", it) }
    }

    private fun appLabel(pkg: String): String = knownApps[pkg] ?: pkg

    private companion object {
        const val TAG = "TxnNotificationListener"

        val knownApps = mapOf(
            "com.google.android.apps.nbu.paisa.user" to "Google Pay",
            "com.phonepe.app" to "PhonePe",
            "net.one97.paytm" to "Paytm",
            "in.org.npci.upiapp" to "BHIM",
            "com.dreamplug.androidapp" to "CRED",
            "com.sbi.lotusintouch" to "YONO SBI",
            "com.sbi.SBIFreedomPlus" to "SBI",
            "com.csam.icici.bank.imobile" to "iMobile",
            "com.snapwork.hdfc" to "HDFC Bank",
            "com.axis.mobile" to "Axis Mobile",
            "com.msf.kbank.mobile" to "Kotak",
            "com.bankofbaroda.mconnect" to "BOB World",
            "com.infrasofttech.CentralBank" to "Cent Mobile",
            "com.fss.pnbpsp" to "PNB",
            "com.amazon.mShop.android.shopping" to "Amazon Pay",
        )

        val watchedPackages = knownApps.keys
    }
}
