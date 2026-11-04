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
import android.net.Uri
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

                // Diagnostic: does this installed build actually declare a
                // HOME activity? If this is false, no system screen can ever
                // offer Zen and the fix is reinstalling a correct APK.
                "isHomeActivityRegistered" -> {
                    result.success(isHomeActivityRegistered())
                }

                "getCurrentHomePackage" -> {
                    result.success(getCurrentHomePackage())
                }

                "requestDefaultLauncher" -> {
                    if (isDefaultLauncher()) {
                        result.success("already")
                        return@setMethodCallHandler
                    }

                    var prompted = false

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        try {
                            val roleManager = getSystemService(RoleManager::class.java)
                            if (roleManager != null &&
                                roleManager.isRoleAvailable(RoleManager.ROLE_HOME)
                            ) {
                                val roleIntent =
                                    roleManager.createRequestRoleIntent(RoleManager.ROLE_HOME)
                                startActivity(roleIntent)
                                prompted = true
                            }
                        } catch (e: Exception) {
                            // Some OEM builds (notably MIUI) reject the role prompt.
                            // Fall through to the settings screen below.
                        }
                    }

                    if (!prompted) {
                        prompted = openHomeSettings()
                    }

                    result.success(if (prompted) "prompted" else "unavailable")
                }

                "openHomeSettings" -> {
                    if (openHomeSettings()) {
                        result.success(true)
                    } else {
                        result.error(
                            "INTENT_FAILED",
                            "Could not open the system Home app settings.",
                            null
                        )
                    }
                }

                // --- SYSTEM NAVIGATION STYLE ---
                "getNavigationMode" -> {
                    result.success(getNavigationMode())
                }

                "getDeviceManufacturer" -> {
                    result.success(Build.MANUFACTURER ?: "")
                }

                "openNavigationSettings" -> {
                    if (openNavigationSettings()) {
                        result.success(true)
                    } else {
                        result.error(
                            "INTENT_FAILED",
                            "Could not open the system navigation settings.",
                            null
                        )
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

                "getTodayScreenTime" -> {
                    try {
                        result.success(getTodayScreenOnMillis())
                    } catch (e: Exception) {
                        result.error("USAGE_FAILED", "Could not read screen time: ${e.message}", null)
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

    /** Resolved package of the current HOME app, or null when none resolves. */
    @Suppress("DEPRECATION")
    private fun getCurrentHomePackage(): String? {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return packageManager
            .resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
            ?.activityInfo
            ?.packageName
    }

    /** True when Zen is the system's chosen HOME app. */
    private fun isDefaultLauncher(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roleManager = getSystemService(RoleManager::class.java)
            if (roleManager?.isRoleHeld(RoleManager.ROLE_HOME) == true) {
                return true
            }
        }

        // RoleManager is unreliable on some OEM builds (MIUI, One UI). Treat a
        // resolved HOME intent that lands on Zen as authoritative too.
        return getCurrentHomePackage() == packageName
    }

    /**
     * True when this installed build declares a HOME activity.
     *
     * The app queries only its own package here. If this returns false, the
     * user cannot select Zen as a Home app no matter which settings screen
     * opens, which usually means an old or partially-installed APK.
     */
    private fun isHomeActivityRegistered(): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            packageManager.queryIntentActivities(intent, 0).any {
                it.activityInfo?.packageName == packageName
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Opens the system screen where the user can pick the HOME app.
     *
     * No single intent works on every OEM skin, so try the public Home-app
     * screen first and then a chain of known fallbacks. Try to start each one
     * rather than only resolving it: several Settings activities resolve to
     * nothing but are still launchable by explicit component.
     */
    @Suppress("DEPRECATION")
    private fun openHomeSettings(): Boolean {
        val candidates = ArrayList<Intent>()

        candidates.add(Intent(Settings.ACTION_HOME_SETTINGS))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            candidates.add(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
        }

        // AOSP Settings variants used by Pixel, OnePlus, Sony, and others.
        candidates.add(
            Intent().setComponent(
                ComponentName(
                    "com.android.settings",
                    "com.android.settings.Settings\$HomeSettingsActivity"
                )
            )
        )
        candidates.add(
            Intent().setComponent(
                ComponentName(
                    "com.android.settings",
                    "com.android.settings.Settings\$DefaultHomeSettingsActivity"
                )
            )
        )
        candidates.add(
            Intent().setComponent(
                ComponentName(
                    "com.android.settings",
                    "com.android.settings.homepage.SettingsHomepageActivity"
                )
            )
        )

        // Last resort: Zen's own App info page, where OEM skins usually expose
        // "Open by default" / "Home app" controls.
        candidates.add(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null)
            )
        )
        candidates.add(Intent(Settings.ACTION_SETTINGS))

        for (base in candidates) {
            try {
                val intent = Intent(base).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (e: Exception) {
                // Try the next candidate.
            }
        }

        return false
    }

    /**
     * System navigation style: 0 = 3-button, 1 = 2-button, 2 = gesture,
     * -1 = unknown / not readable.
     *
     * Android does not let a normal app write this value. Only a system or
     * privileged app (or ADB with WRITE_SECURE_SETTINGS) can change it, so Zen
     * can open the correct settings screen but must let the user choose.
     */
    private fun getNavigationMode(): Int {
        for (key in listOf("navigation_mode", "navigation_bar_mode")) {
            try {
                val value = Settings.Secure.getInt(contentResolver, key, -1)
                if (value in 0..2) return value
            } catch (e: Exception) {
                // Try the next key.
            }
        }

        // Some OEM skins only expose the boolean form.
        return try {
            when (Settings.Secure.getInt(contentResolver, "system_navigation_keys_enabled", -1)) {
                1 -> 0
                0 -> 2
                else -> -1
            }
        } catch (e: Exception) {
            -1
        }
    }

    /**
     * Opens the system screen that lets the user pick gesture vs button
     * navigation. Different OEM skins hide this behind different activities,
     * so try the common ones in order.
     */
    private fun openNavigationSettings(): Boolean {
        val candidates = ArrayList<Intent>()

        // AOSP / Pixel / most MIUI and HyperOS builds.
        candidates.add(Intent("com.android.settings.NAVIGATION_MODE_SETTINGS"))
        candidates.add(Intent("com.android.settings.GESTURE_NAVIGATION_SETTINGS"))
        candidates.add(
            Intent().setComponent(
                ComponentName(
                    "com.android.settings",
                    "com.android.settings.Settings\$NavigationModeSettingsActivity"
                )
            )
        )
        candidates.add(
            Intent().setComponent(
                ComponentName(
                    "com.android.settings",
                    "com.android.settings.Settings\$GestureNavigationSettingsActivity"
                )
            )
        )
        candidates.add(
            Intent().setComponent(
                ComponentName(
                    "com.android.settings",
                    "com.android.settings.Settings\$SystemNavigationSettingsActivity"
                )
            )
        )

        // Samsung puts navigation style under Settings > Display.
        candidates.add(
            Intent().setComponent(
                ComponentName(
                    "com.samsung.android.settings",
                    "com.samsung.android.settings.display.NavigationBarSettingsActivity"
                )
            )
        )
        candidates.add(
            Intent().setComponent(
                ComponentName(
                    "com.samsung.android.settings",
                    "com.samsung.android.settings.display.NavigationBarGestureSettingsActivity"
                )
            )
        )
        candidates.add(Intent(Settings.ACTION_DISPLAY_SETTINGS))
        candidates.add(Intent(Settings.ACTION_SETTINGS))

        for (base in candidates) {
            try {
                val intent = Intent(base).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return true
            } catch (e: Exception) {
                // Try the next candidate.
            }
        }

        return false
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

    /**
     * Real screen-on time since local midnight, derived from UsageEvents.
     *
     * Returns null on Android < 9 where the screen-interactive event constants
     * are unavailable, so Dart can keep its local fallback.
     */
    @Suppress("DEPRECATION")
    private fun getTodayScreenOnMillis(): Long? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null

        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        @Suppress("DEPRECATION")
        val access = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName
        )
        if (access != AppOpsManager.MODE_ALLOWED) return null

        val now = System.currentTimeMillis()
        val todayStart = startOfToday()
        val events = getUsageStatsManager().queryEvents(todayStart, now)
        val event = UsageEvents.Event()

        var lastOn: Long? = null
        var total = 0L
        var sawScreenEvent = false

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.SCREEN_INTERACTIVE -> {
                    lastOn = event.timeStamp
                    sawScreenEvent = true
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    val start = lastOn ?: todayStart
                    if (event.timeStamp > start) {
                        total += event.timeStamp - start
                    }
                    lastOn = null
                    sawScreenEvent = true
                }
            }
        }

        if (lastOn != null) {
            total += (now - lastOn!!).coerceAtLeast(0L)
        } else if (!sawScreenEvent) {
            // No screen events yet today. If the screen is on now, the device
            // was very likely already on at midnight.
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (powerManager.isInteractive) {
                total = now - todayStart
            }
        }

        return total
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
