package com.abhishek.expense_tracker

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.Chronometer
import android.widget.TextView

/**
 * The call screen: who is calling, and the buttons to deal with it.
 *
 * Written in Kotlin against framework widgets rather than in Flutter. The
 * screen has to come up over the lock screen within a ring or two, and
 * booting a Dart engine to answer a phone call is a risk with no upside.
 */
class InCallActivity : Activity() {

    companion object {
        fun intent(context: Context): Intent =
            Intent(context, InCallActivity::class.java)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
    }

    private lateinit var nameView: TextView
    private lateinit var numberView: TextView
    private lateinit var statusView: TextView
    private lateinit var timerView: Chronometer
    private lateinit var answerButton: Button
    private lateinit var hangUpButton: Button
    private lateinit var muteButton: Button
    private lateinit var speakerButton: Button

    private val main = Handler(Looper.getMainLooper())
    private val onCallsChanged: () -> Unit = { main.post { render() } }
    private var timerRunning = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()
        setContentView(R.layout.activity_in_call)

        nameView = findViewById(R.id.call_name)
        numberView = findViewById(R.id.call_number)
        statusView = findViewById(R.id.call_status)
        timerView = findViewById(R.id.call_timer)
        answerButton = findViewById(R.id.call_answer)
        hangUpButton = findViewById(R.id.call_hangup)
        muteButton = findViewById(R.id.call_mute)
        speakerButton = findViewById(R.id.call_speaker)

        answerButton.setOnClickListener { CallStore.answer() }
        hangUpButton.setOnClickListener { CallStore.hangUp() }
        muteButton.setOnClickListener {
            CallStore.setMuted(!CallStore.isMuted())
            render()
        }
        speakerButton.setOnClickListener {
            CallStore.setSpeaker(!CallStore.isSpeakerOn())
            render()
        }

        CallStore.addListener(onCallsChanged)
        render()
    }

    /**
     * A ringing phone has to show this without the screen being unlocked.
     * The window flags are the pre-27 spelling of the same thing and are
     * still what some OEM builds actually honour, so both are set.
     */
    @Suppress("DEPRECATION")
    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            getSystemService(KeyguardManager::class.java)
                ?.requestDismissKeyguard(this, null)
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        render()
    }

    override fun onDestroy() {
        CallStore.removeListener(onCallsChanged)
        super.onDestroy()
    }

    /** Back must not hang up, and must not hide a ringing call either. */
    override fun onBackPressed() {
        val call = CallStore.primary()
        if (call != null && CallStore.isIncoming(call)) return
        super.onBackPressed()
    }

    private fun render() {
        val call = CallStore.primary()
        if (call == null) {
            finishAndRemoveTask()
            return
        }

        val number = CallStore.numberOf(call)
        val name = CallStore.callerNameOf(call)
            ?: number?.let { Contacts.nameFor(this, it) }

        nameView.text = name ?: number ?: "Unknown number"
        numberView.text = if (name != null && number != null) number else ""
        numberView.visibility =
            if (numberView.text.isNullOrEmpty()) View.GONE else View.VISIBLE
        statusView.text = CallStore.labelFor(call)

        val ringing = CallStore.isIncoming(call)
        answerButton.visibility = if (ringing) View.VISIBLE else View.GONE
        hangUpButton.text = if (ringing) "Decline" else "End"

        // Mute and speaker are meaningless until there is audio to route.
        val connected = CallStore.isOngoing(call)
        muteButton.isEnabled = connected
        speakerButton.isEnabled = connected
        muteButton.text = if (CallStore.isMuted()) "Unmute" else "Mute"
        speakerButton.text =
            if (CallStore.isSpeakerOn()) "Speaker on" else "Speaker"

        renderTimer(call)

        if (CallStore.stateOf(call) == Call.STATE_DISCONNECTED) {
            main.postDelayed({ if (!isFinishing) finishAndRemoveTask() }, 1200)
        }
    }

    private fun renderTimer(call: Call) {
        val connectedAt = CallStore.connectTimeOf(call)
        if (CallStore.isOngoing(call) && connectedAt > 0) {
            if (!timerRunning) {
                // Chronometer counts from elapsed-realtime, while the call
                // reports a wall-clock instant; this converts between them.
                timerView.base = android.os.SystemClock.elapsedRealtime() -
                    (System.currentTimeMillis() - connectedAt)
                timerView.start()
                timerRunning = true
            }
            timerView.visibility = View.VISIBLE
        } else {
            if (timerRunning) {
                timerView.stop()
                timerRunning = false
            }
            timerView.visibility = View.GONE
        }
    }
}
