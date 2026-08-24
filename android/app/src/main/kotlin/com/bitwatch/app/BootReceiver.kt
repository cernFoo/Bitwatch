package com.bitwatch.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts the monitoring foreground service after the device reboots. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            BitWatchForegroundService.start(context)
        }
    }
}
