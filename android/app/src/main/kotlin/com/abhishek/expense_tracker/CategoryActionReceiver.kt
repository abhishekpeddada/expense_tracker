package com.abhishek.expense_tracker

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Handles a category quick-action tap on a transaction notification. */
class CategoryActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val entryId = intent.getStringExtra("entryId") ?: return
        val category = intent.getStringExtra("category") ?: return
        val notifId = intent.getIntExtra("notifId", 0)

        SmsQueue.setCategory(context, entryId, category)
        context.getSystemService(NotificationManager::class.java).cancel(notifId)
        MainActivity.pingFlutter()
    }
}
