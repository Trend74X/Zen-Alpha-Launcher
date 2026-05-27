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

  // Reactive list containing all launcher-ready apps on the phone
  var installedApps = <AppModel>[].obs;
  var isLoadingApps = false.obs;
  var searchQuery = ''.obs;
  var showIcons = true.obs; // Defaults to true so toggle has a baseline state

  @override
  Future<void> onInit() async {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    await startZenModeWorkflow();
    await fetchInstalledApps();
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
  // STEP 1 WORKHORSE: THE COMPUTED CHANNEL-GROUPING MAP
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

    // Helper to get a stable signature of the message string.
    // Slicing the first 15 characters lets us match "NICA traded at..." with "NICA traded at..."
    // even if the price or units at the end of the text string differ.
    String textSignature(String? fullText) {
      if (fullText == null || fullText.isEmpty) return '';
      return fullText.length > 15 ? fullText.substring(0, 15) : fullText;
    }

    final String incomingSig = textSignature(event.text);

    // Check if there is an existing alert in the vault with the same App, same Title, 
    // and a matching text signature (e.g., matching stock ticker alerts)
    int duplicateIndex = collectedNotifications.indexWhere((existing) =>
      existing.packageName == event.packageName &&
      existing.title == event.title &&
      textSignature(existing.text) == incomingSig
    );

    if (duplicateIndex != -1) {
      log('Duplicate ticker pattern detected. Replacing older entry with the latest update.');
      // Remove the old notification so it doesn't clutter the history
      collectedNotifications.removeAt(duplicateIndex);
    }

    // Append the fresh notification. Because our groupedNotifications getter 
    // loops using .reversed, this latest one will seamlessly slide to the top!
    collectedNotifications.add(event); 
    collectedNotifications.refresh(); 
  }

  // =================================================================
  // DEEP LINK NAVIGATION DISPATCHER
  // =================================================================
  Future<void> openNotificationTargetApp(NotificationEvent event) async {
    try {
      log("Processing deep-intent routing logic for package: ${event.packageName}");
      
      // FIX: Wipe it from the array immediately so it vanishes from the Vault UI on click
      collectedNotifications.remove(event);
      collectedNotifications.refresh();

      // Try to open the original notification detail intent packet directly
      if (event.canTap == true) {
        bool success = await event.tap();
        if (success) {
          log("SUCCESS: Routed directly to target deep link nested window.");
          return; 
        }
      }
      
      // Fallback entrance launcher entry line
      log("Deep-link token expired or unavailable. Executing fallback launcher application entrance...");
      if (event.packageName != null) {
        await platform.invokeMethod('launchApp', event.packageName);
      }
    } catch (e) {
      log("Error executing notification intent routing: $e");
    }
  }

  void clearAllNotifications() {
    collectedNotifications.clear();
    collectedNotifications.refresh();
    log("Zen Vault cleared out completely.");
  }

  // =================================================================
  // NATIVE APP MANAGER UTILITIES
  // =================================================================
  String getAppNameOf(String packageName) {
    if (packageName == 'UNKNOWN') return 'SYSTEM';
    
    if (appLabelCache.containsKey(packageName)) {
      return appLabelCache[packageName]!;
    }

    _fetchNativeAppLabel(packageName);

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
        appLabelCache.refresh(); 
      }
    } catch (e) {
      log("Failed to look up native app label for $packageName: $e");
    }
  }

  Future<void> fetchInstalledApps() async {
    try {
      isLoadingApps.value = true;
      final List<dynamic>? rawApps = await platform.invokeMethod('getInstalledApps');
      
      if (rawApps != null) {
        installedApps.value = rawApps.map((item) {
          final Map<dynamic, dynamic> appMap = item as Map<dynamic, dynamic>;
          return AppModel(
            name: appMap['name'] ?? 'Unknown',
            packageName: appMap['packageName'] ?? '',
            iconBytes: appMap['icon'] as Uint8List?,
          );
        }).toList();
      }
    } catch (e) {
      log("Error querying installed applications: $e");
    } finally {
      isLoadingApps.value = false;
    }
  }

  Future<void> launchApplicationContainer(String packageName) async {
    try {
      await platform.invokeMethod('launchApp', packageName);
    } catch (e) {
      log("Could not open app $packageName: $e");
    }
  }

    // --- DRAWER REALTIME FILTERS ---
  List<AppModel> get filteredApps {
    if (searchQuery.value.isEmpty) {
      return installedApps;
    }
    return installedApps.where((app) => 
      app.name.toLowerCase().contains(searchQuery.value.toLowerCase())
    ).toList();
  }
  
}

class AppModel {
  final String name;
  final String packageName;
  final Uint8List? iconBytes;

  AppModel({required this.name, required this.packageName, this.iconBytes});
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