package com.abhishek.expense_tracker

import android.os.Build
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import android.telecom.VideoProfile

/**
 * The live picture of what the phone is doing, shared between the
 * InCallService that is told about calls and the screen that shows them.
 *
 * Deliberately a plain object with no Flutter involvement: answering a call
 * must not wait on a Dart engine starting up.
 */
object CallStore {

    /** Set while the system has our InCallService bound. */
    @Volatile
    var service: InCallService? = null

    private val calls = mutableListOf<Call>()
    private val listeners = mutableSetOf<() -> Unit>()

    private val callback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) = notifyListeners()
        override fun onDetailsChanged(call: Call, details: Call.Details) =
            notifyListeners()
    }

    @Synchronized
    fun add(call: Call) {
        if (calls.none { it === call }) {
            calls.add(call)
            call.registerCallback(callback)
        }
        notifyListeners()
    }

    @Synchronized
    fun remove(call: Call) {
        runCatching { call.unregisterCallback(callback) }
        calls.removeAll { it === call }
        notifyListeners()
    }

    /**
     * The call the screen should be about: a ringing one first, since that
     * is what needs answering, then whatever else is going on.
     */
    @Synchronized
    fun primary(): Call? =
        calls.firstOrNull { stateOf(it) == Call.STATE_RINGING } ?: calls.firstOrNull()

    @Synchronized
    fun isEmpty(): Boolean = calls.isEmpty()

    fun addListener(listener: () -> Unit) {
        synchronized(listeners) { listeners.add(listener) }
    }

    fun removeListener(listener: () -> Unit) {
        synchronized(listeners) { listeners.remove(listener) }
    }

    fun notifyListeners() {
        val snapshot = synchronized(listeners) { listeners.toList() }
        snapshot.forEach { runCatching { it() } }
    }

    // ---- Actions, all null-safe so a stale screen cannot crash ----

    fun answer() {
        primary()?.let { runCatching { it.answer(VideoProfile.STATE_AUDIO_ONLY) } }
    }

    /** Rejects a ringing call, or ends one already connected. */
    fun hangUp() {
        val call = primary() ?: return
        runCatching {
            if (stateOf(call) == Call.STATE_RINGING) {
                call.reject(false, null)
            } else {
                call.disconnect()
            }
        }
    }

    fun setMuted(muted: Boolean) {
        runCatching { service?.setMuted(muted) }
    }

    fun isMuted(): Boolean = service?.callAudioState?.isMuted == true

    fun setSpeaker(on: Boolean) {
        runCatching {
            service?.setAudioRoute(
                if (on) CallAudioState.ROUTE_SPEAKER
                else CallAudioState.ROUTE_WIRED_OR_EARPIECE
            )
        }
    }

    fun isSpeakerOn(): Boolean =
        service?.callAudioState?.route == CallAudioState.ROUTE_SPEAKER

    fun playDtmf(digit: Char) {
        primary()?.let {
            runCatching {
                it.playDtmfTone(digit)
                it.stopDtmfTone()
            }
        }
    }

    // ---- Details ----

    /** getState was deprecated in favour of the details object in API 31. */
    fun stateOf(call: Call): Int =
        if (Build.VERSION.SDK_INT >= 31) call.details.state
        else @Suppress("DEPRECATION") call.state

    fun numberOf(call: Call): String? =
        call.details?.handle?.schemeSpecificPart

    /** The caller's name when the network or the call screen supplies one. */
    fun callerNameOf(call: Call): String? =
        call.details?.callerDisplayName?.takeIf { it.isNotBlank() }

    fun isIncoming(call: Call): Boolean =
        stateOf(call) == Call.STATE_RINGING

    fun isOngoing(call: Call): Boolean = when (stateOf(call)) {
        Call.STATE_ACTIVE, Call.STATE_HOLDING -> true
        else -> false
    }

    fun labelFor(call: Call): String = when (stateOf(call)) {
        Call.STATE_RINGING -> "Incoming call"
        Call.STATE_DIALING, Call.STATE_CONNECTING -> "Calling..."
        Call.STATE_ACTIVE -> "In call"
        Call.STATE_HOLDING -> "On hold"
        Call.STATE_DISCONNECTING -> "Ending..."
        Call.STATE_DISCONNECTED -> "Call ended"
        else -> ""
    }

    /** When the call connected, for the on-screen timer. 0 if not yet. */
    fun connectTimeOf(call: Call): Long = call.details?.connectTimeMillis ?: 0L
}
