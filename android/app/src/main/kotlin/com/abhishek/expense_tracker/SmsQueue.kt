package com.abhishek.expense_tracker

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * SharedPreferences-backed queue of incoming SMS. The broadcast receiver
 * appends here (the Flutter engine may not be running), and the Flutter side
 * drains it on launch/resume or when pinged.
 */
object SmsQueue {
    private const val PREFS = "sms_queue"
    private const val KEY = "entries"
    private const val KEY_PENDING = "pending_categories"
    private const val KEY_LOG = "receive_log"
    private const val LOG_MAX = 50
    private const val KEY_SEEN = "seen_keys"
    private const val SEEN_MAX = 40

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    @Synchronized
    fun add(ctx: Context, id: String, sender: String, body: String, ts: Long) {
        val arr = JSONArray(prefs(ctx).getString(KEY, "[]"))
        arr.put(JSONObject().apply {
            put("id", id)
            put("sender", sender)
            put("body", body)
            put("ts", ts)
        })
        prefs(ctx).edit().putString(KEY, arr.toString()).apply()
    }

    /** Records the category picked from a notification quick-action. */
    @Synchronized
    fun setCategory(ctx: Context, id: String, category: String) {
        val arr = JSONArray(prefs(ctx).getString(KEY, "[]"))
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.getString("id") == id) {
                o.put("category", category)
                break
            }
        }
        prefs(ctx).edit().putString(KEY, arr.toString()).apply()
    }

    /**
     * Category picked on a notification for an SMS that may have already been
     * drained into the app's DB. Kept until the Dart side confirms it found
     * and updated the matching transaction.
     */
    @Synchronized
    fun addPendingCategory(ctx: Context, entryId: String, category: String) {
        val obj = JSONObject(prefs(ctx).getString(KEY_PENDING, "{}"))
        obj.put(entryId, category)
        prefs(ctx).edit().putString(KEY_PENDING, obj.toString()).apply()
    }

    @Synchronized
    fun getPendingCategories(ctx: Context): Map<String, String> {
        val obj = JSONObject(prefs(ctx).getString(KEY_PENDING, "{}"))
        val out = mutableMapOf<String, String>()
        for (k in obj.keys()) out[k] = obj.getString(k)
        return out
    }

    @Synchronized
    fun removePendingCategory(ctx: Context, entryId: String) {
        val obj = JSONObject(prefs(ctx).getString(KEY_PENDING, "{}"))
        obj.remove(entryId)
        prefs(ctx).edit().putString(KEY_PENDING, obj.toString()).apply()
    }

    /**
     * Records a message as handled, returning true only the first time.
     * SMS_DELIVER and SMS_RECEIVED both fire while we are the default app,
     * so whichever arrives first wins and the other is ignored.
     */
    @Synchronized
    fun markSeen(ctx: Context, sender: String, body: String, ts: Long): Boolean {
        val key = "$sender|$ts|${body.hashCode()}"
        val arr = JSONArray(prefs(ctx).getString(KEY_SEEN, "[]"))
        for (i in 0 until arr.length()) {
            if (arr.getString(i) == key) return false
        }
        arr.put(key)
        val trimmed = JSONArray()
        val start = maxOf(0, arr.length() - SEEN_MAX)
        for (i in start until arr.length()) trimmed.put(arr.getString(i))
        prefs(ctx).edit().putString(KEY_SEEN, trimmed.toString()).apply()
        return true
    }

    /**
     * Append-only diagnostic log of what the receiver saw, so reception
     * problems can be inspected in-app instead of needing adb.
     */
    @Synchronized
    fun log(ctx: Context, message: String) {
        val arr = JSONArray(prefs(ctx).getString(KEY_LOG, "[]"))
        arr.put(JSONObject().apply {
            put("ts", System.currentTimeMillis())
            put("message", message)
        })
        // keep only the most recent LOG_MAX entries
        val trimmed = JSONArray()
        val start = maxOf(0, arr.length() - LOG_MAX)
        for (i in start until arr.length()) trimmed.put(arr.getJSONObject(i))
        prefs(ctx).edit().putString(KEY_LOG, trimmed.toString()).apply()
    }

    @Synchronized
    fun readLog(ctx: Context): List<Map<String, Any?>> {
        val arr = JSONArray(prefs(ctx).getString(KEY_LOG, "[]"))
        val out = mutableListOf<Map<String, Any?>>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            out.add(mapOf("ts" to o.getLong("ts"), "message" to o.getString("message")))
        }
        return out.reversed()
    }

    @Synchronized
    fun clearLog(ctx: Context) {
        prefs(ctx).edit().putString(KEY_LOG, "[]").apply()
    }

    /** Returns all queued entries and clears the queue. */
    @Synchronized
    fun drain(ctx: Context): List<Map<String, Any?>> {
        val arr = JSONArray(prefs(ctx).getString(KEY, "[]"))
        val out = mutableListOf<Map<String, Any?>>()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            out.add(
                mapOf(
                    "id" to o.getString("id"),
                    "sender" to o.getString("sender"),
                    "body" to o.getString("body"),
                    "ts" to o.getLong("ts"),
                    "category" to if (o.has("category")) o.getString("category") else null,
                )
            )
        }
        prefs(ctx).edit().putString(KEY, "[]").apply()
        return out
    }
}
