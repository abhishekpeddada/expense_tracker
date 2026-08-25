package com.abhishek.expense_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Required for default-SMS-app eligibility. MMS download is not implemented
 * yet — bank transaction SMS are plain SMS.
 */
class MmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = Unit
}
