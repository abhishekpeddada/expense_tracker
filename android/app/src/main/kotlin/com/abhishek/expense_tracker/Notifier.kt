package com.abhishek.expense_tracker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

object Notifier {
    const val TXN_CHANNEL = "transactions"
    const val MSG_CHANNEL = "messages"

    // Quick actions shown on the transaction notification (Android caps
    // notification actions at 3; tapping the body opens the app for the
    // full category list).
    private val quickCategories = listOf("Food & Dining", "Shopping", "Travel")

    fun ensureChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(
                TXN_CHANNEL, "Transactions",
                NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Categorize detected transactions" }
        )
        nm.createNotificationChannel(
            NotificationChannel(
                MSG_CHANNEL, "Messages",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply { description = "Incoming SMS" }
        )
    }

    /**
     * Persistent "what was this for?" notification. Stays until a category
     * is picked (quick action) or the app is opened.
     */
    fun postTransaction(
        ctx: Context,
        entryId: String,
        amount: String,
        isDebit: Boolean,
        sender: String,
    ) {
        ensureChannels(ctx)
        val notifId = entryId.hashCode()

        val openApp = PendingIntent.getActivity(
            ctx, notifId,
            Intent(ctx, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("openTab", "transactions")
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(ctx, TXN_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(
                if (isDebit) "₹$amount spent — what was it for?"
                else "₹$amount received — categorize it?"
            )
            .setContentText("From $sender · tap for all categories")
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(openApp)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)

        quickCategories.forEachIndexed { i, cat ->
            val pi = PendingIntent.getBroadcast(
                ctx, notifId * 10 + i,
                Intent(ctx, CategoryActionReceiver::class.java).apply {
                    putExtra("entryId", entryId)
                    putExtra("category", cat)
                    putExtra("notifId", notifId)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(0, cat.substringBefore(" &"), pi)
        }

        ctx.getSystemService(NotificationManager::class.java)
            .notify(notifId, builder.build())
    }

    /** Regular notification for a non-transaction SMS. */
    fun postMessage(ctx: Context, entryId: String, sender: String, body: String) {
        ensureChannels(ctx)
        val notifId = entryId.hashCode()
        val openApp = PendingIntent.getActivity(
            ctx, notifId,
            Intent(ctx, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra("openTab", "messages")
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = NotificationCompat.Builder(ctx, MSG_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(sender)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openApp)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify(notifId, n)
    }
}
