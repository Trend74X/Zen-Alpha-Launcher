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
  
    // Single unified method channel matching your MainActivity.kt definition
  static const platform = MethodChannel('com.zen_launcher/battery');

    // --- GETX OBSERVABLE STATES ---
  var isListenerRunning = false.obs;
  var isDndActive       = false.obs;  // Connected directly to the custom environment panel toggle
  var appTimersActive   = false.obs;  // Connected directly to the custom environment panel toggle
  
    // Master thread-safe list of notifications intercepted by the platform
  var collectedNotifications = <NotificationEvent>[].obs;
  var appLabelCache          = <String, String>{}.obs;

    // --- USER CONTROLLER SCREEN CLOCK OBSERVABLES ---
  var todayScreenTime = "00:00:00".obs;
  Timer? _tickerTimer;
  int  _accumulatedSecondsToday = 0;     // Cumulative active seconds for the day
  bool _isDeviceScreenOn        = true;  // Track state to manage background counting

    // Track the raw port mapping to safely handle teardowns
  ReceivePort? _uiReceivePort;

    // Reactive list containing all launcher-ready apps on the phone
  var installedApps = <AppModel>[].obs;
  var isLoadingApps = false.obs;
  var searchQuery   = ''.obs;
  var showIcons     = true.obs;          // Defaults to true so toggle has a baseline state

  @override
  Future<void> onInit() async {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    
      // Core Launcher Workflows
    await startZenModeWorkflow();
    await fetchInstalledApps();
    
      // Initialize Permissionless Local Screen Tracking
    initLocalScreenTimeTracking();
  } 

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiReceivePort?.close();
    _tickerTimer?.cancel();
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
    // COMPUTED CHANNEL-GROUPING MAP
    // =================================================================
    /// GetX Reactive Getter that transforms our flat array into a map organized by package names.
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

      // Sync current native Do Not Disturb status flags on app startup
    await checkCurrentDndStatus();
    await checkAndRequestBatteryExemption();
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

    // =================================================================
    // ENVIRONMENT STATE PROGRAMMATIC CONTROLLERS
    // =================================================================

    /// Queries the native Android layer via method channel to see if DND is active
  Future<void> checkCurrentDndStatus() async {
    try {
      final bool systemDndActive = await platform.invokeMethod('isDNDEnabled');
            isDndActive.value    = systemDndActive;
    } catch (e) {
      log("Failed to fetch native DND status profile mapping: $e");
    }
  }

    /// Triggers a native system invocation request to switch Do Not Disturb states
  Future<void> toggleDoNotDisturb(BuildContext context, bool targetState) async {
    try {
      final bool success = await platform.invokeMethod('setDNDMode', {'enabled': targetState});
      if (success) {
        isDndActive.value = targetState;
      }
    } on PlatformException catch (e) {
      if (e.code == 'MISSING_PERMISSION') {
          // ignore: use_build_context_synchronously
        _showDndPermissionDialog(context);
      }
    }
  }

    /// Adjusts the tracking configuration state for the environment App Timers interface
  void toggleAppTimers(bool targetState) {
    appTimersActive.value = targetState;
  }

    /// Triggers a direct platform gateway lookup to launch the native system DND access panel
  Future<void> openDNDSettings() async {
    try {
      await platform.invokeMethod('openDNDPermissionSettings');
    } catch (e) {
      log("Could not open native permission configuration panel: $e");
    }
  }

    /// Prompting layout dialog asking the user to grant Notification Policy Access permissions
  void _showDndPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape          : const LinearBorder(),   // Un-rounded sharp edge minimalist window frame
        title          : const Text(
          'SYSTEM PERMISSION REQUIRED', 
          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        content: Text(
          'Zen Launcher needs notification policy access to automatically suppress incoming calls and message alerts.',
          style: TextStyle(color: Colors.grey[400], fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child    : Text('CANCEL', style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openDNDSettings();
            },
            child: const Text('GRANT ACCESS', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

    // =================================================================
    // NOTIFICATION BACKGROUND ROUTING MANAGEMENT
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
        foreground : true,
        title      : "Zen Focus Active",
        description: "Filtering background distractions...",
      );
    }

    isListenerRunning.value = true;
    log("Notification communication bridge successfully bound.");
  }

  void _handleIncomingUiNotification(NotificationEvent event) {
    log('Notification intercepted from: ${event.packageName}');
    if (event.title == null && event.text == null) return;

    String textSignature(String? fullText) {
      if (fullText == null || fullText.isEmpty) return '';
      return fullText.length > 15 ? fullText.substring(0, 15): fullText;
    }

    final String incomingSig = textSignature(event.text);

    int duplicateIndex = collectedNotifications.indexWhere((existing) =>
      existing.packageName         == event.packageName &&
      existing.title               == event.title &&
      textSignature(existing.text) == incomingSig
    );

    if (duplicateIndex != -1) {
      log('Duplicate ticker pattern detected. Replacing older entry with latest update.');
      collectedNotifications.removeAt(duplicateIndex);
    }

    collectedNotifications.add(event); 
    collectedNotifications.refresh(); 
  }

    // =================================================================
    // DEEP LINK NAVIGATION DISPATCHER
    // =================================================================
  Future<void> openNotificationTargetApp(NotificationEvent event) async {
    try {
      log("Processing deep-intent routing logic for package: ${event.packageName}");
      
      collectedNotifications.remove(event);
      collectedNotifications.refresh();

      if (event.canTap == true) {
        bool success = await event.tap();
        if (success) {
          log("SUCCESS: Routed directly to target deep link nested window.");
          return; 
        }
      }
      
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
      orElse: ()       => 'APP'
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
            isLoadingApps.value    = true;
      final List<dynamic>? rawApps = await platform.invokeMethod('getInstalledApps');
      
      if (rawApps != null) {
        installedApps.value = rawApps.map((item) {
          final Map<dynamic, dynamic> appMap = item as Map<dynamic, dynamic>;
          return AppModel(
            name       : appMap['name'] ?? 'Unknown',
            packageName: appMap['packageName'] ?? '',
            iconBytes  : appMap['icon'] as Uint8List?,
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

  List<AppModel> get filteredApps {
    if (searchQuery.value.isEmpty) {
      return installedApps;
    }
    return installedApps.where((app) => 
      app.name.toLowerCase().contains(searchQuery.value.toLowerCase())
    ).toList();
  }

  // =================================================================
  // PERMISSIONLESS LOCAL SCREEN TIME TRACKING
  // =================================================================

  /// Sets up platform handlers and initializes the countdown engine
  void initLocalScreenTimeTracking() {
      // 1. Establish the platform channel handler for native Android screen broadcast events
    platform.setMethodCallHandler((call) async {
      if (call.method == "onScreenStateChanged") {
        final bool isScreenActive = call.arguments as bool;
        _handleScreenStateUpdate(isScreenActive);
      }
    });

      // 2. Baseline initialization configuration
    _accumulatedSecondsToday = 0;
    
      // 3. Fire up the periodic display ticker tracking engine
    _startDisplayTicker();
  }

  void _handleScreenStateUpdate(bool isScreenActive) {
    _isDeviceScreenOn = isScreenActive;
    if (_isDeviceScreenOn) {
      log("Device awake event caught. Resuming countdown calculations...");
      _startDisplayTicker();
    } else {
      log("Device sleep event caught. Pausing countdown tracking...");
      _tickerTimer?.cancel();
    }
  }

  void _startDisplayTicker() {
    _tickerTimer?.cancel();  // Clear old structural instances
    
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDeviceScreenOn) {
        _accumulatedSecondsToday++;
        _updateDisplayString();
        
          // Automatical count-reset protocol precisely at midnight midnight
        final now = DateTime.now();
        if (now.hour == 0 && now.minute == 0 && now.second == 0) {
          _accumulatedSecondsToday = 0;
        }
      }
    });
  }
  
  void clearNotificationsForPackage(String packageName) {
    collectedNotifications.removeWhere((event) => event.packageName == packageName);
    collectedNotifications.refresh();
    log("Cleared all notification event allocations for package: $packageName");
  }

  void _updateDisplayString() {
    final duration = Duration(seconds: _accumulatedSecondsToday);
    final hours    = duration.inHours.toString().padLeft(2, '0');
    final minutes  = (duration.inMinutes % 60).toString().padLeft(2, '0');
      // final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
      // todayScreenTime.value = "$hours:$minutes:$seconds";
    todayScreenTime.value = "$hours:$minutes";
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