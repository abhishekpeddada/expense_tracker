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
     * The call the screen is about.
     *
     * A call already in progress outranks one that is ringing. That is the
     * opposite of what it looks like it should be, and it matters: during
     * call waiting the person is mid-conversation, and swapping the whole
     * screen to the new caller would hide the call they are actually on
     * along with the button to end it. The second call gets its own strip
     * instead.
     */
    @Synchronized
    fun primary(): Call? = ongoing() ?: ringing() ?: calls.firstOrNull()

    /** The call ringing right now, if any. */
    @Synchronized
    fun ringing(): Call? =
        calls.firstOrNull { stateOf(it) == Call.STATE_RINGING }

    /** A connected call, preferring an active one over a held one. */
    @Synchronized
    fun ongoing(): Call? =
        calls.firstOrNull { stateOf(it) == Call.STATE_ACTIVE }
            ?: calls.firstOrNull { stateOf(it) == Call.STATE_HOLDING }
            ?: calls.firstOrNull { stateOf(it) == Call.STATE_DIALING }
            ?: calls.firstOrNull { stateOf(it) == Call.STATE_CONNECTING }

    @Synchronized
    fun held(): Call? =
        calls.firstOrNull { stateOf(it) == Call.STATE_HOLDING }

    /**
     * The call the screen mentions second: whoever is waiting, or whoever
     * is on hold while someone else talks.
     */
    @Synchronized
    fun secondary(): Call? {
        val main = primary() ?: return null
        return calls.firstOrNull { it !== main && !isConference(it) }
    }

    @Synchronized
    fun count(): Int = calls.size

    @Synchronized
    fun isEmpty(): Boolean = calls.isEmpty()

    // ---- Capabilities ----

    private fun can(call: Call?, capability: Int): Boolean =
        call?.details?.can(capability) == true

    fun canHold(call: Call? = primary()): Boolean =
        can(call, Call.Details.CAPABILITY_HOLD)

    fun canMerge(call: Call? = primary()): Boolean =
        can(call, Call.Details.CAPABILITY_MERGE_CONFERENCE)

    fun canSwap(call: Call? = primary()): Boolean =
        can(call, Call.Details.CAPABILITY_SWAP_CONFERENCE) ||
            (held() != null && ongoing() != null)

    fun isConference(call: Call): Boolean =
        call.details?.hasProperty(Call.Details.PROPERTY_CONFERENCE) == true

    /** Whether this line can carry video, which is a carrier question. */
    fun canVideo(call: Call? = primary()): Boolean =
        can(call, Call.Details.CAPABILITY_SUPPORTS_VT_LOCAL_BIDIRECTIONAL) &&
            can(call, Call.Details.CAPABILITY_SUPPORTS_VT_REMOTE_BIDIRECTIONAL)

    fun isVideo(call: Call? = primary()): Boolean {
        val state = call?.details?.videoState ?: return false
        return VideoProfile.isBidirectional(state) ||
            VideoProfile.isReceptionEnabled(state)
    }

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

    /**
     * Answers whatever is ringing. Telecom holds an existing call for us,
     * so this is also the answer to a second call arriving mid-conversation.
     */
    fun answer(video: Boolean = false) {
        val call = ringing() ?: primary() ?: return
        runCatching {
            call.answer(
                if (video) VideoProfile.STATE_BIDIRECTIONAL
                else VideoProfile.STATE_AUDIO_ONLY
            )
        }
    }

    /** Ends the call in progress and answers the one that is ringing. */
    fun endAndAnswer() {
        val waiting = ringing() ?: return
        ongoing()?.let { runCatching { it.disconnect() } }
        runCatching { waiting.answer(VideoProfile.STATE_AUDIO_ONLY) }
    }

    fun rejectWaiting() {
        ringing()?.let { runCatching { it.reject(false, null) } }
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

    fun hangUp(call: Call) {
        runCatching {
            if (stateOf(call) == Call.STATE_RINGING) call.reject(false, null)
            else call.disconnect()
        }
    }

    // ---- Two calls at once ----

    fun hold() {
        ongoing()?.let { runCatching { it.hold() } }
    }

    fun unhold() {
        held()?.let { runCatching { it.unhold() } }
    }

    fun isOnHold(): Boolean = stateOf(primary() ?: return false) ==
        Call.STATE_HOLDING

    /**
     * Swaps which call you are talking to. Telecom holds the active one as
     * a side effect of resuming the other, so unholding is the whole move.
     */
    fun swap() {
        val other = held() ?: return
        runCatching { other.unhold() }
    }

    /** Joins the two calls into a conference. */
    fun merge() {
        val a = calls.firstOrNull { stateOf(it) == Call.STATE_ACTIVE }
        val b = calls.firstOrNull { it !== a && stateOf(it) == Call.STATE_HOLDING }
        if (a == null || b == null) return
        runCatching { a.conference(b) }
    }

    /** Pulls one party back out of a conference. */
    fun splitFromConference(call: Call) {
        runCatching { call.splitFromConference() }
    }

    @Synchronized
    fun conferenceChildren(): List<Call> =
        primary()?.children ?: emptyList()

    // ---- Video ----

    /** Asks the other side to turn the call into a video call. */
    fun requestVideo() {
        val call = primary() ?: return
        runCatching {
            call.videoCall?.sendSessionModifyRequest(
                VideoProfile(VideoProfile.STATE_BIDIRECTIONAL)
            )
        }
    }

    /** Drops back to audio, keeping the call up. */
    fun stopVideo() {
        val call = primary() ?: return
        runCatching {
            call.videoCall?.sendSessionModifyRequest(
                VideoProfile(VideoProfile.STATE_AUDIO_ONLY)
            )
        }
    }

    fun respondToVideoRequest(accept: Boolean) {
        val call = primary() ?: return
        runCatching {
            call.videoCall?.sendSessionModifyResponse(
                VideoProfile(
                    if (accept) VideoProfile.STATE_BIDIRECTIONAL
                    else VideoProfile.STATE_AUDIO_ONLY
                )
            )
        }
    }

    fun videoCallOf(call: Call? = primary()) = call?.videoCall

    fun setMuted(muted: Boolean) {
        runCatching { service?.setMuted(muted) }
    }

    fun isMuted(): Boolean = service?.callAudioState?.isMuted == true

    fun setSpeaker(on: Boolean) {
        setRoute(
            if (on) CallAudioState.ROUTE_SPEAKER
            else CallAudioState.ROUTE_WIRED_OR_EARPIECE
        )
    }

    fun isSpeakerOn(): Boolean = currentRoute() == CallAudioState.ROUTE_SPEAKER

    // ---- Audio routes ----

    fun setRoute(route: Int) {
        runCatching { service?.setAudioRoute(route) }
    }

    fun currentRoute(): Int =
        service?.callAudioState?.route ?: CallAudioState.ROUTE_EARPIECE

    /**
     * Where the call's audio can go right now.
     *
     * The mask is whatever hardware is actually connected, so a Bluetooth
     * headset appears the moment it pairs and disappears when it walks off.
     * Earpiece and wired headset share a route constant and are reported
     * as one; the phone decides between them by whether something is
     * plugged in.
     */
    fun availableRoutes(): List<Int> {
        val mask = service?.callAudioState?.supportedRouteMask ?: 0
        val wired = mask and CallAudioState.ROUTE_WIRED_HEADSET != 0
        return buildList {
            if (wired) {
                add(CallAudioState.ROUTE_WIRED_HEADSET)
            } else if (mask and CallAudioState.ROUTE_EARPIECE != 0) {
                add(CallAudioState.ROUTE_EARPIECE)
            }
            if (mask and CallAudioState.ROUTE_SPEAKER != 0) {
                add(CallAudioState.ROUTE_SPEAKER)
            }
            if (mask and CallAudioState.ROUTE_BLUETOOTH != 0) {
                add(CallAudioState.ROUTE_BLUETOOTH)
            }
        }
    }

    fun routeLabel(route: Int): String = when (route) {
        CallAudioState.ROUTE_SPEAKER -> "Speaker"
        CallAudioState.ROUTE_BLUETOOTH -> "Bluetooth"
        CallAudioState.ROUTE_WIRED_HEADSET -> "Headset"
        else -> "Phone"
    }

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
