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
