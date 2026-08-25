package com.bitwatch.app

import android.content.Context
import android.content.Intent
import android.net.TrafficStats
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

    private val methodChannelName = "com.bitwatch.app/methods"
    private val eventChannelName = "com.bitwatch.app/speedStream"

    private var sessionBaselineBytes = 0L

    private var eventSink: EventChannel.EventSink? = null
    private var tickJob: Job? = null
    private val activityScope = CoroutineScope(Dispatchers.Main)

    // Independent from the foreground service's own delta tracking - this
    // one drives the live in-app UI while the activity is visible.
    private var lastRx = 0L
    private var lastTx = 0L
    private var lastTickAtMs = 0L
    private var tickCount = 0
    private var cachedMobile = 0L
    private var cachedWifi = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTodayUsage" -> activityScope.launch {
                        val usage = withContext(Dispatchers.IO) {
                            NetworkStatsHelper.getTodayUsage(applicationContext)
                        }
                        result.success(
                            mapOf("mobile" to usage.mobileBytes, "wifi" to usage.wifiBytes)
                        )
                    }

                    "getUsageForDate" -> {
                        val date = call.argument<String>("date")
                        if (date == null) {
                            result.error("BAD_ARGS", "Missing 'date'", null)
                            return@setMethodCallHandler
                        }
                        activityScope.launch {
                            val usage = withContext(Dispatchers.IO) {
                                NetworkStatsHelper.getUsageForDate(applicationContext, date)
                            }
                            result.success(
                                mapOf("mobile" to usage.mobileBytes, "wifi" to usage.wifiBytes)
                            )
                        }
                    }

                    "hasUsageAccessPermission" -> {
                        result.success(NetworkStatsHelper.hasUsageAccessPermission(applicationContext))
                    }

                    "openUsageAccessSettings" -> {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                        try {
                            intent.data = Uri.parse("package:$packageName")
                        } catch (_: Exception) {
                            // Some OEMs don't accept a package Uri here; fall back to
                            // the bare settings screen.
                        }
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(null)
                    }

                    "startForegroundService" -> {
                        BitWatchForegroundService.start(applicationContext)
                        result.success(null)
                    }

                    "stopForegroundService" -> {
                        BitWatchForegroundService.stop(applicationContext)
                        result.success(null)
                    }

                    "updateTimerState" -> {
                        val active = call.argument<Boolean>("active") ?: false
                        val paused = call.argument<Boolean>("paused") ?: false
                        val elapsed = call.argument<Int>("elapsedSeconds") ?: 0
                        val bytes = (call.argument<Number>("timerBytes"))?.toLong() ?: 0L
                        val remaining = call.argument<Int>("remainingSeconds") ?: -1
                        BitWatchForegroundService.updateTimer(
                            applicationContext, active, paused, elapsed, bytes, remaining
                        )
                        result.success(null)
                    }

                    "resetSessionBaseline" -> {
                        sessionBaselineBytes = NetworkStatsHelper.currentTotalBytes()
                        result.success(sessionBaselineBytes)
                    }

                    "getCurrentTotalBytes" -> {
                        result.success(NetworkStatsHelper.currentTotalBytes())
                    }

                    "hasBatteryOptimizationExemption" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }

                    "requestBatteryOptimizationExemption" -> {
                        requestBatteryOptimizationExemption()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                    startTicking()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    tickJob?.cancel()
                }
            })
    }

    private fun startTicking() {
        tickJob?.cancel()
        lastRx = TrafficStats.getTotalRxBytes().coerceAtLeast(0)
        lastTx = TrafficStats.getTotalTxBytes().coerceAtLeast(0)
        lastTickAtMs = System.currentTimeMillis()
        tickCount = 0

        tickJob = activityScope.launch {
            while (true) {
                kotlinx.coroutines.delay(1000)
                tick()
            }
        }
    }

    private suspend fun tick() {
        val now = System.currentTimeMillis()
        val elapsedMs = (now - lastTickAtMs).coerceAtLeast(1)
        val rx = TrafficStats.getTotalRxBytes().coerceAtLeast(0)
        val tx = TrafficStats.getTotalTxBytes().coerceAtLeast(0)

        val downloadBps = ((rx - lastRx).coerceAtLeast(0)) * 1000L / elapsedMs
        val uploadBps = ((tx - lastTx).coerceAtLeast(0)) * 1000L / elapsedMs

        lastRx = rx
        lastTx = tx
        lastTickAtMs = now
        tickCount++

        if (tickCount % 5 == 0 || tickCount == 1) {
            val usage = withContext(Dispatchers.IO) {
                NetworkStatsHelper.getTodayUsage(applicationContext)
            }
            cachedMobile = usage.mobileBytes
            cachedWifi = usage.wifiBytes
        }

        eventSink?.success(
            mapOf(
                "downloadBps" to downloadBps,
                "uploadBps" to uploadBps,
                "todayMobile" to cachedMobile,
                "todayWifi" to cachedWifi,
                "timerActive" to BitWatchForegroundService.timerActive,
                "timerPaused" to BitWatchForegroundService.timerPaused,
                "timerElapsedSeconds" to BitWatchForegroundService.timerElapsedSeconds,
                "timerBytes" to BitWatchForegroundService.timerBytes
            )
        )
    }

    override fun onDestroy() {
        tickJob?.cancel()
        super.onDestroy()
    }

    /**
     * Whether BitWatch is currently exempt from Doze/App Standby battery
     * optimizations. Like Usage Access, this is a "special access" setting
     * Android does not allow requesting via a plain runtime permission
     * dialog - the system intent below shows its own native confirmation
     * dialog instead.
     */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * Launches the system's "Allow [app] to ignore battery optimizations?"
     * dialog directly (ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS), rather
     * than deep-linking to the general battery settings screen, so the user
     * can grant it in a single tap. Falls back to the general Settings
     * screen if the direct-request intent isn't handled on this OEM build.
     */
    private fun requestBatteryOptimizationExemption() {
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        } catch (_: Exception) {
            val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(fallback)
        }
    }
}
