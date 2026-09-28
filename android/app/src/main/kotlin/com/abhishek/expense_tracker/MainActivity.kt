package com.abhishek.expense_tracker

import android.Manifest
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

        // Set while a Flutter engine is attached, so broadcast receivers can
        // nudge the UI to drain the queue. Main-thread only.
        private var channel: MethodChannel? = null

        fun pingFlutter() {
            runCatching { channel?.invokeMethod("smsPing", null) }
        }
    }

    private var pendingRoleResult: MethodChannel.Result? = null
    private var pendingDialerResult: MethodChannel.Result? = null

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
                    if (number.isNullOrBlank()) {
                        result.error("bad_args", "number is required", null)
                    } else {
                        result.success(placeCall(number))
                    }
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
    private fun placeCall(number: String): Boolean {
        val uri = Uri.fromParts("tel", number, null)
        if (checkSelfPermission(Manifest.permission.CALL_PHONE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            val placed = runCatching {
                getSystemService(TelecomManager::class.java)
                    ?.placeCall(uri, null)
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
