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
import 'package:get_storage/get_storage.dart';
import 'package:local_auth/local_auth.dart';
// ignore: depend_on_referenced_packages
import 'package:local_auth_android/local_auth_android.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zen_launcher/src/config/app_config.dart';
import 'package:zen_launcher/src/widget/permission_disclosure.dart';

class AppController extends GetxController with WidgetsBindingObserver {
  final dndPlugin = DoNotDisturbPlugin();
  final localAuth = LocalAuthentication();
  final _storage = GetStorage();
  
    // --- PLATFORM COMMUNICATION GATEWAYS ---
  static const platform                          = MethodChannel('com.zen_launcher/battery');
  static const MethodChannel notificationChannel = MethodChannel('com.zen_launcher/notifications');

    // --- GETX REACTIVE STATE VARIABLES ---
  var isListenerRunning = false.obs;
  var isDndActive       = false.obs;
  var appTimersActive   = false.obs;
  var isScreenOn        = true.obs;

    // --- APP TIMER / USAGE TRACKING ---
  var usageAccessGranted = false.obs;
  var todayAppUsage      = <String, int>{}.obs; // packageName -> foreground millis today
  var appDailyLimits     = <String, int>{}.obs; // packageName -> daily limit in minutes
  
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
  var installedApps     = <AppModel>[].obs;
  var hiddenAppPackages = <String>{}.obs;
  var isLoadingApps     = false.obs;
  var searchQuery       = ''.obs;
  var showIcons         = true.obs;

    // --- DYNAMIC WORKSPACE SLOTS (MAX 6 CUSTOM ADDS) ---
  var pinnedHomeApps = <String>[].obs;

  var isDoubleTapLockEnabled = false.obs;  // Defaults to off

    // --- DEFAULT HOME / LAUNCHER ROLE ---
  var isDefaultLauncher = false.obs;

    // --- THE INTERRUPTER PROPERTIES ---
  var isInterrupterActive         = false.obs;
  var interrupterRemainingSeconds = 5.obs;
  var currentInterruptedPackage   = '';
  Timer? interrupterTimer;

  @override
  Future<void> onInit() async {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    
    // Core Launcher Lifecycle Initialization Hooks
    await checkDefaultLauncher();
    await startZenModeWorkflow();
    await fetchInstalledApps();
    await initAppTimers();
    
    // Fire Up Local Screen Activity Trackers
    initLocalScreenTimeTracking();
    syncDoubleTapToggleWithSystem();

    // Ask once to become the HOME app (only after notification setup settles).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      maybePromptDefaultLauncher();
    });
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
      checkDefaultLauncher();
      maybePromptDefaultLauncher();
      syncDoubleTapToggleWithSystem();
      syncAppTimersWithSystem();
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
      // Only auto-prompt once, and only after showing Play-required disclosure.
      // After that the user can reconnect from ZEN CONTROL > Notification Access.
      final bool alreadyAsked = _storage.read<bool>('notification_disclosure_seen') ?? false;
      if (!alreadyAsked) {
        _storage.write('notification_disclosure_seen', true);
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await requestNotificationAccess();
        });
      }
      return;
    }

    // Sync current native hardware DND status flags on app startup
    await checkCurrentDndStatus();
    await checkAndRequestBatteryExemption();
    await initializeNotificationCollector();
  }

  /// Shows the Play-required disclosure and then opens Notification Access settings.
  Future<void> requestNotificationAccess() async {
    final bool accepted = await showPermissionDisclosure(
      eyebrow: 'NOTIFICATION ACCESS',
      title: 'YOUR NOTIFICATION VAULT',
      body:
          'Zen Launcher reads notification titles and text so it can show them in your Notification Vault while Zen mode is active. '
          'This content stays on this device, is never uploaded or shared, and is cleared when you clear the Vault or close the app. '
          'You can turn this access off at any time in Android Settings.',
      continueLabel: 'CONTINUE',
    );

    if (!accepted) return;

    _storage.write('notification_disclosure_accepted', true);
    await NotificationsListener.openPermissionSettings();
  }

  Future<void> openBatterySettings() async {
    try {
      await BatteryOptimizationHelper.openBatteryOptimizationSettings();
    } catch (e) {
      log("Could not open battery optimization settings: $e");
    }
  }

  /// Opens the public privacy policy in the browser.
  ///
  /// The entry point is hidden while [privacyPolicyUrl] is empty, so this is a
  /// no-op until a URL is configured.
  Future<void> openPrivacyPolicy() async {
    if (privacyPolicyUrl.isEmpty) return;

    try {
      final bool opened = await launchUrl(
        Uri.parse(privacyPolicyUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        log("Could not open the privacy policy URL.");
      }
    } catch (e) {
      log("Could not open the privacy policy URL: $e");
    }
  }

  /// Reads whether Zen is currently the system HOME app.
  Future<void> checkDefaultLauncher() async {
    try {
      final bool isDefault = await platform.invokeMethod('isDefaultLauncher') ?? false;
      isDefaultLauncher.value = isDefault;
    } catch (e) {
      log("Error checking default launcher state: $e");
      isDefaultLauncher.value = false;
    }
  }

  /// Opens the system prompt/settings to make Zen the default home app.
  Future<void> requestDefaultLauncher() async {
    try {
      await platform.invokeMethod('requestDefaultLauncher');
    } on PlatformException catch (e) {
      log("Failed to open default launcher settings: ${e.message}");
    }
  }

  /// Nudges the user once to make Zen the system HOME app.
  ///
  /// Runs only after the notification-access flow has been handled so two system
  /// prompts never overlap on a fresh install.
  Future<void> maybePromptDefaultLauncher() async {
    await checkDefaultLauncher();
    if (isDefaultLauncher.value) return;

    final bool alreadyPrompted = _storage.read<bool>('default_launcher_prompted') ?? false;
    if (alreadyPrompted || Get.isDialogOpen == true) return;

    final bool notificationDisclosureSeen =
        _storage.read<bool>('notification_disclosure_seen') ?? false;
    final bool listenerGranted = (await NotificationsListener.hasPermission) ?? false;
    if (!notificationDisclosureSeen && !listenerGranted) return;

    _storage.write('default_launcher_prompted', true);

    final bool accepted = await showPermissionDisclosure(
      eyebrow: 'HOME APP',
      title: 'MAKE ZEN YOUR HOME',
      body:
          'Zen is a launcher, so it needs to be your default home app. That keeps it in place when you press Home '
          'instead of letting Android minimize it back to your old launcher. '
          'You can change this any time in Android Settings.',
      continueLabel: 'SET AS HOME',
      declineLabel: 'NOT NOW',
    );

    if (accepted) {
      await requestDefaultLauncher();
    }
  }

  Future<void> checkAndRequestBatteryExemption() async {
    try {
      final bool isIgnoring = await platform.invokeMethod('isIgnoringBattery');
      if (!isIgnoring) {
        // Do not open system settings on every launcher start. Prompt once;
        // the user can reopen this from ZEN CONTROL > Background Reliability.
        final bool alreadyPrompted = _storage.read<bool>('battery_opt_prompted') ?? false;
        if (!alreadyPrompted) {
          _storage.write('battery_opt_prompted', true);
          log("Launcher is being optimized by battery saver. Prompting user once...");
          await BatteryOptimizationHelper.openBatteryOptimizationSettings();
        }
      } else {
        log("Launcher is already white-listed from battery saving.");
      }
    } on PlatformException catch (e) {
      log("Failed to check battery status: ${e.message}");
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
        // ignore: use_build_context_synchronously
        await requestDndAccess(context);
      }
    }
  }

  Future<void> toggleAppTimers(bool targetState) async {
    if (!targetState) {
      appTimersActive.value = false;
      _storage.write('app_timers_active', false);
      return;
    }

    final bool granted = await checkUsageAccess();
    if (!granted) {
      final bool accepted = await showPermissionDisclosure(
        eyebrow: 'USAGE ACCESS',
        title: 'APP TIMERS',
        body:
            'Zen Launcher reads how long apps have been in the foreground today so it can enforce the daily limits you set. '
            'Usage data stays on this device and is never uploaded or shared. '
            'You can revoke Usage Access at any time in Android Settings.',
        continueLabel: 'CONTINUE',
      );

      if (!accepted) {
        appTimersActive.value = false;
        return;
      }

      // Remember the intent so the toggle turns on automatically when the
      // user returns from the Usage Access screen.
      _storage.write('app_timers_active', true);
      await openUsageAccessSettings();
      return;
    }

    await refreshUsageStats();
    appTimersActive.value = true;
    _storage.write('app_timers_active', true);
  }

  Future<bool> checkUsageAccess() async {
    try {
      final bool granted = await platform.invokeMethod('hasUsageAccess') ?? false;
      usageAccessGranted.value = granted;
      return granted;
    } catch (e) {
      log("Error checking Usage Access: $e");
      usageAccessGranted.value = false;
      return false;
    }
  }

  Future<void> openUsageAccessSettings() async {
    try {
      await platform.invokeMethod('openUsageAccessSettings');
    } catch (e) {
      log("Could not open Usage Access settings: $e");
    }
  }

  Future<void> initAppTimers() async {
    final dynamic stored = _storage.read('app_daily_limits');
    if (stored is Map) {
      appDailyLimits.clear();
      stored.forEach((key, value) {
        if (value is num) {
          appDailyLimits[key.toString()] = value.toInt();
        }
      });
    }
    await syncAppTimersWithSystem();
  }

  /// Reconciles the App Timers toggle with the real Usage Access state.
  Future<void> syncAppTimersWithSystem() async {
    final bool granted = await checkUsageAccess();

    if (!granted) {
      appTimersActive.value = false;
      _storage.write('app_timers_active', false);
      todayAppUsage.clear();
      return;
    }

    final bool requested = _storage.read<bool>('app_timers_active') ?? false;
    appTimersActive.value = requested;
    if (requested) {
      await refreshUsageStats();
    }
  }

  Future<void> refreshUsageStats() async {
    if (!await checkUsageAccess()) {
      todayAppUsage.clear();
      return;
    }

    try {
      final Map<dynamic, dynamic>? raw = await platform.invokeMethod('getTodayUsage');
      if (raw == null) return;

      todayAppUsage.assignAll(
        raw.map((key, value) => MapEntry(key.toString(), (value as num).toInt())),
      );
    } catch (e) {
      log("Could not refresh app usage stats: $e");
    }
  }

  void setAppLimit(String packageName, int minutes) {
    if (minutes <= 0) {
      appDailyLimits.remove(packageName);
    } else {
      appDailyLimits[packageName] = minutes;
    }
    appDailyLimits.refresh();
    _storage.write('app_daily_limits', Map<String, int>.from(appDailyLimits));
  }

  int getUsedMinutes(String packageName) {
    return ((todayAppUsage[packageName] ?? 0) / 60000).floor();
  }

  bool isAppOverLimit(String packageName) {
    if (!appTimersActive.value) return false;
    final int? limit = appDailyLimits[packageName];
    if (limit == null || limit <= 0) return false;
    return (todayAppUsage[packageName] ?? 0) >= limit * 60 * 1000;
  }

  void _showLimitReached(String packageName) {
    final int limit = appDailyLimits[packageName] ?? 0;
    final String appName = getAppNameOf(packageName);

    Get.dialog(
      AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        shape: const LinearBorder(),
        title: Text(
          '$appName LIMIT REACHED',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        content: Text(
          'You have used your $limit minute daily limit for $appName. '
          'Take a break and come back tomorrow.',
          style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text(
              'GO BACK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> openDNDSettings() async {
    try {
      await platform.invokeMethod('openDNDPermissionSettings');
    } catch (e) {
      log("Could not open native permission configuration panel: $e");
    }
  }

  Future<void> requestDndAccess(BuildContext context) async {
    final bool accepted = await showPermissionDisclosure(
      eyebrow: 'DO NOT DISTURB ACCESS',
      title: 'SILENCE THE NOISE',
      body:
          'Zen Launcher needs notification policy access to turn Do Not Disturb on and off for you. '
          'This only changes the system Do Not Disturb state. It does not read, store, or upload your calls, messages, or notification content. '
          'You can revoke this access at any time in Android Settings.',
      continueLabel: 'GRANT ACCESS',
    );

    if (!accepted || !context.mounted) return;
    await openDNDSettings();
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

  /// The absolute master click handler—no conditions, always blocks first!
  Future<void> launchApplicationContainer(String packageName) async {
    if (appTimersActive.value) {
      await refreshUsageStats();
      if (isAppOverLimit(packageName)) {
        log("Daily limit reached for $packageName. Blocking launch.");
        _showLimitReached(packageName);
        return;
      }
    }

    log("Intercepting launch intent for $packageName. Showing Interrupter immediately.");
    triggerInterrupterGate(packageName);
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

  Future<void> lockDeviceScreen() async {
    try {
      final bool success = await platform.invokeMethod('lockScreen');
      if (success) {
        log("Hardware lock sequence fired successfully.");
      }
    } on PlatformException catch (e) {
      log("Failed to execute platform hardware screen lock: ${e.message}");

      if (e.code == "DISABLED" || e.code == "REJECTED") {
        Get.snackbar(
          'DEVICE ADMIN REQUIRED',
          'Tap here to authorize Zen Launcher to sleep the screen automatically.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.black,
          colorText: Colors.white,
          borderRadius: 0,
          duration: const Duration(seconds: 4),
          onTap: (_) {
            requestDeviceAdminPermission();
          },
        );
      }
    }
  }

  Future<void> requestDeviceAdminPermission() async {
    try {
      await platform.invokeMethod('requestDeviceAdmin');
      log("Redirected user to the Android device admin screen.");
    } on PlatformException catch (e) {
      log("Failed to launch device admin screen: ${e.message}");
    }
  }

  Future<void> removeDeviceAdminPermission() async {
    try {
      await platform.invokeMethod('removeDeviceAdmin');
    } on PlatformException catch (e) {
      log("Failed to remove device admin: ${e.message}");
    }
  }

  /// Manages the activation state based on real system confirmation
  Future<void> toggleDoubleTapLock(bool targetState) async {
    if (targetState) {
      final bool accepted = await showPermissionDisclosure(
        eyebrow: 'DEVICE ADMIN',
        title: 'DOUBLE-TAP TO LOCK',
        body:
            'Zen Launcher uses Android\'s device administrator only to turn the screen off when you double-tap an empty area of the home screen. '
            'It cannot erase the device, change your password, or modify any other setting. '
            'You can remove it at any time from Android Settings > Security > Device admin apps.',
        continueLabel: 'CONTINUE',
      );

      if (!accepted) {
        isDoubleTapLockEnabled.value = false;
        return;
      }

      await requestDeviceAdminPermission();
      // The toggle is reconciled by syncDoubleTapToggleWithSystem() when the
      // user returns from the system screen.
    } else {
      isDoubleTapLockEnabled.value = false;
      await removeDeviceAdminPermission();
    }
  }

  /// Native helper that returns true/false from Android OS
  Future<bool> checkDeviceAdminPermission() async {
    try {
      final bool isEnabled = await platform.invokeMethod('checkDeviceAdminPermission');
      return isEnabled;
    } catch (e) {
      log("Error checking device admin permission: $e");
      return false;
    }
  }

  /// Checks the actual native OS state and forces the UI switch to match it perfectly
  Future<void> syncDoubleTapToggleWithSystem() async {
    final bool hasPermission = await checkDeviceAdminPermission();
    isDoubleTapLockEnabled.value = hasPermission;
  }

  /// Handles the countdown ticking
  void triggerInterrupterGate(String packageName) {
    currentInterruptedPackage = packageName;
    interrupterRemainingSeconds.value = 5; // Reset countdown token to 5
    isInterrupterActive.value = true;

    interrupterTimer?.cancel();
    interrupterTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (interrupterRemainingSeconds.value > 1) {
        interrupterRemainingSeconds.value--;
      } else {
        // --- CHOSEN BEHAVIOR ---
        // If the user doesn't touch anything, the timer expires and kicks them back automatically!
        log("User left idle. Resetting environment baseline.");
        cancelInterrupter();
      }
    });
  }

  void cancelInterrupter() {
    interrupterTimer?.cancel();
    isInterrupterActive.value = false;
    currentInterruptedPackage = '';
  }

  void completeOverride() {
    interrupterTimer?.cancel();
    isInterrupterActive.value = false;
    
    // Launch the target app now that intention is proven
    if (currentInterruptedPackage.isNotEmpty) {
      _directNativeLaunch(currentInterruptedPackage);
    }
  }

  /// Direct pass-through that invokes the native Android intent to open the app
  Future<void> _directNativeLaunch(String packageName) async {
    try {
      // Fires the launch command down the method channel pipe to MainActivity.kt
      await platform.invokeMethod('launchApp', packageName);
    } catch (e) {
      log("Could not open app $packageName via native execution channel: $e");
      Get.snackbar(
        'LAUNCH FAILED',
        'Application could not be resolved by the system pipeline.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.black,
        colorText: Colors.white,
        borderRadius: 0,
      );
    }
  }

  /// Restarts the countdown ticking without resetting the remaining seconds token
  void resumeInterrupterCountdown() {
    interrupterTimer?.cancel();
    interrupterTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (interrupterRemainingSeconds.value > 1) {
        interrupterRemainingSeconds.value--;
      } else {
        log("User left idle after release. Resetting environment baseline.");
        cancelInterrupter();
      }
    });
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