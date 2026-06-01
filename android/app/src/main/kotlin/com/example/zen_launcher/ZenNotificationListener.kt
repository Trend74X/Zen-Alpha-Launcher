package com.example.zen_launcher

import android.app.Notification
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class ZenNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return

        val packageName = sbn.packageName
        val channelId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) sbn.notification.channelId else null
        
        // Run interception extraction parameters through the filtration engine
        if (!MainActivity.shouldShowNotification(packageName, channelId)) {
            return // Drop input method selectors silently here
        }

        // Pull notification descriptive payloads safely
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        // Forward to the bridge if data is meaningful
        if (title.isNotEmpty() || text.isNotEmpty()) {
            MainActivity.sendNotificationToFlutter(packageName, title, text)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        // Optional: Implement this callback if your Flutter layout needs to clear notification badges dynamically
    }
}