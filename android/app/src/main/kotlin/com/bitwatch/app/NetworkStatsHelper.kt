package com.bitwatch.app

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.TrafficStats
import android.os.Build
import android.os.Process
import android.telephony.TelephonyManager
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * Bytes-used breakdown for a single [start, end) millisecond window.
 */
data class UsageResult(val mobileBytes: Long, val wifiBytes: Long)

/**
 * Wraps [NetworkStatsManager] (API 23+) for historical/day-bucket totals and
 * [TrafficStats] for cheap, instantaneous cumulative-since-boot counters used
 * to derive live speed and "since timer start" deltas.
 *
 * NetworkStatsManager caveats this class works around:
 *  - Querying MOBILE totals technically wants a subscriberId. On most modern
 *    devices/API levels, an app holding the PACKAGE_USAGE_STATS special
 *    permission can pass an empty string and still get correct aggregate
 *    totals via [NetworkStatsManager.querySummaryForDevice]; a small number
 *    of OEM builds are stricter. We try the real subscriber ID first (needs
 *    READ_PHONE_STATE, and returns null on API 29+ for non-carrier-privileged
 *    apps), then fall back to an empty string, then to zero on failure so the
 *    UI degrades gracefully instead of crashing.
 *  - Reading usage stats at all requires the user to have granted the
 *    "Usage access" special app permission (see hasUsageAccessPermission()).
 */
object NetworkStatsHelper {

    private val dayFormat =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = TimeZone.getDefault() }

    /** Start/end epoch millis (device-local time) for the given yyyy-MM-dd date string. */
    fun dayRangeMillis(dateStr: String): Pair<Long, Long> {
        val cal = Calendar.getInstance()
        cal.time = dayFormat.parse(dateStr) ?: cal.time
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        val start = cal.timeInMillis
        cal.add(Calendar.DAY_OF_MONTH, 1)
        val end = cal.timeInMillis
        return start to end
    }

    fun hasUsageAccessPermission(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun subscriberId(context: Context): String {
        return try {
            val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            @Suppress("DEPRECATION")
            tm.subscriberId ?: ""
        } catch (_: SecurityException) {
            ""
        } catch (_: Exception) {
            ""
        }
    }

    /** Sums bucket byte counts (rx+tx) for [networkType] between start/end. */
    private fun queryTotal(
        context: Context,
        manager: NetworkStatsManager,
        networkType: Int,
        start: Long,
        end: Long
    ): Long {
        var total = 0L
        try {
            val subId = if (networkType == ConnectivityManager.TYPE_MOBILE) {
                subscriberId(context)
            } else {
                ""
            }
            val bucket = NetworkStats.Bucket()
            val stats: NetworkStats = manager.querySummary(networkType, subId, start, end)
            stats.use {
                while (it.hasNextBucket()) {
                    it.getNextBucket(bucket)
                    total += bucket.rxBytes + bucket.txBytes
                }
            }
        } catch (_: SecurityException) {
            // Usage access not granted, or subscriberId mismatch on strict OEMs.
            return 0L
        } catch (_: Exception) {
            return 0L
        }
        return total
    }

    /** Returns mobile + Wi-Fi totals for the given yyyy-MM-dd day string. */
    fun getUsageForDate(context: Context, dateStr: String): UsageResult {
        val manager =
            context.getSystemService(Context.NETWORK_STATS_SERVICE) as NetworkStatsManager
        val (start, end) = dayRangeMillis(dateStr)
        val mobile = queryTotal(context, manager, ConnectivityManager.TYPE_MOBILE, start, end)
        val wifi = queryTotal(context, manager, ConnectivityManager.TYPE_WIFI, start, end)
        return UsageResult(mobile, wifi)
    }

    fun todayDateString(): String = dayFormat.format(Calendar.getInstance().time)

    fun getTodayUsage(context: Context): UsageResult = getUsageForDate(context, todayDateString())

    /**
     * Cheap, instantaneous cumulative rx+tx byte counter since device boot,
     * used for speed sampling (delta between two calls one second apart) and
     * for the "data used since timer start" baseline subtraction. Falls back
     * to per-app [TrafficStats] figures (also since boot) if the device-wide
     * getTotalRxBytes/TxBytes API isn't supported (rare, very old devices).
     */
    fun currentTotalBytes(): Long {
        val rx = TrafficStats.getTotalRxBytes()
        val tx = TrafficStats.getTotalTxBytes()
        if (rx == TrafficStats.UNSUPPORTED.toLong() || tx == TrafficStats.UNSUPPORTED.toLong()) {
            val uid = Process.myUid()
            val urx = TrafficStats.getUidRxBytes(uid).coerceAtLeast(0)
            val utx = TrafficStats.getUidTxBytes(uid).coerceAtLeast(0)
            return urx + utx
        }
        return rx + tx
    }
}
