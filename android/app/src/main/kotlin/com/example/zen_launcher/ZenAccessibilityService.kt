package com.example.zen_launcher

import android.accessibilityservice.AccessibilityService
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class ZenAccessibilityService : AccessibilityService() {

    companion object {
        // Keeps a live, thread-safe reference to the active system service instance
        private var instance: ZenAccessibilityService? = null

        /**
         * This is the exact method MainActivity looks for. 
         * It communicates directly with the active system instance.
         */
        fun requestScreenLock(): String {
            val currentService = instance ?: return "SERVICE_NOT_CONNECTED_OR_DISABLED"
            
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                // Execute the native OS screen lock frame command
                val success = currentService.performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
                if (success) "SUCCESS" else "OS_REJECTED_ACTION_CHECK_PERMISSIONS"
            } else {
                "ANDROID_VERSION_TOO_LOW"
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("ZenLauncher", "Accessibility Service successfully attached to Android OS registry.")
        instance = this
    }

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        Log.d("ZenLauncher", "Accessibility Service detached/unbound.")
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}
}