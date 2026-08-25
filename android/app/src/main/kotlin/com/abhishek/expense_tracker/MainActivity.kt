package com.abhishek.expense_tracker

import android.Manifest
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
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
            channel?.invokeMethod("smsPing", null)
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
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(
                            this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIF
                        )
                    }
                    result.success(null)
                }
                "drainSmsQueue" -> result.success(SmsQueue.drain(this))
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

    private fun isDefaultSmsApp(): Boolean =
        Telephony.Sms.getDefaultSmsPackage(this) == packageName
}
