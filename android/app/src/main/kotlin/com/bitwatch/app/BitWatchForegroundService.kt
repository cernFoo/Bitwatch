package com.bitwatch.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.TrafficStats
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

/**
 * Always-on foreground service that:
 *  1. Owns the persistent, non-dismissible status bar notification.
 *  2. Ticks once per second, sampling TrafficStats deltas for live combined
 *     upload/download speed, and periodically re-queries NetworkStatsManager
 *     for today's Mobile/Wi-Fi totals.
 *  3. Renders the *download* speed onto the small status bar icon via
 *     [SpeedIconFactory] (spec: status bar shows download speed only).
 *  4. Immediately re-posts the notification if the system reports it was
 *     dismissed, since some OEM launchers allow swiping away notifications
 *     that are merely setOngoing(true) without also being a genuine
 *     non-dismissible foreground-service notification on their skin.
 *
 * Timer state (active/paused/elapsed/bytes) is pushed in from the Dart side
 * via MainActivity's MethodChannel handler and cached here in a companion
 * object so it survives independently of whether the Flutter UI is attached.
 */
class BitWatchForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "bitwatch_monitor_channel"
        const val NOTIFICATION_ID = 4201

        const val ACTION_START = "com.bitwatch.app.action.START"
        const val ACTION_STOP = "com.bitwatch.app.action.STOP"
        const val ACTION_UPDATE_TIMER = "com.bitwatch.app.action.UPDATE_TIMER"
        const val ACTION_RESHOW_NOTIFICATION = "com.bitwatch.app.action.RESHOW"

        const val EXTRA_TIMER_ACTIVE = "timerActive"
        const val EXTRA_TIMER_PAUSED = "timerPaused"
        const val EXTRA_TIMER_ELAPSED = "timerElapsed"
        const val EXTRA_TIMER_BYTES = "timerBytes"

        // Shared with MainActivity's EventChannel loop so both surfaces
        // (in-app UI and notification) reflect the same timer numbers even
        // though they're driven from two different Kotlin components.
        @Volatile var timerActive: Boolean = false
        @Volatile var timerPaused: Boolean = false
        @Volatile var timerElapsedSeconds: Int = 0
        @Volatile var timerBytes: Long = 0
        // -1 means "no countdown limit set" (count-up / stopwatch mode).
        @Volatile var timerRemainingSeconds: Int = -1

        fun start(context: Context) {
            val intent = Intent(context, BitWatchForegroundService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, BitWatchForegroundService::class.java)
                .setAction(ACTION_STOP)
            context.startService(intent)
        }

        fun updateTimer(
            context: Context,
            active: Boolean,
            paused: Boolean,
            elapsedSeconds: Int,
            bytes: Long,
            remainingSeconds: Int = -1
        ) {
            timerActive = active
            timerPaused = paused
            timerElapsedSeconds = elapsedSeconds
            timerBytes = bytes
            timerRemainingSeconds = remainingSeconds
            // Nudge the running service to redraw immediately rather than
            // waiting up to a second for the next natural tick.
            val intent = Intent(context, BitWatchForegroundService::class.java)
                .setAction(ACTION_UPDATE_TIMER)
            context.startService(intent)
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var notificationManager: NotificationManager

    private var lastRx = 0L
    private var lastTx = 0L
    private var lastTickAtMs = 0L
    private var tickCount = 0

    private var cachedMobileBytes = 0L
    private var cachedWifiBytes = 0L

    private val tickRunnable = object : Runnable {
        override fun run() {
            tick()
            handler.postDelayed(this, 1000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        notificationManager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createChannelIfNeeded()
        lastRx = TrafficStats.getTotalRxBytes().coerceAtLeast(0)
        lastTx = TrafficStats.getTotalTxBytes().coerceAtLeast(0)
        lastTickAtMs = System.currentTimeMillis()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                handler.removeCallbacks(tickRunnable)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE_TIMER -> {
                // Companion object fields already updated by updateTimer();
                // just redraw using the last known speed sample so the
                // notification's timer line updates without waiting a full
                // second.
                notificationManager.notify(NOTIFICATION_ID, buildNotification(0, 0))
            }
            else -> {
                startForeground(NOTIFICATION_ID, buildNotification(0, 0))
                handler.removeCallbacks(tickRunnable)
                handler.post(tickRunnable)
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        // User swiped BitWatch away from Recents: keep monitoring running
        // per spec (service must not be tied to the activity's lifecycle).
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        handler.removeCallbacks(tickRunnable)
        super.onDestroy()
    }

    private fun tick() {
        val now = System.currentTimeMillis()
        val elapsedMs = (now - lastTickAtMs).coerceAtLeast(1)
        val rx = TrafficStats.getTotalRxBytes().coerceAtLeast(0)
        val tx = TrafficStats.getTotalTxBytes().coerceAtLeast(0)

        val downloadBps = (((rx - lastRx).coerceAtLeast(0)) * 1000L / elapsedMs)
        val uploadBps = (((tx - lastTx).coerceAtLeast(0)) * 1000L / elapsedMs)

        lastRx = rx
        lastTx = tx
        lastTickAtMs = now
        tickCount++

        // Re-query NetworkStatsManager for "today" totals every 5s: it's a
        // heavier system call than TrafficStats and doesn't need per-second
        // resolution for a notification readout.
        if (tickCount % 5 == 0 || tickCount == 1) {
            try {
                val usage = NetworkStatsHelper.getTodayUsage(applicationContext)
                cachedMobileBytes = usage.mobileBytes
                cachedWifiBytes = usage.wifiBytes
            } catch (_: Exception) {
                // Keep last known good values if the query fails transiently.
            }
        }

        notificationManager.notify(NOTIFICATION_ID, buildNotification(downloadBps, uploadBps))
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val existing = notificationManager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "BitWatch Monitoring",
            NotificationManager.IMPORTANCE_LOW // low = no sound/heads-up for a per-second updater
        ).apply {
            description = "Ongoing network speed & data usage monitoring"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun contentPendingIntent(): PendingIntent {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(this, 0, launchIntent, flags)
    }

    private fun deletePendingIntent(): PendingIntent {
        val intent = Intent(this, NotificationDismissReceiver::class.java)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(this, 0, intent, flags)
    }

    private fun buildNotification(downloadBps: Long, uploadBps: Long): Notification {
        val hasCountdown = timerActive && timerRemainingSeconds >= 0

        val timerLine = when {
            !timerActive -> "Timer: Inactive"
            hasCountdown -> {
                val stateLabel = if (timerPaused) "Paused" else "Running"
                "Timer ($stateLabel): ${formatBytes(timerBytes)} used \u00b7 ${formatDuration(timerRemainingSeconds)} left"
            }
            else -> {
                val stateLabel = if (timerPaused) "Paused" else "Running"
                "Timer ($stateLabel): ${formatBytes(timerBytes)} in ${formatDuration(timerElapsedSeconds)}"
            }
        }

        val bigText = buildString {
            append("↓ ${formatSpeed(downloadBps)}  ↑ ${formatSpeed(uploadBps)}\n")
            append("Today - Mobile: ${formatBytes(cachedMobileBytes)}  Wi-Fi: ${formatBytes(cachedWifiBytes)}\n")
            append(timerLine)
        }

        // The collapsed (non-expanded) notification only shows title + one
        // line of text, so when the timer is running we prioritize it there
        // instead of "Today" - the countdown is the thing a user glances at
        // the status bar/notification shade for while a session is active.
        val collapsedText = if (timerActive) {
            val timerGlance = if (hasCountdown) {
                "\u23f1 ${formatDuration(timerRemainingSeconds)} left"
            } else {
                "\u23f1 ${formatDuration(timerElapsedSeconds)} elapsed"
            }
            "\u2191 ${formatSpeed(uploadBps)}  \u00b7  $timerGlance"
        } else {
            "\u2191 ${formatSpeed(uploadBps)}  \u00b7  Today: ${formatBytes(cachedMobileBytes + cachedWifiBytes)}"
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("BitWatch \u00b7 ${formatSpeed(downloadBps)} \u2193")
            .setContentText(collapsedText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(bigText))
            .setSmallIcon(SpeedIconFactory.buildIcon(downloadBps))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(contentPendingIntent())
            .setDeleteIntent(deletePendingIntent())

        return builder.build()
    }

    private fun formatSpeed(bps: Long): String {
        val kb = 1024.0
        val mb = kb * 1024.0
        return when {
            bps >= mb -> "%.1f MB/s".format(bps / mb)
            bps >= kb -> "%.0f KB/s".format(bps / kb)
            else -> "$bps B/s"
        }
    }

    private fun formatBytes(bytes: Long): String {
        val kb = 1024.0
        val mb = kb * 1024.0
        val gb = mb * 1024.0
        return when {
            bytes >= gb -> "%.2f GB".format(bytes / gb)
            bytes >= mb -> "%.1f MB".format(bytes / mb)
            bytes >= kb -> "%.0f KB".format(bytes / kb)
            else -> "$bytes B"
        }
    }

    private fun formatDuration(totalSeconds: Int): String {
        val h = totalSeconds / 3600
        val m = (totalSeconds % 3600) / 60
        val s = totalSeconds % 60
        return if (h > 0) "%02d:%02d:%02d".format(h, m, s) else "%dm %ds".format(m, s)
    }
}
