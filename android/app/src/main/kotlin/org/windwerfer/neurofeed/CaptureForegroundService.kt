package org.windwerfer.neurofeed

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

class CaptureForegroundService : Service() {
    companion object {
        const val ACTION_START = "org.windwerfer.neurofeed.CAPTURE_FGS_START"
        const val ACTION_REQUEST_STOP = "org.windwerfer.neurofeed.CAPTURE_FGS_REQUEST_STOP"
        const val EXTRA_KIND = "kind"
        const val EXTRA_STARTED_AT_MS = "startedAtMs"
        const val EXTRA_ELAPSED_SECONDS = "elapsedSeconds"
        const val EXTRA_UNSAVED = "unsaved"

        private const val CHANNEL_ID = "capture"
        private const val NOTIFICATION_ID = 7107
        private const val TAG = "neurofeed_fgs"

        @Volatile
        private var instance: CaptureForegroundService? = null

        val isRunning: Boolean
            get() = instance != null

        fun apply(
            context: Context,
            kind: String,
            startedAtMs: Long,
            elapsedSeconds: Int,
            unsaved: Boolean,
        ) {
            val running = instance
            if (running != null) {
                running.handler.post {
                    running.applyState(kind, startedAtMs, elapsedSeconds, unsaved)
                }
                return
            }
            val intent = Intent(context, CaptureForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_KIND, kind)
                putExtra(EXTRA_STARTED_AT_MS, startedAtMs)
                putExtra(EXTRA_ELAPSED_SECONDS, elapsedSeconds)
                putExtra(EXTRA_UNSAVED, unsaved)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                @Suppress("DEPRECATION")
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CaptureForegroundService::class.java))
        }

        internal fun formatElapsed(totalSeconds: Int): String {
            val s = if (totalSeconds < 0) 0 else totalSeconds
            val h = s / 3600
            val m = (s % 3600) / 60
            val r = s % 60
            return if (h > 0) {
                String.format("%d:%02d:%02d", h, m, r)
            } else {
                String.format("%d:%02d", m, r)
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            if (unsaved) return
            elapsedSeconds = elapsedFromStart()
            postNotification()
            handler.postDelayed(this, 1000L)
        }
    }

    private var kind: String = "recording"
    private var startedAtMs: Long = 0L
    private var elapsedSeconds: Int = 0
    private var unsaved: Boolean = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        ensureChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_REQUEST_STOP) {
            CaptureForegroundBridge.requestStop()
            return START_STICKY
        }
        val k = intent?.getStringExtra(EXTRA_KIND) ?: kind
        val started = intent?.getLongExtra(EXTRA_STARTED_AT_MS, startedAtMs) ?: startedAtMs
        val elapsed = intent?.getIntExtra(EXTRA_ELAPSED_SECONDS, elapsedSeconds) ?: elapsedSeconds
        val saved = intent?.getBooleanExtra(EXTRA_UNSAVED, unsaved) ?: unsaved
        applyState(k, started, elapsed, saved)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        instance = null
        if (Build.VERSION.SDK_INT >= 24) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun applyState(
        nextKind: String,
        nextStartedAtMs: Long,
        nextElapsed: Int,
        nextUnsaved: Boolean,
    ) {
        kind = if (nextKind == "session") "session" else "recording"
        startedAtMs = nextStartedAtMs
        elapsedSeconds = if (nextElapsed < 0) 0 else nextElapsed
        unsaved = nextUnsaved
        if (!unsaved && startedAtMs <= 0L) {
            startedAtMs = System.currentTimeMillis() - elapsedSeconds * 1000L
        }
        postNotification()
        syncTicker()
    }

    private fun syncTicker() {
        handler.removeCallbacks(tick)
        if (!unsaved) {
            handler.postDelayed(tick, 1000L)
        }
    }

    private fun elapsedFromStart(): Int {
        if (startedAtMs <= 0L) return elapsedSeconds
        val delta = ((System.currentTimeMillis() - startedAtMs) / 1000L).toInt()
        return if (delta < 0) 0 else delta
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.capture_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.setShowBadge(false)
        channel.enableVibration(false)
        channel.enableLights(false)
        manager.createNotificationChannel(channel)
    }

    private fun postNotification() {
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForeground failed", e)
        }
    }

    private fun buildNotification(): Notification {
        val title = if (kind == "session") {
            getString(R.string.capture_session)
        } else {
            getString(R.string.capture_recording)
        }
        val text = formatElapsed(if (unsaved) elapsedSeconds else elapsedFromStart())
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launch.action = Intent.ACTION_MAIN
        launch.addCategory(Intent.CATEGORY_LAUNCHER)
        launch.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
        )
        val tapFlags = pendingFlags()
        val tap = PendingIntent.getActivity(this, 0, launch, tapFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(tap)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
        if (Build.VERSION.SDK_INT >= 21) {
            builder.setVisibility(Notification.VISIBILITY_PUBLIC)
        }
        if (Build.VERSION.SDK_INT >= 31) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        if (!unsaved) {
            val stopIntent = Intent(this, CaptureForegroundService::class.java).apply {
                action = ACTION_REQUEST_STOP
            }
            val stopPi = PendingIntent.getService(this, 1, stopIntent, tapFlags)
            builder.addAction(
                0,
                getString(R.string.capture_stop),
                stopPi,
            )
        }
        return builder.build()
    }

    private fun pendingFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }
}

internal object CaptureForegroundBridge {
    @Volatile
    var messenger: io.flutter.plugin.common.BinaryMessenger? = null

    /// Asks Dart to stop keepable capture. No-op if the Flutter engine is gone
    /// (must not tear down BLE from this path).
    fun requestStop() {
        val m = messenger ?: return
        Handler(Looper.getMainLooper()).post {
            try {
                io.flutter.plugin.common.MethodChannel(m, "neurofeed/capture_fgs")
                    .invokeMethod("stopRequested", null)
            } catch (e: Exception) {
                Log.w("neurofeed_fgs", "stopRequested not delivered", e)
            }
        }
    }
}
