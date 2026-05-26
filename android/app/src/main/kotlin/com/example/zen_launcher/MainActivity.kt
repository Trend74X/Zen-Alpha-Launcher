package com.example.zen_launcher

import android.content.Context
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
            if (call.method == "isIgnoringBattery") {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                val isIgnoring = powerManager.isIgnoringBatteryOptimizations(packageName)
                result.success(isIgnoring)
            } else {
                result.notImplemented()
            }
        }
    }
}