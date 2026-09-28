package com.vyaya.capture

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * On-device queue of captured messages. Survives the app being closed; the
 * Flutter side drains it (fetchPending -> process -> markConsumed).
 * A UNIQUE dedup key drops the same message seen twice (e.g. a notification
 * re-posted, or an SMS received live and again during inbox import).
 */
class CaptureStore private constructor(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DB_NAME, null, DB_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE captures (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              source TEXT NOT NULL,
              sender TEXT NOT NULL,
              body TEXT NOT NULL,
              posted_at INTEGER NOT NULL,
              backfill INTEGER NOT NULL DEFAULT 0,
              dedup_key TEXT NOT NULL UNIQUE,
              consumed INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX idx_captures_pending ON captures (consumed, posted_at)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    /** Returns true if the message was new. */
    fun insert(source: String, sender: String, body: String, postedAt: Long, backfill: Boolean): Boolean {
        val key = "$source|${sender.lowercase()}|${body.trim().hashCode()}|${postedAt / 60_000L}"
        val values = ContentValues().apply {
            put("source", source)
            put("sender", sender)
            put("body", body)
            put("posted_at", postedAt)
            put("backfill", if (backfill) 1 else 0)
            put("dedup_key", key)
        }
        return writableDatabase.insertWithOnConflict(
            "captures", null, values, SQLiteDatabase.CONFLICT_IGNORE
        ) != -1L
    }

    fun pending(limit: Int): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        readableDatabase.query(
            "captures",
            arrayOf("id", "source", "sender", "body", "posted_at", "backfill"),
            "consumed = 0", null, null, null,
            "posted_at ASC", limit.toString()
        ).use { c ->
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(0),
                        "source" to c.getString(1),
                        "sender" to c.getString(2),
                        "body" to c.getString(3),
                        "postedAt" to c.getLong(4),
                        "backfill" to (c.getInt(5) == 1)
                    )
                )
            }
        }
        return out
    }

    fun pendingCount(): Int =
        readableDatabase.rawQuery("SELECT COUNT(*) FROM captures WHERE consumed = 0", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }

    /**
     * Forgets captures completely (the user removed them from the review
     * list), so a later SMS import can queue those messages again.
     */
    fun forget(ids: List<Long>) {
        if (ids.isEmpty()) return
        val db = writableDatabase
        db.beginTransaction()
        try {
            for (chunk in ids.chunked(500)) {
                val placeholders = chunk.joinToString(",") { "?" }
                db.execSQL(
                    "DELETE FROM captures WHERE id IN ($placeholders)",
                    chunk.map { it.toString() }.toTypedArray()
                )
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun markConsumed(ids: List<Long>) {
        if (ids.isEmpty()) return
        val db = writableDatabase
        db.beginTransaction()
        try {
            for (chunk in ids.chunked(500)) {
                val placeholders = chunk.joinToString(",") { "?" }
                db.execSQL(
                    "UPDATE captures SET consumed = 1 WHERE id IN ($placeholders)",
                    chunk.map { it.toString() }.toTypedArray()
                )
            }
            // Keep the table small: forget processed rows after 60 days.
            val cutoff = System.currentTimeMillis() - 60L * 24 * 60 * 60 * 1000
            db.execSQL("DELETE FROM captures WHERE consumed = 1 AND posted_at < ?", arrayOf(cutoff.toString()))
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    companion object {
        private const val DB_NAME = "vyaya_capture_queue.db"
        private const val DB_VERSION = 1

        @Volatile private var instance: CaptureStore? = null

        fun get(context: Context): CaptureStore =
            instance ?: synchronized(this) {
                instance ?: CaptureStore(context).also { instance = it }
            }
    }
}
