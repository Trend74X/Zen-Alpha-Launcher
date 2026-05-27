import 'dart:async';
import 'dart:developer';
import 'dart:isolate';
import 'dart:ui';

import 'package:battery_optimization_helper/battery_optimization_helper.dart';
import 'package:do_not_disturb/do_not_disturb.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_notification_listener_plus/flutter_notification_listener_plus.dart';
import 'package:get/get.dart';

class AppController extends GetxController with WidgetsBindingObserver {
  final dndPlugin = DoNotDisturbPlugin();
  static const platform = MethodChannel('com.zen_launcher/battery');

  var isDndEnabled = false.obs;
  var isListenerRunning = false.obs;
  
  // Master thread safe list of notifications intercepted by the platform
  var collectedNotifications = <NotificationEvent>[].obs;
  var appLabelCache = <String, String>{}.obs;

  // Track the raw port mapping to safely handle teardowns
  ReceivePort? _uiReceivePort;

  @override
  Future<void> onInit() async {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    await startZenModeWorkflow();
  } 

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiReceivePort?.close();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      log("User returned to launcher. Re-checking remaining workflows...");
      startZenModeWorkflow();
    }
  }

  // =================================================================
  // STEP 1 WORKHORSE: THE COMPUTED GROUPING MAP
  // =================================================================
  /// GetX Reactive Getter that transforms our flat array into a map organized by package names.
  /// Iterating in reverse ensures the newest notifications bubble to the top of each group.
  Map<String, List<NotificationEvent>> get groupedNotifications {
    final Map<String, List<NotificationEvent>> groups = {};
    
    for (var item in collectedNotifications.reversed) {
      final package = item.packageName ?? 'UNKNOWN';
      if (!groups.containsKey(package)) {
        groups[package] = [];
      }
      groups[package]!.add(item);
    }
    
    return groups;
  }

  // =================================================================
  // PERMISSION & CORE LAUNCHER LIFECYCLE FLOWS
  // =================================================================
  Future<void> startZenModeWorkflow() async {
    bool hasListenerPermission = (await NotificationsListener.hasPermission) ?? false;
    if (!hasListenerPermission) {
      log('Notification Listener Permission missing. Prompting user...');
      await NotificationsListener.openPermissionSettings();
      return; 
    }

    bool hasDndPermission = await dndPlugin.isNotificationPolicyAccessGranted();
    if (!hasDndPermission) {
      log('DND Access Permission missing. Prompting user...');
      await dndPlugin.openNotificationPolicyAccessSettings();
      return; 
    }

    await checkAndRequestBatteryExemption();
    await enableDNDMode();
    await initializeNotificationCollector();
  }

  Future<void> checkAndRequestBatteryExemption() async {
    try {
      final bool isIgnoring = await platform.invokeMethod('isIgnoringBattery');
      if (!isIgnoring) {
        log("Launcher is being optimized by battery saver. Prompting user...");
        await BatteryOptimizationHelper.openBatteryOptimizationSettings();
      } else {
        log("Launcher is already white-listed from battery saving.");
      }
    } on PlatformException catch (e) {
      log("Failed to check battery status: ${e.message}");
      await BatteryOptimizationHelper.openBatteryOptimizationSettings();
    }
  }

  Future<void> enableDNDMode() async {
    bool active = await dndPlugin.isDndEnabled();
    if (!active) {
      log('Enabling Zen Priority Silence Mode...');
      await dndPlugin.setInterruptionFilter(InterruptionFilter.priority);
      isDndEnabled.value = true;
    } else {
      log('DND Mode is already active.');
      isDndEnabled.value = true;
    }
  }

  // =================================================================
  // NOTIFICATION BACKGROUND BACKGROUND ROUTING MANAGEMENT
  // =================================================================
  Future<void> initializeNotificationCollector() async {
    await NotificationsListener.initialize(callbackHandle: backgroundNotificationHandler);
    
    IsolateNameServer.removePortNameMapping("_listener_");

    _uiReceivePort = ReceivePort();
    IsolateNameServer.registerPortWithName(_uiReceivePort!.sendPort, "_listener_");

    _uiReceivePort!.listen((rawData) {
      if (rawData is NotificationEvent) {
        _handleIncomingUiNotification(rawData);
      }
    });

    bool isServiceRunning = await NotificationsListener.isRunning ?? false;
    if (!isServiceRunning) {
      log("System notification tracking engine inactive. Starting service context...");
      await NotificationsListener.startService(
        foreground: true,
        title: "Zen Focus Active",
        description: "Filtering background distractions...",
      );
    }

    isListenerRunning.value = true;
    log("Notification communication bridge successfully bound.");
  }

  void _handleIncomingUiNotification(NotificationEvent event) {
    log('Notification intercepted from: ${event.packageName}');
    if (event.title == null && event.text == null) return;

    // Filter potential duplicate notifications arriving in rapid succession
    bool alreadyExists = collectedNotifications.any((n) => 
      n.packageName == event.packageName && 
      n.title == event.title && 
      n.text == event.text
    );

    if (!alreadyExists) {
      collectedNotifications.add(event); 
      // Telling collectedNotifications to trigger will cascade updates straight to our grouped getter
      collectedNotifications.refresh(); 
    }
  }

  // =================================================================
  // DEEP LINK NAVIGATION DISPATCHER
  // =================================================================
  Future<void> openNotificationTargetApp(NotificationEvent event) async {
    try {
      log("Processing deep-intent routing logic for package: ${event.packageName}");
      
      // Try to open the original notification detail intent packet directly
      if (event.canTap == true) {
        bool success = await event.tap();
        if (success) {
          log("SUCCESS: Routed directly to target deep link nested window.");
          return; 
        }
      }
      
      // Fallback: If the intent token expired, use the MethodChannel entrance fallback
      log("Deep-link token expired or unavailable. Executing fallback launcher application entrance...");
      if (event.packageName != null) {
        await platform.invokeMethod('launchApp', event.packageName);
      }
    } catch (e) {
      log("Error executing notification intent routing: $e");
    }
  }

  // Clear out the whole Vault structure at once
  void clearAllNotifications() {
    collectedNotifications.clear();
    collectedNotifications.refresh();
    log("Zen Vault cleared out completely.");
  }

  /// Fetches the real app name from Android OS or returns the cached string
  String getAppNameOf(String packageName) {
    if (packageName == 'UNKNOWN') return 'SYSTEM';
    
    // If we already looked it up, return it instantly from memory
    if (appLabelCache.containsKey(packageName)) {
      return appLabelCache[packageName]!;
    }

    // Otherwise, kick off an asynchronous background request to fetch it
    _fetchNativeAppLabel(packageName);

    // While waiting for the native bridge to reply, provide a clean temporary fallback
    return packageName.split('.').reversed.firstWhere(
      (segment) => segment != 'android' && segment != 'app',
      orElse: () => 'APP'
    ).toUpperCase();
  }

  Future<void> _fetchNativeAppLabel(String packageName) async {
    try {
      final String? realLabel = await platform.invokeMethod('getAppLabel', packageName);
      if (realLabel != null && realLabel.isNotEmpty) {
        appLabelCache[packageName] = realLabel.toUpperCase();
        appLabelCache.refresh(); // Forces GetX UI elements to update with the pretty name
      }
    } catch (e) {
      print("Failed to look up native app label for $packageName: $e");
    }
  }
  
}

// =================================================================
// ISOLATE ENTRY POINT HANDLER
// =================================================================
@pragma('vm:entry-point')
void backgroundNotificationHandler(NotificationEvent event) {
  log("Background Isolate caught notification: ${event.title}");
  final SendPort? sendPort = IsolateNameServer.lookupPortByName("_listener_");
  
  if (sendPort != null) {
    sendPort.send(event);
  } else {
    log("Communication channel '_listener_' wasn't found yet.");
  }
}