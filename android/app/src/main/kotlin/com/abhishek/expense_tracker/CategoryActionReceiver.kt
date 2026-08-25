package com.abhishek.expense_tracker

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.RemoteInput

/**
 * Handles a category pick on a transaction notification — either a quick
 * action button (category in an extra) or free text typed into the
 * notification's RemoteInput field.
 */
class CategoryActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val entryId = intent.getStringExtra("entryId") ?: return
        val notifId = intent.getIntExtra("notifId", 0)

        val typed = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(Notifier.KEY_CATEGORY_INPUT)?.toString()?.trim()
        val category = typed?.takeIf { it.isNotEmpty() }
            ?: intent.getStringExtra("category")
            ?: return

        // The SMS entry may still be queued (app never opened) or already
        // drained into the DB (app opened first) — cover both.
        SmsQueue.setCategory(context, entryId, category)
        SmsQueue.addPendingCategory(context, entryId, category)

        context.getSystemService(NotificationManager::class.java).cancel(notifId)
        MainActivity.pingFlutter()
    }
}
