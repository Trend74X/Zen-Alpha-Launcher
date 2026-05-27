package com.example.zen_launcher

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.zen_launcher/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // FORCE NATIVE ANDROID LAYER TO RENDER UNDER THE NOTCH/CUTOUT AREA
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
                            result.success(appLabel) // Returns clean names like "Facebook", "Daraz"
                        } catch (e: PackageManager.NameNotFoundException) {
                            result.success(null) // Safe fallback if app was just uninstalled
                        }
                    } else {
                        result.error("BAD_ARGUMENTS", "Package name argument was null", null)
                    }
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}