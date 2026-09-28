package com.abhishek.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Answer and Decline on the call notification. */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            CallNotifier.ACTION_ANSWER -> {
                CallStore.answer()
                // The screen is wanted now that the call is being taken,
                // and by this point the tap counts as user interaction.
                runCatching {
                    context.startActivity(
                        InCallActivity.intent(context)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                }
            }
            CallNotifier.ACTION_HANGUP -> CallStore.hangUp()
        }
    }
}
