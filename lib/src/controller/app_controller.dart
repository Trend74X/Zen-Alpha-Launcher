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
import 'package:local_auth/local_auth.dart';
// ignore: depend_on_referenced_packages
import 'package:local_auth_android/local_auth_android.dart';

class AppController extends GetxController with WidgetsBindingObserver {
  final dndPlugin = DoNotDisturbPlugin();
  final localAuth = LocalAuthentication();
  
  // --- PLATFORM COMMUNICATION GATEWAYS ---
  static const platform = MethodChannel('com.zen_launcher/battery');
  static const MethodChannel notificationChannel = MethodChannel('com.zen_launcher/notifications');

  // --- GETX REACTIVE STATE VARIABLES ---
  var isListenerRunning = false.obs;
  var isDndActive       = false.obs;
  var appTimersActive   = false.obs;
  var isScreenOn        = true.obs;
  
  // Master thread-safe collection of notifications displayed in Zen view layers
  var collectedNotifications = <NotificationEvent>[].obs;
  var appLabelCache          = <String, String>{}.obs;

  // --- USER WORKSPACE CLOCK METRICS ---
  var todayScreenTime = "00:00".obs;
  Timer? _tickerTimer;
  int  _accumulatedSecondsToday = 0;     
  bool _isDeviceScreenOn        = true;  

  // Native hardware platform port pipeline communication memory trace
  ReceivePort? _uiReceivePort;

  // --- APPLICATION REPOS & VAULTS ---
  var installedApps = <AppModel>[].obs;
  var hiddenAppPackages = <String>{}.obs;
  var isLoadingApps = false.obs;
  var searchQuery   = ''.obs;
  var showIcons     = true.obs;          

  // --- DYNAMIC WORKSPACE SLOTS (MAX 6 CUSTOM ADDS) ---
  var pinnedHomeApps = <String>[].obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    
    // Core Launcher Lifecycle Initialization Hooks
    await startZenModeWorkflow();
    await fetchInstalledApps();
    
    // Fire Up Local Screen Activity Trackers
    initLocalScreenTimeTracking();
  } 

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _uiReceivePort?.close();
    _tickerTimer?.cancel();
    IsolateNameServer.removePortNameMapping("_listener_");
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
  // REACTIVE COMPUTED CHANNEL-GROUPING PROPERTIES
  // =================================================================
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
  // PERMISSION & SYSTEM WORKFLOW BOOTSTRAPPERS
  // =================================================================
  Future<void> startZenModeWorkflow() async {
    bool hasListenerPermission = (await NotificationsListener.hasPermission) ?? false;
    if (!hasListenerPermission) {
      log('Notification Listener Permission missing. Prompting user...');
      await NotificationsListener.openPermissionSettings();
      return; 
    }

    // Sync current native hardware DND status flags on app startup
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
  // PROGRAMMATIC DO NOT DISTURB & ENVIRONMENT CONFIGURATORS
  // =================================================================
  Future<void> checkCurrentDndStatus() async {
    try {
      final bool systemDndActive = await platform.invokeMethod('isDNDEnabled');
      isDndActive.value    = systemDndActive;
    } catch (e) {
      log("Failed to fetch native DND status profile mapping: $e");
    }
  }

  Future<void> toggleDoNotDisturb(BuildContext context, bool targetState) async {
    try {
      final bool success = await platform.invokeMethod('setDNDMode', {'enabled': targetState});
      if (success) {
        isDndActive.value = targetState;
      }
    } on PlatformException catch (e) {
      if (e.code == 'MISSING_PERMISSION') {
        _showDndPermissionDialog(context);
      }
    }
  }

  void toggleAppTimers(bool targetState) {
    appTimersActive.value = targetState;
  }

  Future<void> openDNDSettings() async {
    try {
      await platform.invokeMethod('openDNDPermissionSettings');
    } catch (e) {
      log("Could not open native permission configuration panel: $e");
    }
  }

  void _showDndPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        shape: const LinearBorder(),   
        title: const Text(
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
            child: Text('CANCEL', style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold)),
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
  // ISOLATED PORT LISTENER NOTIFICATION PIPELINE
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
    // Safety Catch: Prevent null crashes or unwanted low-priority platform loops
    if (event.packageName == null || (event.title == null && event.text == null)) return;

    // Double Safeguard: Filter package drops out of UI parsing structures if background handler leaks them
    final blockedPackages = const ['android', 'com.android.systemui', 'com.google.android.inputmethod.latin'];
    if (blockedPackages.contains(event.packageName!.toLowerCase())) {
      log("UI thread intercepted and discarded a low-priority system package leakage.");
      return; 
    }

    log('Notification parsed into UI pipeline from: ${event.packageName}');

    String textSignature(String? fullText) {
      if (fullText == null || fullText.isEmpty) return '';
      return fullText.length > 15 ? fullText.substring(0, 15) : fullText;
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

  void clearNotificationsForPackage(String packageName) {
    collectedNotifications.removeWhere((event) => event.packageName == packageName);
    collectedNotifications.refresh();
    log("Cleared all notification event allocations for package: $packageName");
  }

  // =================================================================
  // APPLICATION ENGINE METADATA PARSERS & GENERATORS
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

  // =================================================================
  // PRIVATE SECURITY SECURE VAULT ENGINE (HIDDEN APPLICATIONS)
  // =================================================================
  void hideApplication(String packageName) {
    hiddenAppPackages.add(packageName);
    hiddenAppPackages.refresh();
    log("Application structural footprint hidden from matrix: $packageName");
  }

  void revealApplication(String packageName) {
    hiddenAppPackages.remove(packageName);
    hiddenAppPackages.refresh();
    log("Application context revealed back to main space: $packageName");
  }

  List<AppModel> get filteredApps {
    final visibleApps = installedApps.where((app) => !hiddenAppPackages.contains(app.packageName));

    if (searchQuery.value.isEmpty) {
      return visibleApps.toList();
    }
    return visibleApps.where((app) => 
      app.name.toLowerCase().contains(searchQuery.value.toLowerCase())
    ).toList();
  }

  Future<void> launchApplicationContainer(String packageName) async {
    try {
      await platform.invokeMethod('launchApp', packageName);
    } catch (e) {
      log("Could not open app $packageName: $e");
    }
  }

  // =================================================================
  // DYNAMIC HOME SCREEN ADDITIONS SLOTS (MAX 6 EXTRA SLOTS)
  // =================================================================
  bool isAppPinnedToHome(String packageName) {
    return pinnedHomeApps.contains(packageName);
  }

  void pinAppToHome(String packageName) {
    if (!pinnedHomeApps.contains(packageName)) {
      // STRICT CAP GUARD: Phone and Messages are hardcoded, allow exactly 6 dynamic links max
      if (pinnedHomeApps.length < 6) { 
        pinnedHomeApps.add(packageName);
        pinnedHomeApps.refresh();
        log("App pinned to home workspace canvas: $packageName");
      } else {
        Get.snackbar(
          'WORKSPACE SATURATED',
          'Maximum allocation capacity reached (6 apps max).',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.black,
          colorText: Colors.white,
          borderRadius: 0,
        );
      }
    }
  }

  void unpinAppFromHome(String packageName) {
    if (pinnedHomeApps.contains(packageName)) {
      pinnedHomeApps.remove(packageName);
      pinnedHomeApps.refresh();
      log("App pulled off home workspace canvas: $packageName");
    }
  }

  // =================================================================
  // SCREEN ACTIVATION TRACKING (METRIC LOGGERS)
  // =================================================================
  void initLocalScreenTimeTracking() {
    platform.setMethodCallHandler((call) async {
      if (call.method == "onScreenStateChanged") {
        final bool isScreenActive = call.arguments as bool;
        _handleScreenStateUpdate(isScreenActive);
      }
    });

    _accumulatedSecondsToday = 0;
    _startDisplayTicker();
  }

  void _handleScreenStateUpdate(bool isScreenActive) {
    _isDeviceScreenOn = isScreenActive;
    isScreenOn.value = isScreenActive;
    if (_isDeviceScreenOn) {
      log("Device awake event caught. Resuming countdown calculations...");
      _startDisplayTicker();
    } else {
      log("Device sleep event caught. Pausing countdown tracking...");
      _tickerTimer?.cancel();
    }
  }

  void _startDisplayTicker() {
    _tickerTimer?.cancel();  
    
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDeviceScreenOn) {
        _accumulatedSecondsToday++;
        _updateDisplayString();
        
        final now = DateTime.now();
        if (now.hour == 0 && now.minute == 0 && now.second == 0) {
          _accumulatedSecondsToday = 0;
        }
      }
    });
  }

  void _updateDisplayString() {
    final duration = Duration(seconds: _accumulatedSecondsToday);
    final hours    = duration.inHours.toString().padLeft(2, '0');
    final minutes  = (duration.inMinutes % 60).toString().padLeft(2, '0');
    todayScreenTime.value = "$hours:$minutes";
  }

  Future<bool> authenticateUserSecurely({required String reason}) async {
    try {
      final bool canAuthenticateWithBiometrics = await localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await localAuth.isDeviceSupported();
      
      if (!canAuthenticateWithBiometrics && !isDeviceSupported) {
        log("Security Layer Error: Device lacks lockscreen credential validation setups.");
        return false;
      }

      return await localAuth.authenticate(
        localizedReason: reason,
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'ARCHITECTURAL UNLOCK',
            cancelButton: 'CANCEL',
          ),
        ],
      );
    } catch (error) {
      log("Authentication exception intercepted: $error");
      return false; 
    }
  }
}

class AppModel {
  final String name;
  final String packageName;
  final Uint8List? iconBytes;

  AppModel({required this.name, required this.packageName, this.iconBytes});
}

// =================================================================
// ISOLATE BACKGROUND ENTRY TASK HANDLER (STAYS TOP LEVEL)
// =================================================================
@pragma('vm:entry-point')
void backgroundNotificationHandler(NotificationEvent event) {
  // Extract package signature strings cleanly
  final String currentPackage = event.packageName?.toLowerCase() ?? '';

  // Core System Pipeline Blacklist Filtering
  // Discards keyboard selection prompts ("Choose input method") right at the background boundary!
  final blacklistedPackages = const [
    'android',
    'com.android.systemui',
    'com.google.android.inputmethod.latin'
  ];

  if (blacklistedPackages.contains(currentPackage)) {
    return; // Drop system processes silently without processing
  }

  final SendPort? sendPort = IsolateNameServer.lookupPortByName("_listener_");
  if (sendPort != null) {
    sendPort.send(event);
  }
}