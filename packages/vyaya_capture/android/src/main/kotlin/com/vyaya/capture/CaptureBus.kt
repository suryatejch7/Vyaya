package com.vyaya.capture

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** Pushes "something new was captured" to Flutter while the app is running. */
object CaptureBus {
    private val main = Handler(Looper.getMainLooper())

    @Volatile var sink: EventChannel.EventSink? = null

    fun hasListener(): Boolean = sink != null

    fun publish(source: String) {
        main.post { sink?.success(mapOf("source" to source)) }
    }
}
