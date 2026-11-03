package com.trend74x.zenalpha

import android.app.admin.DeviceAdminReceiver

/**
 * Minimal device administrator used only for the "Double-Tap to Lock" feature.
 *
 * This replaces the previous AccessibilityService-based implementation. Device Admin
 * is the Play-policy-friendly way to lock the screen because it does not require a
 * non-accessibility app to enable the Accessibility API.
 */
class ZenDeviceAdminReceiver : DeviceAdminReceiver()
