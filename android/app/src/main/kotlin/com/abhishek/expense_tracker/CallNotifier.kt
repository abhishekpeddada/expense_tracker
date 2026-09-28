package com.abhishek.expense_tracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.telecom.Call

/**
 * The notification side of a call.
 *
 * This is not decoration. From Android 10 an app cannot reliably start an
 * activity from the background, so a high-importance notification carrying
 * a full-screen intent is what actually puts the incoming-call screen up -
 * and if even that is refused, the notification itself still offers Answer
 * and Decline. The screen is the nice path; this is the one that must work.
 */
object CallNotifier {
    const val INCOMING_ID = 4101
    const val ONGOING_ID = 4102

    private const val CHANNEL_INCOMING = "calls_incoming"
    private const val CHANNEL_ONGOING = "calls_ongoing"

    const val ACTION_ANSWER = "com.abhishek.expense_tracker.ANSWER"
    const val ACTION_HANGUP = "com.abhishek.expense_tracker.HANGUP"

    private fun channels(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)

        val incoming = NotificationChannel(
            CHANNEL_INCOMING,
            "Incoming calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Rings and shows the incoming call screen"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }

        val ongoing = NotificationChannel(
            CHANNEL_ONGOING,
            "Ongoing calls",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "The call in progress"
            setShowBadge(false)
        }

        nm.createNotificationChannel(incoming)
        nm.createNotificationChannel(ongoing)
    }

    private fun action(context: Context, act: String): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            act.hashCode(),
            Intent(context, CallActionReceiver::class.java).setAction(act),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun screen(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            InCallActivity.intent(context),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    fun show(context: Context, call: Call) {
        channels(context)
        val nm = context.getSystemService(NotificationManager::class.java)
        val who = CallStore.callerNameOf(call)
            ?: CallStore.numberOf(call)
            ?: "Unknown number"

        if (CallStore.isIncoming(call)) {
            val builder = Notification.Builder(context, CHANNEL_INCOMING)
                .setSmallIcon(android.R.drawable.sym_call_incoming)
                .setContentTitle(who)
                .setContentText("Incoming call")
                .setCategory(Notification.CATEGORY_CALL)
                .setOngoing(true)
                .setAutoCancel(false)
                .setContentIntent(screen(context))
                // true asks the system to put the screen up immediately
                // rather than showing a heads-up the user has to tap.
                .setFullScreenIntent(screen(context), true)
                .addAction(
                    Notification.Action.Builder(
                        Icon_answer(), "Answer", action(context, ACTION_ANSWER)
                    ).build()
                )
                .addAction(
                    Notification.Action.Builder(
                        Icon_decline(), "Decline", action(context, ACTION_HANGUP)
                    ).build()
                )
            nm.notify(INCOMING_ID, builder.build())
            nm.cancel(ONGOING_ID)
        } else {
            val builder = Notification.Builder(context, CHANNEL_ONGOING)
                .setSmallIcon(android.R.drawable.sym_call_outgoing)
                .setContentTitle(who)
                .setContentText(CallStore.labelFor(call))
                .setCategory(Notification.CATEGORY_CALL)
                .setOngoing(true)
                .setContentIntent(screen(context))
                .addAction(
                    Notification.Action.Builder(
                        Icon_decline(), "Hang up", action(context, ACTION_HANGUP)
                    ).build()
                )
            nm.notify(ONGOING_ID, builder.build())
            nm.cancel(INCOMING_ID)
        }
    }

    fun clear(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.cancel(INCOMING_ID)
        nm.cancel(ONGOING_ID)
    }

    // Framework drawables, never resource id 0: SystemUI throws on a
    // missing icon and the whole notification is lost with it.
    private fun Icon_answer() =
        android.graphics.drawable.Icon.createWithResource(
            "android", android.R.drawable.sym_action_call
        )

    private fun Icon_decline() =
        android.graphics.drawable.Icon.createWithResource(
            "android", android.R.drawable.ic_menu_close_clear_cancel
        )
}
