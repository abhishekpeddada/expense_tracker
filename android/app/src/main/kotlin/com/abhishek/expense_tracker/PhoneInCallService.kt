package com.abhishek.expense_tracker

import android.content.Intent
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService

/**
 * How the system hands us calls once this app holds the dialer role.
 *
 * Every call goes to CallStore first and to the screen second, so the state
 * is right even if no screen is up - a call answered from the notification
 * on a locked phone never opens one.
 */
class PhoneInCallService : InCallService() {

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        CallStore.service = this
        CallStore.add(call)
        CallNotifier.show(this, call)

        // Outgoing calls start from a tap, so this is allowed and instant.
        // Incoming ones usually arrive with the app in the background,
        // where the launch is refused and the full-screen intent on the
        // notification is what actually opens the screen.
        runCatching {
            startActivity(
                InCallActivity.intent(this).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        CallStore.remove(call)
        if (CallStore.isEmpty()) {
            CallNotifier.clear(this)
        } else {
            CallStore.primary()?.let { CallNotifier.show(this, it) }
        }
    }

    override fun onCallAudioStateChanged(audioState: CallAudioState) {
        super.onCallAudioStateChanged(audioState)
        CallStore.notifyListeners()
    }

    override fun onDestroy() {
        if (CallStore.service === this) CallStore.service = null
        super.onDestroy()
    }
}
