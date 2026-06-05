package com.example.zen_launcher

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.ComponentName  // <-- ADDED MISSING IMPORT
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils          // <-- ADDED MISSING IMPORT
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL_BATTERY = "com.zen_launcher/battery"
    private val CHANNEL_NOTIFICATIONS = "com.zen_launcher/notifications"
    private var screenReceiver: BroadcastReceiver? = null
    
    companion object {
        private var flutterChannel: MethodChannel? = null
        
        private val BLOCKED_NOTIFICATION_PACKAGES = arrayOf(
            "android",
            "com.android.systemui",
            "com.google.android.inputmethod.latin"
        )

        fun shouldShowNotification(packageName: String, channelId: String?): Boolean {
            if (BLOCKED_NOTIFICATION_PACKAGES.contains(packageName)) {
                return false
            }
            if (channelId != null && channelId.contains("input_method", ignoreCase = true)) {
                return false
            }
            return true
        }

        fun sendNotificationToFlutter(packageName: String, title: String, text: String) {
            val data = HashMap<String, String>()
            data["packageName"] = packageName
            data["title"] = title
            data["text"] = text
            flutterChannel?.invokeMethod("onNotificationReceived", data)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode = 
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        
        val batteryChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_BATTERY)
        flutterChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NOTIFICATIONS)

        // Screen State Broadcast Receiver
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }

        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> {
                        batteryChannel.invokeMethod("onScreenStateChanged", true)
                    }
                    Intent.ACTION_SCREEN_OFF -> {
                        batteryChannel.invokeMethod("onScreenStateChanged", false)
                    }
                }
            }
        }
        this.registerReceiver(screenReceiver, filter)

        // Method Channel Handlers
        batteryChannel.setMethodCallHandler { call, result ->
            val notificationManager = this.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            when (call.method) {
                "isDNDEnabled" -> {
                    val isEnabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        notificationManager.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_NONE
                    } else {
                        false
                    }
                    result.success(isEnabled)
                }

                "setDNDMode" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (notificationManager.isNotificationPolicyAccessGranted) {
                            val targetFilter = if (enabled) {
                                NotificationManager.INTERRUPTION_FILTER_NONE
                            } else {
                                NotificationManager.INTERRUPTION_FILTER_ALL
                            }
                            notificationManager.setInterruptionFilter(targetFilter)
                            result.success(true)
                        } else {
                            result.error("MISSING_PERMISSION", "Notification policy access not granted", null)
                        }
                    } else {
                        result.success(false)
                    }
                }

                "openDNDPermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        this.startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }

                "isIgnoringBattery" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    val isIgnoring = powerManager.isIgnoringBatteryOptimizations(packageName)
                    result.success(isIgnoring)
                }
                
                "getAppLabel" -> {
                    val targetPackageName = call.arguments<String>()
                    if (targetPackageName != null) {
                        try {
                            val pm: PackageManager = packageManager
                            val ai: ApplicationInfo = pm.getApplicationInfo(targetPackageName, 0)
                            val appLabel = pm.getApplicationLabel(ai).toString()
                            result.success(appLabel)
                        } catch (e: PackageManager.NameNotFoundException) {
                            result.success(null)
                        }
                    } else {
                        result.error("BAD_ARGUMENTS", "Package name argument was null", null)
                    }
                }

                "getInstalledApps" -> {
                    val pm = packageManager
                    val appsList = ArrayList<Map<String, Any>>()
                    
                    val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                        addCategory(Intent.CATEGORY_LAUNCHER)
                    }
                    val launchableApps = pm.queryIntentActivities(mainIntent, 0)
                    val addedPackages = HashSet<String>()

                    for (resolveInfo in launchableApps) {
                        val pName = resolveInfo.activityInfo.packageName
                        val label = resolveInfo.loadLabel(pm).toString()
                        val iconDrawable = resolveInfo.loadIcon(pm)
                        val iconBytes = drawableToByteArray(iconDrawable)

                        val appInfo = HashMap<String, Any>()
                        appInfo["name"] = label
                        appInfo["packageName"] = pName
                        if (iconBytes != null) appInfo["icon"] = iconBytes
                        
                        appsList.add(appInfo)
                        addedPackages.add(pName)
                    }

                    val allInstalledPackages = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                    for (appInfo in allInstalledPackages) {
                        if (addedPackages.contains(appInfo.packageName)) continue
                        
                        val launchIntent = pm.getLaunchIntentForPackage(appInfo.packageName)
                        if (launchIntent != null) {
                            val label = appInfo.loadLabel(pm).toString()
                            val iconDrawable = appInfo.loadIcon(pm)
                            val iconBytes = drawableToByteArray(iconDrawable)

                            val fallBackApp = HashMap<String, Any>()
                            fallBackApp["name"] = label
                            fallBackApp["packageName"] = appInfo.packageName
                            if (iconBytes != null) fallBackApp["icon"] = iconBytes

                            appsList.add(fallBackApp)
                            addedPackages.add(appInfo.packageName)
                        }
                    }

                    appsList.sortBy { (it["name"] as String).lowercase() }
                    result.success(appsList)
                }

                "launchApp" -> {
                    val pName = call.arguments<String>()
                    if (pName != null) {
                        val launchIntent = packageManager.getLaunchIntentForPackage(pName)
                        if (launchIntent != null) {
                            startActivity(launchIntent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.error("BAD_ARGUMENTS", "Package name was null", null)
                    }
                }

                // --- OPTIMIZED SCREEN LOCK EXECUTION VECTOR ---
                "lockScreen" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        // Request direct command dispatch via tracking instance
                        val resultStatus = ZenAccessibilityService.requestScreenLock()
                        
                        when (resultStatus) {
                            "SUCCESS" -> result.success(true)
                            "SERVICE_NOT_CONNECTED_OR_DISABLED" -> {
                                result.error("DISABLED", "Accessibility service is off in system settings.", null)
                            }
                            "OS_REJECTED_ACTION_CHECK_PERMISSIONS" -> {
                                result.error("REJECTED", "Android window pipeline refused execution.", null)
                            }
                            else -> result.error("ERROR", resultStatus, null)
                        }
                    } else {
                        result.error("UNSUPPORTED_OS", "Requires Android 9 or above.", null)
                    }
                }

                "checkAccessibilityPermission" -> {
                    val isEnabled = isAccessibilityServiceEnabled()
                    result.success(isEnabled)
                }

                "openAccessibilitySettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        this.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INTENT_FAILED", "Could not open accessibility panel: ${e.message}", null)
                    }
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            screenReceiver?.let { this.unregisterReceiver(it) }
        } catch (e: Exception) {
            // Already unregistered gracefully
        }
    }

    private fun drawableToByteArray(drawable: Drawable): ByteArray? {
        val bitmap = if (drawable is BitmapDrawable) {
            drawable.bitmap
        } else {
            val width = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else 100
            val height = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 100
            val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bmp
        }

        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedComponentName = ComponentName(this, ZenAccessibilityService::class.java)
        val settingValue = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(settingValue)
        while (splitter.hasNext()) {
            val accessService = splitter.next()
            val componentName = ComponentName.unflattenFromString(accessService)
            if (componentName != null && componentName == expectedComponentName) {
                return true
            }
        }
        return false
    }
}