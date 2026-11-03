package com.trend74x.zenalpha

import android.app.NotificationManager
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.app.role.RoleManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.ComponentName
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
import android.os.Process
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Calendar

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL_BATTERY = "com.zen_launcher/battery"
    private var screenReceiver: BroadcastReceiver? = null

    private val devicePolicyManager: DevicePolicyManager
        get() = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    private val deviceAdminComponent: ComponentName
        get() = ComponentName(this, ZenDeviceAdminReceiver::class.java)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }

        val batteryChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_BATTERY)

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

                // --- DEFAULT HOME / LAUNCHER ROLE ---
                "isDefaultLauncher" -> {
                    result.success(isDefaultLauncher())
                }

                "requestDefaultLauncher" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val roleManager = getSystemService(RoleManager::class.java)
                            if (roleManager != null &&
                                roleManager.isRoleAvailable(RoleManager.ROLE_HOME) &&
                                !roleManager.isRoleHeld(RoleManager.ROLE_HOME)
                            ) {
                                startActivity(roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME))
                                result.success(true)
                            } else {
                                // Already held or unavailable on this device: show the
                                // system home-app list as a fallback.
                                startActivity(
                                    Intent(Settings.ACTION_HOME_SETTINGS)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.success(true)
                            }
                        } else {
                            startActivity(
                                Intent(Settings.ACTION_HOME_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        // Some OEM builds reject the role intent. Fall back to the
                        // system home-app picker so the user can still choose Zen.
                        try {
                            startActivity(
                                Intent(Settings.ACTION_HOME_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (fallbackError: Exception) {
                            result.error(
                                "INTENT_FAILED",
                                "Could not open default-launcher settings: ${e.message}",
                                null
                            )
                        }
                    }
                }

                // --- APP TIMERS / USAGE ACCESS ---
                "hasUsageAccess" -> {
                    val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
                    @Suppress("DEPRECATION")
                    val mode = appOps.checkOpNoThrow(
                        AppOpsManager.OPSTR_GET_USAGE_STATS,
                        Process.myUid(),
                        packageName
                    )
                    result.success(mode == AppOpsManager.MODE_ALLOWED)
                }

                "openUsageAccessSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        this.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INTENT_FAILED", "Could not open usage access settings: ${e.message}", null)
                    }
                }

                "getTodayUsage" -> {
                    try {
                        result.success(getTodayUsageMillis())
                    } catch (e: Exception) {
                        result.error("USAGE_FAILED", "Could not read usage stats: ${e.message}", null)
                    }
                }

                "getForegroundApp" -> {
                    try {
                        result.success(getForegroundPackage())
                    } catch (e: Exception) {
                        result.error("USAGE_FAILED", "Could not read foreground app: ${e.message}", null)
                    }
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

                    // A launcher only needs apps that expose a launcher activity.
                    // The <queries> block in AndroidManifest.xml makes these visible
                    // without QUERY_ALL_PACKAGES.
                    val mainIntent = Intent(Intent.ACTION_MAIN, null).apply {
                        addCategory(Intent.CATEGORY_LAUNCHER)
                    }
                    val launchableApps = pm.queryIntentActivities(mainIntent, 0)
                    val addedPackages = HashSet<String>()

                    for (resolveInfo in launchableApps) {
                        val pName = resolveInfo.activityInfo.packageName
                        if (!addedPackages.add(pName)) continue

                        val label = resolveInfo.loadLabel(pm).toString()
                        val iconDrawable = resolveInfo.loadIcon(pm)
                        val iconBytes = drawableToByteArray(iconDrawable)

                        val appInfo = HashMap<String, Any>()
                        appInfo["name"] = label
                        appInfo["packageName"] = pName
                        if (iconBytes != null) appInfo["icon"] = iconBytes

                        appsList.add(appInfo)
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

                // --- DEVICE ADMIN SCREEN LOCK ---
                "lockScreen" -> {
                    if (devicePolicyManager.isAdminActive(deviceAdminComponent)) {
                        try {
                            devicePolicyManager.lockNow()
                            result.success(true)
                        } catch (e: SecurityException) {
                            result.error("REJECTED", "Device admin refused the lock request.", null)
                        }
                    } else {
                        result.error("DISABLED", "Device admin is not enabled.", null)
                    }
                }

                "checkDeviceAdminPermission" -> {
                    result.success(devicePolicyManager.isAdminActive(deviceAdminComponent))
                }

                "requestDeviceAdmin" -> {
                    try {
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, deviceAdminComponent)
                            putExtra(
                                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                "Zen Launcher uses device admin only to turn off the screen when you double-tap the home background."
                            )
                        }
                        this.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INTENT_FAILED", "Could not open device admin settings: ${e.message}", null)
                    }
                }

                "removeDeviceAdmin" -> {
                    try {
                        if (devicePolicyManager.isAdminActive(deviceAdminComponent)) {
                            devicePolicyManager.removeActiveAdmin(deviceAdminComponent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("REMOVE_FAILED", "Could not remove device admin: ${e.message}", null)
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

    private fun getUsageStatsManager(): UsageStatsManager =
        getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

    /** True when Zen is the system's chosen HOME app. */
    private fun isDefaultLauncher(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(RoleManager::class.java)
            roleManager?.isRoleHeld(RoleManager.ROLE_HOME) == true
        } else {
            @Suppress("DEPRECATION")
            val resolved = packageManager.resolveActivity(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),
                PackageManager.MATCH_DEFAULT_ONLY
            )
            resolved?.activityInfo?.packageName == packageName
        }
    }

    private fun startOfToday(): Long {
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        return calendar.timeInMillis
    }

    @Suppress("DEPRECATION")
    private fun getTodayUsageMillis(): Map<String, Long> {
        val now = System.currentTimeMillis()
        val events = getUsageStatsManager().queryEvents(startOfToday(), now)
        val event = UsageEvents.Event()
        val startedAt = HashMap<String, Long>()
        val totals = HashMap<String, Long>()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> startedAt[pkg] = event.timeStamp
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    val start = startedAt.remove(pkg)
                    if (start != null) {
                        totals[pkg] = (totals[pkg] ?: 0L) + (event.timeStamp - start)
                    }
                }
            }
        }

        // Count the app that is currently in the foreground.
        for ((pkg, start) in startedAt) {
            totals[pkg] = (totals[pkg] ?: 0L) + (now - start)
        }

        return totals
    }

    @Suppress("DEPRECATION")
    private fun getForegroundPackage(): String? {
        val now = System.currentTimeMillis()
        val events = getUsageStatsManager().queryEvents(now - 15_000, now)
        val event = UsageEvents.Event()
        var lastForeground: String? = null

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                lastForeground = event.packageName
            }
        }

        return lastForeground
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
}
