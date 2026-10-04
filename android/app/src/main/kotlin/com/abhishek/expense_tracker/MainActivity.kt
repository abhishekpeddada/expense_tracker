package com.abhishek.expense_tracker

import android.Manifest
import android.app.NotificationManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.ContactsContract
import android.provider.CallLog
import android.provider.Settings
import android.provider.Telephony
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "expense_tracker/sms"
        private const val REQ_SMS_ROLE = 1001
        private const val REQ_NOTIF = 1002
        private const val REQ_DIALER_ROLE = 1003
        private const val REQ_PHONE_PERMS = 1004

        /** Plenty to read an amount off a receipt, small enough to send. */
        private const val MAX_IMAGE_EDGE = 1280

        // Set while a Flutter engine is attached, so broadcast receivers can
        // nudge the UI to drain the queue. Main-thread only.
        private var channel: MethodChannel? = null

        fun pingFlutter() {
            runCatching { channel?.invokeMethod("smsPing", null) }
        }
    }

    private var pendingRoleResult: MethodChannel.Result? = null
    private var pendingDialerResult: MethodChannel.Result? = null

    /** A receipt image shared in, waiting to be collected. */
    private var sharedImage: Uri? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        rememberSharedImage(intent)
    }

    /** A share arriving while the app is already open comes through here. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        rememberSharedImage(intent)
        if (sharedImage != null) {
            runCatching { channel?.invokeMethod("sharedImage", null) }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "isDefaultSmsApp" -> result.success(isDefaultSmsApp())
                "requestDefaultSmsRole" -> {
                    if (isDefaultSmsApp()) {
                        result.success(true)
                    } else {
                        pendingRoleResult = result
                        val rm = getSystemService(RoleManager::class.java)
                        startActivityForResult(
                            rm.createRequestRoleIntent(RoleManager.ROLE_SMS),
                            REQ_SMS_ROLE
                        )
                    }
                }
                "requestPermissions" -> {
                    // SMS permissions are normally auto-granted with
                    // ROLE_SMS, but not on every OEM build — request them
                    // explicitly so reception never silently fails.
                    val wanted = mutableListOf(
                        Manifest.permission.READ_CONTACTS,
                        Manifest.permission.RECEIVE_SMS,
                        Manifest.permission.READ_SMS,
                        Manifest.permission.SEND_SMS,
                    )
                    if (Build.VERSION.SDK_INT >= 33) {
                        wanted.add(Manifest.permission.POST_NOTIFICATIONS)
                    }
                    val missing = wanted.filter {
                        checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
                    }
                    if (missing.isNotEmpty()) {
                        ActivityCompat.requestPermissions(
                            this, missing.toTypedArray(), REQ_NOTIF
                        )
                    }
                    // OEM battery managers (Moto included) put apps in a
                    // restricted state where broadcasts are dropped — ask
                    // to be exempted so SMS_DELIVER always reaches us.
                    val pm = getSystemService(PowerManager::class.java)
                    if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                        runCatching {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        }
                    }
                    result.success(null)
                }
                "isDefaultDialer" -> result.success(isDefaultDialer())
                "requestDefaultDialerRole" -> {
                    if (isDefaultDialer()) {
                        result.success(true)
                    } else {
                        pendingDialerResult = result
                        val rm = getSystemService(RoleManager::class.java)
                        startActivityForResult(
                            rm.createRequestRoleIntent(RoleManager.ROLE_DIALER),
                            REQ_DIALER_ROLE
                        )
                    }
                }
                "requestPhonePermissions" -> {
                    val wanted = mutableListOf(
                        Manifest.permission.CALL_PHONE,
                        Manifest.permission.READ_PHONE_STATE,
                        Manifest.permission.READ_CALL_LOG,
                        Manifest.permission.READ_CONTACTS,
                    )
                    if (isDefaultDialer()) {
                        wanted.add(Manifest.permission.ANSWER_PHONE_CALLS)
                        // Only useful for video calls, but asking during a
                        // ringing one would be the worst possible moment.
                        wanted.add(Manifest.permission.CAMERA)
                    }
                    val missing = wanted.filter {
                        checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
                    }
                    if (missing.isNotEmpty()) {
                        ActivityCompat.requestPermissions(
                            this, missing.toTypedArray(), REQ_PHONE_PERMS
                        )
                    }
                    result.success(null)
                }
                "placeCall" -> {
                    val number = call.argument<String>("number")
                    val video = call.argument<Boolean>("video") ?: false
                    if (number.isNullOrBlank()) {
                        result.error("bad_args", "number is required", null)
                    } else {
                        result.success(placeCall(number, video))
                    }
                }
                "getVoicemail" -> result.success(voicemailInfo())
                "takeSharedImage" -> result.success(takeSharedImage())
                "getContacts" -> result.success(readContacts())
                "addContact" -> {
                    val number = call.argument<String>("number")
                    val name = call.argument<String>("name")
                    result.success(addContact(number, name))
                }
                "openContact" -> {
                    val id = call.argument<Int>("id")?.toLong()
                    result.success(openContact(id))
                }
                "canUseFullScreenIntent" -> result.success(canFullScreen())
                "openFullScreenIntentSettings" -> {
                    result.success(openFullScreenSettings())
                }
                "getCallLog" -> {
                    val limit = call.argument<Int>("limit") ?: 200
                    result.success(readCallLog(limit))
                }
                "getContactName" -> {
                    val number = call.argument<String>("number")
                    result.success(number?.let { lookupContactName(it) })
                }
                "drainSmsQueue" -> result.success(SmsQueue.drain(this))
                "drainSentQueue" -> result.success(SmsQueue.drainSent(this))
                "getReceiveLog" -> result.success(SmsQueue.readLog(this))
                "getAppVersion" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    result.success(
                        mapOf(
                            "versionName" to info.versionName,
                            "versionCode" to
                                if (Build.VERSION.SDK_INT >= 28)
                                    info.longVersionCode
                                else @Suppress("DEPRECATION") info.versionCode.toLong(),
                        )
                    )
                }
                "postBudgetAlert" -> {
                    val title = call.argument<String>("title") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    Notifier.postBudgetAlert(this, title, body)
                    result.success(null)
                }
                "clearReceiveLog" -> {
                    SmsQueue.clearLog(this)
                    result.success(null)
                }
                "getDiagnostics" -> {
                    val pm = getSystemService(PowerManager::class.java)
                    result.success(
                        mapOf(
                            "isDefaultSmsApp" to isDefaultSmsApp(),
                            "isDefaultDialer" to isDefaultDialer(),
                            "fullScreenCalls" to canFullScreen(),
                            "canPlaceCalls" to (checkSelfPermission(
                                Manifest.permission.CALL_PHONE
                            ) == PackageManager.PERMISSION_GRANTED),
                            "canReadCallLog" to (checkSelfPermission(
                                Manifest.permission.READ_CALL_LOG
                            ) == PackageManager.PERMISSION_GRANTED),
                            "batteryUnrestricted" to
                                pm.isIgnoringBatteryOptimizations(packageName),
                            "receiveSms" to (checkSelfPermission(
                                Manifest.permission.RECEIVE_SMS
                            ) == PackageManager.PERMISSION_GRANTED),
                            "readSms" to (checkSelfPermission(
                                Manifest.permission.READ_SMS
                            ) == PackageManager.PERMISSION_GRANTED),
                            "notifications" to (Build.VERSION.SDK_INT < 33 ||
                                checkSelfPermission(
                                    Manifest.permission.POST_NOTIFICATIONS
                                ) == PackageManager.PERMISSION_GRANTED),
                        )
                    )
                }
                "getPendingCategories" ->
                    result.success(SmsQueue.getPendingCategories(this))
                "removePendingCategory" -> {
                    val entryId = call.argument<String>("entryId")
                    if (entryId != null) SmsQueue.removePendingCategory(this, entryId)
                    result.success(null)
                }
                "sendSms" -> {
                    val to = call.argument<String>("to")
                    val body = call.argument<String>("body")
                    if (to.isNullOrBlank() || body.isNullOrBlank()) {
                        result.error("bad_args", "to and body are required", null)
                    } else {
                        runCatching {
                            @Suppress("DEPRECATION")
                            val sm = if (Build.VERSION.SDK_INT >= 31)
                                getSystemService(SmsManager::class.java)
                            else SmsManager.getDefault()
                            sm.sendMultipartTextMessage(
                                to, null, sm.divideMessage(body), null, null
                            )
                        }.fold(
                            onSuccess = { result.success(true) },
                            onFailure = { result.error("send_failed", it.message, null) }
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SMS_ROLE) {
            pendingRoleResult?.success(isDefaultSmsApp())
            pendingRoleResult = null
        }
        if (requestCode == REQ_DIALER_ROLE) {
            pendingDialerResult?.success(isDefaultDialer())
            pendingDialerResult = null
        }
    }

    // isRoleHeld is the authoritative check; getDefaultSmsPackage is stale
    // or wrong on some OEM builds even while we receive SMS_DELIVER.
    private fun isDefaultSmsApp(): Boolean {
        val rm = getSystemService(RoleManager::class.java)
        return rm.isRoleHeld(RoleManager.ROLE_SMS) ||
            Telephony.Sms.getDefaultSmsPackage(this) == packageName
    }

    /**
     * An image shared into this app, handed over once and then forgotten.
     *
     * Downscaled here rather than on the Flutter side: a screenshot off a
     * modern phone is several megabytes, and what reads a receipt only
     * needs enough pixels to see the numbers.
     */
    private fun takeSharedImage(): ByteArray? {
        val uri = sharedImage ?: return null
        sharedImage = null
        return try {
            // Measured before it is decoded: a full-resolution screenshot
            // off a modern phone is big enough to be worth never holding
            // in memory in the first place.
            val bounds = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            // decodeStream returns null when it is only measuring, so the
            // stream is opened separately rather than tested for null here.
            val measuring = contentResolver.openInputStream(uri) ?: return null
            measuring.use { BitmapFactory.decodeStream(it, null, bounds) }

            val longest = maxOf(bounds.outWidth, bounds.outHeight)
            if (longest <= 0) return null
            var sample = 1
            while (longest / (sample * 2) >= MAX_IMAGE_EDGE) sample *= 2

            val decoded = contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(
                    it,
                    null,
                    BitmapFactory.Options().apply { inSampleSize = sample },
                )
            } ?: return null

            // Sampling only halves, so one more exact step brings the long
            // edge down to the budget.
            val longestNow = maxOf(decoded.width, decoded.height)
            val scaled = if (longestNow <= MAX_IMAGE_EDGE) decoded else {
                val factor = MAX_IMAGE_EDGE.toFloat() / longestNow
                Bitmap.createScaledBitmap(
                    decoded,
                    (decoded.width * factor).toInt().coerceAtLeast(1),
                    (decoded.height * factor).toInt().coerceAtLeast(1),
                    true,
                )
            }
            ByteArrayOutputStream().use { out ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 85, out)
                out.toByteArray()
            }
        } catch (e: Throwable) {
            // A shared image is whatever another app handed over: it may be
            // gone, unreadable, or too big to decode. None of that should
            // take the app down - the person can pick a file instead.
            null
        }
    }

    /**
     * Remembers a receipt shared into the app until Flutter asks for it.
     *
     * EXTRA_STREAM is where a well-behaved share puts the image, but not
     * every app is well behaved, so the clip data and the intent's own
     * data are tried as well.
     */
    private fun rememberSharedImage(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        if (intent.type?.startsWith("image/") != true) return
        @Suppress("DEPRECATION")
        val extra = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        val uri = extra
            ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
            ?: intent.data
        if (uri != null) sharedImage = uri
    }

    private fun isDefaultDialer(): Boolean {
        val rm = getSystemService(RoleManager::class.java)
        val tm = getSystemService(TelecomManager::class.java)
        return rm.isRoleHeld(RoleManager.ROLE_DIALER) ||
            tm?.defaultDialerPackage == packageName
    }

    /**
     * Places a call. As the default dialer this goes through Telecom and
     * our own in-call screen; otherwise it is handed to whichever dialer
     * the phone is using, so the button still works before the role is
     * granted.
     */
    private fun placeCall(number: String, video: Boolean = false): Boolean {
        val uri = Uri.fromParts("tel", number, null)
        if (checkSelfPermission(Manifest.permission.CALL_PHONE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            // Asking for video up front only works where the carrier
            // carries it; Telecom falls back to audio where it does not.
            val extras = if (video) android.os.Bundle().apply {
                putInt(
                    TelecomManager.EXTRA_START_CALL_WITH_VIDEO_STATE,
                    android.telecom.VideoProfile.STATE_BIDIRECTIONAL
                )
            } else null

            val placed = runCatching {
                getSystemService(TelecomManager::class.java)
                    ?.placeCall(uri, extras)
            }.isSuccess
            if (placed) return true
        }
        // No permission, or Telecom refused: fall back to the dialer with
        // the number filled in, which never needs permission.
        return runCatching {
            startActivity(
                Intent(Intent.ACTION_DIAL, uri)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }.isSuccess
    }

    /**
     * Whether the incoming call screen is allowed to take over the display.
     *
     * From Android 14 a full-screen intent needs its own permission. It is
     * granted at install to calling apps, but it can be revoked, and when
     * it is the call screen quietly degrades to a heads-up notification
     * with no hint as to why.
     */
    private fun canFullScreen(): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        val nm = getSystemService(NotificationManager::class.java)
        return runCatching { nm.canUseFullScreenIntent() }.getOrDefault(true)
    }

    private fun openFullScreenSettings(): Boolean {
        if (Build.VERSION.SDK_INT < 34) return false
        return runCatching {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:$packageName")
                )
            )
        }.isSuccess
    }

    /** Every phone number in the contact book, one row per number. */
    private fun readContacts(): List<Map<String, Any?>> {
        if (checkSelfPermission(Manifest.permission.READ_CONTACTS) !=
            PackageManager.PERMISSION_GRANTED
        ) return emptyList()

        return runCatching {
            val out = mutableListOf<Map<String, Any?>>()
            val seen = mutableSetOf<String>()
            contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.PHOTO_URI,
                    ContactsContract.CommonDataKinds.Phone.TYPE,
                    ContactsContract.CommonDataKinds.Phone.LABEL,
                ),
                null,
                null,
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC",
            )?.use { c ->
                while (c.moveToNext()) {
                    val number = c.getString(2) ?: continue
                    val id = c.getLong(0)
                    // The same number often appears twice, once per account
                    // it syncs from; the list should not.
                    val key = "$id|${number.filter { ch -> ch.isDigit() }}"
                    if (!seen.add(key)) continue
                    out.add(
                        mapOf(
                            "id" to id,
                            "name" to c.getString(1),
                            "number" to number,
                            "photo" to c.getString(3),
                            "label" to phoneLabel(c.getInt(4), c.getString(5)),
                        )
                    )
                }
            }
            out
        }.getOrDefault(emptyList())
    }

    private fun phoneLabel(type: Int, custom: String?): String =
        ContactsContract.CommonDataKinds.Phone
            .getTypeLabel(resources, type, custom)
            .toString()

    /**
     * Hands the number to the system contact editor rather than writing
     * the contact here. It already knows about accounts, duplicates and
     * every field a contact can have, and it needs no write permission
     * from us.
     */
    private fun addContact(number: String?, name: String?): Boolean =
        runCatching {
            val intent = Intent(Intent.ACTION_INSERT_OR_EDIT)
                .setType(ContactsContract.Contacts.CONTENT_ITEM_TYPE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (!number.isNullOrBlank()) {
                intent.putExtra(ContactsContract.Intents.Insert.PHONE, number)
            }
            if (!name.isNullOrBlank()) {
                intent.putExtra(ContactsContract.Intents.Insert.NAME, name)
            }
            startActivity(intent)
        }.isSuccess

    private fun openContact(id: Long?): Boolean {
        if (id == null) return false
        return runCatching {
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setData(
                        Uri.withAppendedPath(
                            ContactsContract.Contacts.CONTENT_URI,
                            id.toString()
                        )
                    )
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }.isSuccess
    }

    /**
     * The carrier's voicemail number, and its own name for the service.
     *
     * Both come from the SIM, not from this app: the operator records the
     * message and this only says where to ring to hear it.
     *
     * There is deliberately no unread count here. getVoiceMessageCount is
     * marked @hide in the platform, so it is not ours to call; the public
     * alternative delivers a waiting flag asynchronously through a
     * listener, which is a lot of moving parts for a badge. The system
     * already shows the waiting icon in the status bar.
     */
    private fun voicemailInfo(): Map<String, Any?> {
        if (checkSelfPermission(Manifest.permission.READ_PHONE_STATE) !=
            PackageManager.PERMISSION_GRANTED
        ) return mapOf("number" to null, "label" to null)

        val tm = getSystemService(TelephonyManager::class.java)
        return mapOf(
            "number" to runCatching { tm?.voiceMailNumber }.getOrNull(),
            "label" to runCatching { tm?.voiceMailAlphaTag }.getOrNull(),
        )
    }

    /** Recent calls, newest first, for the Calls list. */
    private fun readCallLog(limit: Int): List<Map<String, Any?>> {
        if (checkSelfPermission(Manifest.permission.READ_CALL_LOG) !=
            PackageManager.PERMISSION_GRANTED
        ) return emptyList()

        return runCatching {
            val out = mutableListOf<Map<String, Any?>>()
            contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(
                    CallLog.Calls._ID,
                    CallLog.Calls.NUMBER,
                    CallLog.Calls.CACHED_NAME,
                    CallLog.Calls.TYPE,
                    CallLog.Calls.DATE,
                    CallLog.Calls.DURATION,
                ),
                null,
                null,
                "${CallLog.Calls.DATE} DESC LIMIT $limit",
            )?.use { c ->
                while (c.moveToNext()) {
                    out.add(
                        mapOf(
                            "id" to c.getLong(0),
                            "number" to c.getString(1),
                            "name" to c.getString(2),
                            "type" to c.getInt(3),
                            "date" to c.getLong(4),
                            "duration" to c.getLong(5),
                        )
                    )
                }
            }
            out
        }.getOrDefault(emptyList())
    }

    private fun lookupContactName(number: String): String? {
        if (checkSelfPermission(Manifest.permission.READ_CONTACTS) !=
            PackageManager.PERMISSION_GRANTED
        ) return null
        return runCatching {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(number)
            )
            contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null, null, null
            )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        }.getOrNull()
    }
}
