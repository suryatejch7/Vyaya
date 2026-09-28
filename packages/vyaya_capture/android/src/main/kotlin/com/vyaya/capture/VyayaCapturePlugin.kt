package com.vyaya.capture

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Bridge between the native capture queue and Flutter. */
class VyayaCapturePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var context: Context
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "vyaya_capture").also { it.setMethodCallHandler(this) }
        events = EventChannel(binding.binaryMessenger, "vyaya_capture/events").also { it.setStreamHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        CaptureBus.sink = null
        methods = null
        events = null
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        CaptureBus.sink = sink
    }

    override fun onCancel(arguments: Any?) {
        CaptureBus.sink = null
    }

    /** Runs [work] off the main thread and replies on it. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            val outcome = runCatching(work)
            main.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error("capture_error", it.message, null) }
                )
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isNotificationAccessGranted" -> result.success(isListenerEnabled())
            "openNotificationAccessSettings" -> {
                startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                result.success(null)
            }
            "openAppDetails" -> {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.fromParts("package", context.packageName, null))
                )
                result.success(null)
            }
            "requestRebind" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isListenerEnabled()) {
                    runCatching {
                        NotificationListenerService.requestRebind(
                            ComponentName(context, PaymentNotificationListener::class.java)
                        )
                    }
                }
                result.success(null)
            }
            "hasSmsPermission" -> result.success(
                granted(Manifest.permission.RECEIVE_SMS) && granted(Manifest.permission.READ_SMS)
            )
            "fetchPending" -> {
                val limit = call.argument<Int>("limit") ?: 200
                background(result) { CaptureStore.get(context).pending(limit) }
            }
            "markConsumed" -> {
                val ids = (call.argument<List<Any>>("ids") ?: emptyList())
                    .mapNotNull { (it as? Number)?.toLong() }
                background(result) { CaptureStore.get(context).markConsumed(ids); null }
            }
            "forget" -> {
                val ids = (call.argument<List<Any>>("ids") ?: emptyList())
                    .mapNotNull { (it as? Number)?.toLong() }
                background(result) { CaptureStore.get(context).forget(ids); null }
            }
            "pendingCount" -> background(result) { CaptureStore.get(context).pendingCount() }
            "backfillSms" -> {
                val since = (call.argument<Any>("sinceMillis") as? Number)?.toLong() ?: 0L
                val limit = call.argument<Int>("limit") ?: 1000
                if (!granted(Manifest.permission.READ_SMS)) {
                    result.error("no_permission", "READ_SMS not granted", null)
                } else {
                    background(result) { backfill(since, limit) }
                }
            }
            "setNotifierEnabled" -> {
                CaptureNotifier.setEnabled(context, call.argument<Boolean>("enabled") ?: true)
                result.success(null)
            }
            "clearNotifier" -> {
                CaptureNotifier.clear(context)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startActivity(intent: Intent) {
        runCatching { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    private fun granted(permission: String): Boolean =
        context.checkPermission(permission, android.os.Process.myPid(), android.os.Process.myUid()) ==
            PackageManager.PERMISSION_GRANTED

    private fun isListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: return false
        return flat.split(":").any { ComponentName.unflattenFromString(it)?.packageName == context.packageName }
    }

    /**
     * Queues transaction-like SMS from the inbox received after [sinceMs].
     * Goes back by date: every message in the window is checked, and [limit]
     * caps only how many payment-like ones are taken (OTPs and promos don't
     * count towards it, so a busy inbox still reaches the full 30 days).
     */
    private fun backfill(sinceMs: Long, limit: Int): Int {
        val store = CaptureStore.get(context)
        var queued = 0
        var matched = 0
        val cursor = context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} >= ?",
            arrayOf(sinceMs.toString()),
            "${Telephony.Sms.DATE} DESC"
        ) ?: return 0
        cursor.use {
            while (it.moveToNext() && matched < limit) {
                val sender = it.getString(0) ?: continue
                val body = it.getString(1)?.trim() ?: continue
                val date = it.getLong(2)
                if (!CaptureFilter.looksLikeTransaction(body)) continue
                matched++
                if (store.insert("sms", sender, body, date, backfill = true)) queued++
            }
        }
        return queued
    }
}
