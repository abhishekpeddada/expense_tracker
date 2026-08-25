package com.abhishek.expense_tracker

import android.Manifest
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.ContactsContract
import android.provider.Settings
import android.provider.Telephony
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

        // Set while a Flutter engine is attached, so broadcast receivers can
        // nudge the UI to drain the queue. Main-thread only.
        private var channel: MethodChannel? = null

        fun pingFlutter() {
            runCatching { channel?.invokeMethod("smsPing", null) }
        }
    }

    private var pendingRoleResult: MethodChannel.Result? = null

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
                "getContactName" -> {
                    val number = call.argument<String>("number")
                    result.success(number?.let { lookupContactName(it) })
                }
                "drainSmsQueue" -> result.success(SmsQueue.drain(this))
                "getReceiveLog" -> result.success(SmsQueue.readLog(this))
                "clearReceiveLog" -> {
                    SmsQueue.clearLog(this)
                    result.success(null)
                }
                "getDiagnostics" -> {
                    val pm = getSystemService(PowerManager::class.java)
                    result.success(
                        mapOf(
                            "isDefaultSmsApp" to isDefaultSmsApp(),
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
    }

    // isRoleHeld is the authoritative check; getDefaultSmsPackage is stale
    // or wrong on some OEM builds even while we receive SMS_DELIVER.
    private fun isDefaultSmsApp(): Boolean {
        val rm = getSystemService(RoleManager::class.java)
        return rm.isRoleHeld(RoleManager.ROLE_SMS) ||
            Telephony.Sms.getDefaultSmsPackage(this) == packageName
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
