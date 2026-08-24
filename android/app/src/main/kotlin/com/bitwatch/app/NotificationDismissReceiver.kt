package com.bitwatch.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Fires when the notification's deleteIntent is triggered (i.e. the user
 * managed to dismiss it despite setOngoing(true)/FLAG_ONGOING_EVENT on OEM
 * skins that permit it). Immediately restarts the foreground service, which
 * re-posts the persistent notification, satisfying the "if dismissed or
 * cleared, must immediately recreate/re-anchor it" requirement.
 */
class NotificationDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        BitWatchForegroundService.start(context)
    }
}
