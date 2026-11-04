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
  DateTime _screenTimeDay       = DateTime.now();

    // Native hardware platform port pipeline communication memory trace
  ReceivePort? _uiReceivePort;
  bool _notificationBridgeInitialized = false;

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

    // --- SYSTEM NAVIGATION STYLE (read-only; Android/OEM owns this) ---
  var navigationMode   = (-1).obs; // 0=3-button, 1=2-button, 2=gesture, -1=unknown
  var deviceManufacturer = ''.obs;

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
    _loadWorkspacePreferences();
    await checkDefaultLauncher();
    await refreshNavigationMode();
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
      refreshNavigationMode();
      maybePromptDefaultLauncher();
      syncDoubleTapToggleWithSystem();
      syncAppTimersWithSystem();
      refreshScreenTime();
    }
  }

  /// Restores workspace choices that previously lived only in memory.
  ///
  /// Without this, pinned home apps, hidden apps, and the icon-visibility
  /// toggle all reset every time Android killed and recreated the launcher.
  void _loadWorkspacePreferences() {
    final dynamic storedPinned = _storage.read('pinned_home_apps');
    if (storedPinned is List) {
      pinnedHomeApps.assignAll(storedPinned.whereType<String>());
    }

    final dynamic storedHidden = _storage.read('hidden_app_packages');
    if (storedHidden is List) {
      hiddenAppPackages.assignAll(storedHidden.whereType<String>());
    }

    showIcons.value = _storage.read<bool>('show_icons') ?? true;
  }

  void _persistPinnedApps() {
    _storage.write('pinned_home_apps', pinnedHomeApps.toList());
  }

  void _persistHiddenApps() {
    _storage.write('hidden_app_packages', hiddenAppPackages.toList());
  }

  /// Persists the app-drawer icon visibility preference.
  void setShowIcons(bool value) {
    showIcons.value = value;
    _storage.write('show_icons', value);
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

  /// True when this installed build actually declares a HOME activity.
  ///
  /// If false, Android cannot offer Zen on the Home-app picker at all. That
  /// usually means a stale or partially installed APK, so the UI should say so
  /// instead of sending the user to a settings screen that cannot help.
  Future<bool> isHomeActivityRegistered() async {
    try {
      return await platform.invokeMethod<bool>('isHomeActivityRegistered') ?? true;
    } catch (e) {
      log("Error checking HOME registration: $e");
      return true;
    }
  }

  /// The package name of the current HOME app, used in help text.
  Future<String?> currentHomePackage() async {
    try {
      return await platform.invokeMethod<String>('getCurrentHomePackage');
    } catch (e) {
      log("Error reading current HOME app: $e");
      return null;
    }
  }

  /// Guides the user through making Zen the system HOME app.
  ///
  /// Android does not allow an app to promote itself silently; the user must
  /// pick Zen on a system screen. Show exact instructions and give them two
  /// ways in, because the RoleManager prompt is hidden on several OEM skins.
  Future<void> requestDefaultLauncher() async {
    if (Get.isDialogOpen == true) return;

    await checkDefaultLauncher();
    if (isDefaultLauncher.value) {
      _showHomeSnack(
        'ZEN IS ALREADY HOME',
        'Pressing Home already opens Zen. Change this any time in Android Settings.',
      );
      return;
    }

    if (!await isHomeActivityRegistered()) {
      await _showHomeRegistrationError();
      return;
    }

    final String? currentHome = await currentHomePackage();
    final String currentHomeLine =
        (currentHome == null || currentHome == appPackageName)
            ? ''
            : '\n\nCurrent Home app: $currentHome';

    final String? choice = await Get.dialog<String>(
      AlertDialog(
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.zero,
        ),
        title: const Text(
          'MAKE ZEN YOUR HOME',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        content: Text(
          'Android only changes the Home app from system settings.\n\n'
          '1. Open Home app settings.\n'
          '2. Choose Zen Alpha.\n'
          '3. Press Home. Zen stays put instead of minimizing.'
          '$currentHomeLine',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
            height: 1.5,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Get.back(result: 'prompt'),
            child: const Text('SYSTEM PROMPT'),
          ),
          TextButton(
            onPressed: () => Get.back(result: 'settings'),
            child: const Text('OPEN SETTINGS'),
          ),
        ],
      ),
      barrierDismissible: true,
    );

    if (choice == 'prompt') {
      await _requestHomeRolePrompt();
    } else if (choice == 'settings') {
      await openHomeSettings();
    }
  }

  /// Fires the RoleManager HOME prompt and explains the next step if Android
  /// suppresses it (common on MIUI, One UI, and some carrier builds).
  Future<void> _requestHomeRolePrompt() async {
    try {
      final String outcome =
          await platform.invokeMethod<String>('requestDefaultLauncher') ?? 'unavailable';

      // Let the system screen take focus before checking whether the user
      // actually selected Zen. This also keeps the snackbar from covering it.
      await Future<void>.delayed(const Duration(seconds: 2));
      await checkDefaultLauncher();

      if (isDefaultLauncher.value) {
        _showHomeSnack('ZEN IS HOME', 'Home now returns to Zen.');
        return;
      }

      if (outcome == 'unavailable') {
        await openHomeSettings();
        return;
      }

      _showHomeSnack(
        'ONE MORE STEP',
        'Choose Zen Alpha on the system screen. Tap here if it did not open.',
        onTap: openHomeSettings,
      );
    } on PlatformException catch (e) {
      log("Failed to open default launcher settings: ${e.message}");
      await openHomeSettings();
    }
  }

  /// Opens Android's Home-app picker directly (works on more OEM builds than
  /// the RoleManager prompt).
  Future<void> openHomeSettings() async {
    try {
      final bool opened =
          await platform.invokeMethod<bool>('openHomeSettings') ?? false;
      if (!opened) {
        _showHomeSettingsManualInstructions();
      }
    } on PlatformException catch (e) {
      log("Failed to open Home app settings: ${e.message}");
      _showHomeSettingsManualInstructions();
    }
  }

  // =================================================================
  // SYSTEM NAVIGATION STYLE
  // =================================================================

  /// Human-readable name for the OS navigation style.
  String get navigationModeLabel {
    switch (navigationMode.value) {
      case 0:
        return '3-button navigation';
      case 1:
        return '2-button navigation';
      case 2:
        return 'Swipe gestures';
      default:
        return 'Unknown';
    }
  }

  bool get isXiaomiDevice {
    final String maker = deviceManufacturer.value.toLowerCase();
    return maker.contains('xiaomi') ||
        maker.contains('redmi') ||
        maker.contains('poco');
  }

  bool get isSamsungDevice =>
      deviceManufacturer.value.toLowerCase().contains('samsung');

  /// Where the navigation picker lives on this OEM skin.
  String get navigationSettingsPath {
    if (isXiaomiDevice) return 'Settings > Home screen > System navigation';
    if (isSamsungDevice) return 'Settings > Display > Navigation bar';
    return 'Settings > System > Gestures > System navigation';
  }

  /// Reads the current OS navigation mode. Read-only for normal apps; Android
  /// only allows system/privileged apps to change it.
  Future<void> refreshNavigationMode() async {
    try {
      final int mode =
          await platform.invokeMethod<int>('getNavigationMode') ?? -1;
      navigationMode.value = mode;

      final String maker =
          await platform.invokeMethod<String>('getDeviceManufacturer') ?? '';
      deviceManufacturer.value = maker;
    } catch (e) {
      log("Error reading navigation mode: $e");
      navigationMode.value = -1;
    }
  }

  /// Opens the system screen where the user chooses gesture vs button
  /// navigation. Zen cannot change this value itself.
  Future<void> openNavigationSettings() async {
    try {
      final bool opened =
          await platform.invokeMethod<bool>('openNavigationSettings') ?? false;
      if (!opened) {
        _showNavigationManualInstructions();
      }
    } on PlatformException catch (e) {
      log("Failed to open navigation settings: ${e.message}");
      _showNavigationManualInstructions();
    }
  }

  /// Explains the navigation-style limitation and offers the settings shortcut.
  Future<void> showNavigationStyleHelp() async {
    if (Get.isDialogOpen == true) return;

    await refreshNavigationMode();

    final String current = navigationModeLabel;
    final String vendorNote = isXiaomiDevice
        ? '\n\nXiaomi/HyperOS blocks gesture navigation for third-party launchers. '
            'If the swipe option is missing or jumps back to buttons, that is a '
            'Xiaomi restriction, not a Zen setting.'
        : '';

    final String? choice = await Get.dialog<String>(
      AlertDialog(
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.zero,
        ),
        title: const Text(
          'NAVIGATION STYLE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        content: Text(
          'Current: $current\n\n'
          'Android controls the navigation style. Zen can open the system setting, '
          'but it cannot change the style for you. Zen runs full-screen, so the '
          'system bar may be hidden on the home screen; the style still applies '
          'across Android.$vendorNote',
          style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('CLOSE'),
          ),
          TextButton(
            onPressed: () => Get.back(result: 'open'),
            child: const Text('OPEN SETTINGS'),
          ),
        ],
      ),
      barrierDismissible: true,
    );

    if (choice == 'open') {
      await openNavigationSettings();
    }
  }

  /// Shows the exact manual path when no navigation-settings intent resolves.
  void _showNavigationManualInstructions() {
    if (Get.isDialogOpen == true) return;

    Get.dialog<void>(
      AlertDialog(
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.zero,
        ),
        title: const Text(
          'OPEN NAVIGATION SETTINGS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        content: Text(
          'Open $navigationSettingsPath, then choose Swipe gestures or Buttons.\n\n'
          'Some devices use Settings > Display > Navigation bar instead.',
          style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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

    // Nothing to prompt for if this APK has no HOME activity registered.
    if (!await isHomeActivityRegistered()) return;

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
      // Go straight to the system prompt; requesting the full instructions
      // dialog here would stack two dialogs back to back.
      await _requestHomeRolePrompt();
    }
  }

  /// Shows the exact manual path when no Settings intent can be resolved.
  void _showHomeSettingsManualInstructions() {
    if (Get.isDialogOpen == true) return;

    Get.dialog<void>(
      AlertDialog(
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.zero,
        ),
        title: const Text(
          'OPEN SETTINGS MANUALLY',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        content: Text(
          'Open Android Settings > Apps > Default apps > Home app, then choose Zen Alpha.\n\n'
          'On some devices the path is Settings > Home or Settings > Apps > Zen Alpha > Open by default.',
          style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Explains that this build cannot be selected as HOME at all.
  Future<void> _showHomeRegistrationError() async {
    if (Get.isDialogOpen == true) return;

    await Get.dialog<void>(
      AlertDialog(
        backgroundColor: Colors.black,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.zero,
        ),
        title: const Text(
          'HOME ROLE UNAVAILABLE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        content: Text(
          'This installed copy of Zen does not declare a Home activity, so Android cannot list it under Home app settings.\n\n'
          'Reinstall the latest Zen Alpha APK ($appPackageName) and try again.',
          style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Small monochrome snackbar used by the HOME setup flow.
  void _showHomeSnack(
    String title,
    String message, {
    VoidCallback? onTap,
  }) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.black,
      colorText: Colors.white,
      borderRadius: 0,
      duration: const Duration(seconds: 8),
      onTap: onTap == null ? null : (_) => onTap(),
    );
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
    final bool wasRunning = await NotificationsListener.isRunning ?? false;
    final bool firstBind = !_notificationBridgeInitialized;

    await NotificationsListener.initialize(callbackHandle: backgroundNotificationHandler);

    if (firstBind) {
      // Register the UI port exactly once per process. Re-creating it on every
      // resume leaked the old ReceivePort and could split events between two
      // live listeners.
      IsolateNameServer.removePortNameMapping("_listener_");
      _uiReceivePort?.close();

      final ReceivePort port = ReceivePort();
      _uiReceivePort = port;
      IsolateNameServer.registerPortWithName(port.sendPort, "_listener_");
      port.listen((rawData) {
        if (rawData is NotificationEvent) {
          _handleIncomingUiNotification(rawData);
        }
      });

      _notificationBridgeInitialized = true;
    }

    // The plugin caches a background Flutter engine for the listener service.
    // If Android created that service before plugin.initialize ran (very common
    // after a reboot or after granting Notification Access), the cached engine
    // has no event callback and silently drops every notification. Restarting
    // the service on the first bind forces a fresh engine with our callback.
    if (firstBind || !wasRunning) {
      log("Bind notification engine with a fresh service context...");
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
    debugPrint('Zen notification UI pipeline: ${event.packageName}');

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
    _persistHiddenApps();
    log("Application structural footprint hidden from matrix: $packageName");
  }

  void revealApplication(String packageName) {
    hiddenAppPackages.remove(packageName);
    hiddenAppPackages.refresh();
    _persistHiddenApps();
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

  /// Launches an app that the user deliberately pinned to the home screen.
  ///
  /// Pinned links skip the five-second interrupter and open immediately, but
  /// daily limits still apply. The interrupter exists to interrupt accidental
  /// or impulsive launches from the app drawer, not a home-screen shortcut the
  /// user created on purpose.
  Future<void> launchPinnedApp(String packageName) async {
    if (appTimersActive.value) {
      await refreshUsageStats();
      if (isAppOverLimit(packageName)) {
        log("Daily limit reached for pinned app $packageName. Blocking launch.");
        _showLimitReached(packageName);
        return;
      }
    }

    log("Pinned home launch for $packageName. Skipping interrupter.");
    await _directNativeLaunch(packageName);
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
        _persistPinnedApps();
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
      _persistPinnedApps();
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
    _screenTimeDay = DateTime.now();
    _startDisplayTicker();
    unawaited(refreshScreenTime());
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
        if (now.year != _screenTimeDay.year ||
            now.month != _screenTimeDay.month ||
            now.day != _screenTimeDay.day) {
          // Midnight rollover while the launcher is awake.
          _screenTimeDay = now;
          _accumulatedSecondsToday = 0;
          _updateDisplayString();
          unawaited(refreshScreenTime());
        }
      }
    });
  }

  /// Pulls real screen-on time for today from Android usage events.
  ///
  /// Without Usage Access the native call returns null and the local ticker
  /// remains the fallback.
  Future<void> refreshScreenTime() async {
    try {
      final dynamic millis = await platform.invokeMethod('getTodayScreenTime');
      if (millis is num && millis >= 0) {
        _accumulatedSecondsToday = (millis / 1000).floor();
        _screenTimeDay = DateTime.now();
        _updateDisplayString();
      }
    } catch (e) {
      log("Could not refresh device screen time: $e");
    }
  }

  void _updateDisplayString() {
    final duration = Duration(seconds: _accumulatedSecondsToday);
    final hours    = duration.inHours.toString().padLeft(2, '0');
    final minutes  = (duration.inMinutes % 60).toString().padLeft(2, '0');
    todayScreenTime.value = "$hours:$minutes";
  }

  Future<bool> authenticateUserSecurely({required String reason}) async {
    try {
      final bool isDeviceSupported = await localAuth.isDeviceSupported();

      if (!isDeviceSupported) {
        _showAuthIssue(
          title: 'NO SCREEN LOCK SET',
          message:
              'Hidden apps need a screen lock. Set a PIN, pattern, password, or fingerprint in Android Settings first.',
        );
        return false;
      }

      final List<BiometricType> enrolled =
          await localAuth.getAvailableBiometrics();
      if (enrolled.isEmpty) {
        final bool useScreenLock = await _confirmDeviceCredentialFallback();
        if (!useScreenLock) return false;
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
    } on PlatformException catch (error) {
      log("Authentication platform exception: ${error.code} - ${error.message}");
      switch (error.code) {
        case 'NotAvailable':
        case 'NotEnrolled':
          _showAuthIssue(
            title: 'FINGERPRINT NOT AVAILABLE',
            message:
                'No fingerprint is enrolled on this device. Add one in Android Settings, then try again.',
          );
          break;
        case 'PasscodeNotSet':
          _showAuthIssue(
            title: 'NO SCREEN LOCK SET',
            message:
                'Set a PIN, pattern, password, or fingerprint in Android Settings before using hidden apps.',
          );
          break;
        case 'LockedOut':
        case 'PermanentlyLockedOut':
          _showAuthIssue(
            title: 'FINGERPRINT LOCKED',
            message:
                'Too many failed attempts. Unlock your phone with your PIN, then try again.',
          );
          break;
        default:
          _showAuthIssue(
            title: 'AUTHENTICATION UNAVAILABLE',
            message:
                'Zen could not start fingerprint or screen-lock authentication on this device.',
          );
      }
      return false;
    } catch (error) {
      log("Authentication exception intercepted: $error");
      _showAuthIssue(
        title: 'AUTHENTICATION ERROR',
        message: 'Zen could not verify your identity. Please try again.',
      );
      return false;
    }
  }

  /// Offered when the device has a screen lock but no enrolled fingerprint.
  Future<bool> _confirmDeviceCredentialFallback() async {
    final bool? useScreenLock = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        shape: const LinearBorder(),
        title: const Text(
          'FINGERPRINT NOT AVAILABLE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        content: Text(
          'No fingerprint is enrolled on this device. Add one in Android Settings, '
          'or continue with your screen lock PIN.',
          style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text(
              'CANCEL',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text(
              'USE PIN',
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

    return useScreenLock ?? false;
  }

  /// Shows a blocking, readable error instead of failing silently.
  void _showAuthIssue({required String title, required String message}) {
    if (Get.isDialogOpen == true) return;

    Get.dialog(
      AlertDialog(
        backgroundColor: const Color(0xFF0F0F0F),
        shape: const LinearBorder(),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        content: Text(
          message,
          style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text(
              'OK',
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
  debugPrint('Zen notification background event: $currentPackage');

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