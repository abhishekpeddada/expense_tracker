package com.abhishek.expense_tracker

import android.app.Activity
import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.ContactsContract
import android.telecom.Call
import android.view.View
import android.view.WindowManager
import android.widget.Chronometer
import android.widget.EditText
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

/**
 * The call screen: who is calling, and what can be done about it.
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

        private val AVATAR_COLOURS = intArrayOf(
            0xFF1F6F63.toInt(), 0xFF5C6BC0.toInt(), 0xFF8E24AA.toInt(),
            0xFFEF6C00.toInt(), 0xFF00838F.toInt(), 0xFF6D4C41.toInt(),
        )
    }

    private lateinit var nameView: TextView
    private lateinit var numberView: TextView
    private lateinit var statusView: TextView
    private lateinit var timerView: Chronometer
    private lateinit var initialsView: TextView
    private lateinit var photoView: ImageView
    private lateinit var controlsRow: LinearLayout
    private lateinit var replyRow: LinearLayout
    private lateinit var answerColumn: LinearLayout
    private lateinit var answerButton: ImageButton
    private lateinit var hangUpButton: ImageButton
    private lateinit var hangUpLabel: TextView
    private lateinit var muteButton: ImageButton
    private lateinit var muteLabel: TextView
    private lateinit var speakerButton: ImageButton
    private lateinit var speakerLabel: TextView
    private lateinit var keypadButton: ImageButton

    private val main = Handler(Looper.getMainLooper())
    private val onCallsChanged: () -> Unit = { main.post { render() } }
    private var timerRunning = false

    /** Avatar and name lookups are slow enough to be worth doing once. */
    private var shownNumber: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()
        setContentView(R.layout.activity_in_call)

        nameView = findViewById(R.id.call_name)
        numberView = findViewById(R.id.call_number)
        statusView = findViewById(R.id.call_status)
        timerView = findViewById(R.id.call_timer)
        initialsView = findViewById(R.id.call_initials)
        photoView = findViewById(R.id.call_photo)
        controlsRow = findViewById(R.id.call_controls)
        replyRow = findViewById(R.id.call_reply_row)
        answerColumn = findViewById(R.id.call_answer_column)
        answerButton = findViewById(R.id.call_answer)
        hangUpButton = findViewById(R.id.call_hangup)
        hangUpLabel = findViewById(R.id.call_hangup_label)
        muteButton = findViewById(R.id.call_mute)
        muteLabel = findViewById(R.id.call_mute_label)
        speakerButton = findViewById(R.id.call_speaker)
        speakerLabel = findViewById(R.id.call_speaker_label)
        keypadButton = findViewById(R.id.call_keypad)

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
        keypadButton.setOnClickListener { showKeypad() }
        findViewById<ImageButton>(R.id.call_reply).setOnClickListener {
            showQuickReplies()
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
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        val call = CallStore.primary()
        if (call != null && CallStore.isIncoming(call)) return
        @Suppress("DEPRECATION")
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

        if (shownNumber != number) {
            shownNumber = number
            renderAvatar(name, number)
        }

        val ringing = CallStore.isIncoming(call)
        answerColumn.visibility = if (ringing) View.VISIBLE else View.GONE
        replyRow.visibility =
            if (ringing && QuickReply.canSend(this) && number != null)
                View.VISIBLE else View.GONE
        // Controls would sit under the ringing layout with nothing to do.
        controlsRow.visibility = if (ringing) View.INVISIBLE else View.VISIBLE
        hangUpLabel.text = if (ringing) "Decline" else "End"
        hangUpButton.setImageResource(
            if (ringing) R.drawable.ic_call_decline else R.drawable.ic_call_end
        )

        val connected = CallStore.isOngoing(call)
        muteButton.isEnabled = connected
        speakerButton.isEnabled = connected
        keypadButton.isEnabled = connected

        val muted = CallStore.isMuted()
        muteButton.setImageResource(
            if (muted) R.drawable.ic_mic_off else R.drawable.ic_mic
        )
        muteLabel.text = if (muted) "Unmute" else "Mute"
        setActive(muteButton, muted)

        val speaker = CallStore.isSpeakerOn()
        speakerLabel.text = if (speaker) "Speaker on" else "Speaker"
        setActive(speakerButton, speaker)

        renderTimer(call)

        if (CallStore.stateOf(call) == Call.STATE_DISCONNECTED) {
            main.postDelayed({ if (!isFinishing) finishAndRemoveTask() }, 1200)
        }
    }

    /** A toggled control inverts, the way every dialer shows "on". */
    private fun setActive(button: ImageButton, active: Boolean) {
        button.setBackgroundResource(
            if (active) R.drawable.bg_circle_active
            else R.drawable.bg_circle_slate
        )
        button.imageTintList = android.content.res.ColorStateList.valueOf(
            if (active) Color.BLACK else Color.WHITE
        )
    }

    private fun renderAvatar(name: String?, number: String?) {
        val photo = number?.let { contactPhoto(it) }
        if (photo != null) {
            photoView.setImageBitmap(photo)
            photoView.clipToOutline = true
            photoView.outlineProvider =
                object : android.view.ViewOutlineProvider() {
                    override fun getOutline(
                        view: View,
                        outline: android.graphics.Outline
                    ) = outline.setOval(0, 0, view.width, view.height)
                }
            photoView.visibility = View.VISIBLE
            return
        }

        photoView.visibility = View.GONE
        val letter = name?.trim()?.firstOrNull()?.uppercaseChar()
        initialsView.text = letter?.toString() ?: ""
        if (letter == null) {
            initialsView.setBackgroundResource(R.drawable.bg_circle_slate)
            initialsView.setCompoundDrawablesWithIntrinsicBounds(
                0, R.drawable.ic_person, 0, 0
            )
        } else {
            initialsView.setCompoundDrawablesWithIntrinsicBounds(0, 0, 0, 0)
            // Same colour for the same person every time, rather than a
            // shade that changes with each call.
            val key = (number ?: name).hashCode()
            val colour = AVATAR_COLOURS[
                Math.floorMod(key, AVATAR_COLOURS.size)
            ]
            initialsView.background =
                android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.OVAL
                    setColor(colour)
                }
        }
    }

    private fun contactPhoto(number: String): android.graphics.Bitmap? {
        if (checkSelfPermission(android.Manifest.permission.READ_CONTACTS) !=
            android.content.pm.PackageManager.PERMISSION_GRANTED
        ) return null
        return runCatching {
            val lookup = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(number)
            )
            val id = contentResolver.query(
                lookup,
                arrayOf(ContactsContract.PhoneLookup._ID),
                null, null, null
            )?.use { c -> if (c.moveToFirst()) c.getLong(0) else null }
                ?: return null

            val contactUri = ContentUris.withAppendedId(
                ContactsContract.Contacts.CONTENT_URI, id
            )
            ContactsContract.Contacts.openContactPhotoInputStream(
                contentResolver, contactUri, true
            )?.use { BitmapFactory.decodeStream(it) }
        }.getOrNull()
    }

    private fun renderTimer(call: Call) {
        val connectedAt = CallStore.connectTimeOf(call)
        if (CallStore.isOngoing(call) && connectedAt > 0) {
            if (!timerRunning) {
                // Chronometer counts from elapsed-realtime, while the call
                // reports a wall-clock instant; this converts between them.
                timerView.base = SystemClock.elapsedRealtime() -
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

    /** Canned replies, plus writing one. Rejects the call either way. */
    private fun showQuickReplies() {
        val number = CallStore.numberOf(CallStore.primary() ?: return)
            ?: return
        val options = QuickReply.canned + "Write your own..."

        AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
            .setTitle("Reply and decline")
            .setItems(options.toTypedArray()) { _, which ->
                if (which == QuickReply.canned.size) {
                    askForReply(number)
                } else {
                    sendAndDecline(number, QuickReply.canned[which])
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun askForReply(number: String) {
        val input = EditText(this).apply {
            hint = "Message"
            setSingleLine(false)
            maxLines = 4
        }
        AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
            .setTitle("Reply and decline")
            .setView(input)
            .setPositiveButton("Send") { _, _ ->
                sendAndDecline(number, input.text.toString().trim())
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun sendAndDecline(number: String, text: String) {
        if (text.isBlank()) return
        val sent = QuickReply.send(this, number, text)
        Toast.makeText(
            this,
            if (sent) "Message sent" else "Could not send the message",
            Toast.LENGTH_SHORT
        ).show()
        // Declining regardless: the caller is waiting either way, and a
        // failed text is not a reason to keep ringing.
        CallStore.hangUp()
    }

    /** DTMF tones for phone menus, once a call is connected. */
    private fun showKeypad() {
        val digits = arrayOf(
            "1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"
        )
        AlertDialog.Builder(this, android.R.style.Theme_Material_Dialog_Alert)
            .setTitle("Keypad")
            .setItems(digits) { _, which ->
                CallStore.playDtmf(digits[which][0])
                showKeypad()
            }
            .setNegativeButton("Done", null)
            .show()
    }
}
