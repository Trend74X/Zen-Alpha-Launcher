package com.example.zen_launcher

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.zen_launcher/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode = 
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
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

                // ==========================================
                // NEW: FETCH INSTALLED APPS WITH ICONS
                // ==========================================
                "getInstalledApps" -> {
                    val pm = packageManager
                    val appsList = ArrayList<Map<String, Any>>()
                    
                    // 1. Target standard user-launchable desktop app shortcuts
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
                        addedPackages.add(pName) // Mark as captured
                    }

                    // 2. BACKUP LOOP: Grab any hidden or system apps that might be missing standard shortcuts
                    val allInstalledPackages = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                    for (appInfo in allInstalledPackages) {
                        // Skip if already found, or if it's a critical background system service with no UI component
                        if (addedPackages.contains(appInfo.packageName)) continue
                        
                        // Only add if it's an accessible system application profile or third-party container
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

                    // Sort everything alphabetically
                    appsList.sortBy { (it["name"] as String).lowercase() }
                    result.success(appsList)
                }

                // ==========================================
                // NEW: EXPLICIT LAUNCH APP METHOD
                // ==========================================
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
                
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // Helper to convert Android vector/bitmap drawables into png bytes
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