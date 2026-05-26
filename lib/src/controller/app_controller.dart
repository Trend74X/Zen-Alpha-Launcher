import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:battery_optimization_helper/battery_optimization_helper.dart';
import 'package:do_not_disturb/do_not_disturb.dart'; // Using the proper package API
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:get/get.dart';

class AppController extends GetxController with WidgetsBindingObserver {
  final dndPlugin = DoNotDisturbPlugin();
  static const platform = MethodChannel('com.zen_launcher/battery');

  var isDndEnabled = false.obs;
  var isListenerRunning = false.obs;
  var collectedNotifications = <NotificationEvent>[].obs;

  StreamSubscription? _notificationSubscription;

  @override
  Future<void> onInit() async {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    await startZenModeWorkflow();
  } 

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("User returned to launcher. Re-checking remaining workflows...");
      startZenModeWorkflow();
    }
  }

  Future<void> startZenModeWorkflow() async {
    // FIX 1: Parentheses added around await for accurate evaluation
    bool hasListenerPermission = (await NotificationsListener.hasPermission) ?? false;
    if (!hasListenerPermission) {
      print('Notification Listener Permission missing. Prompting user...');
      await NotificationsListener.openPermissionSettings();
      return; 
    }

    bool hasDndPermission = await dndPlugin.isNotificationPolicyAccessGranted();
    if (!hasDndPermission) {
      print('DND Access Permission missing. Prompting user...');
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
        print("Launcher is being optimized by battery saver. Prompting user...");
        await BatteryOptimizationHelper.openBatteryOptimizationSettings();
      } else {
        print("Launcher is already white-listed from battery saving.");
      }
    } on PlatformException catch (e) {
      print("Failed to check battery status: ${e.message}");
      await BatteryOptimizationHelper.openBatteryOptimizationSettings();
    }
  }

  Future<void> enableDNDMode() async {
    bool active = await dndPlugin.isDndEnabled();
    if (!active) {
      print('Enabling DND Mode...');
      await dndPlugin.setInterruptionFilter(InterruptionFilter.none);
      isDndEnabled.value = true;
    } else {
      print('DND Mode is already active.');
      isDndEnabled.value = true;
    }
  }

  Future<void> initializeNotificationCollector() async {
    await NotificationsListener.initialize(callbackHandle: backgroundNotificationHandler);
    isListenerRunning.value = true;

    IsolateNameServer.removePortNameMapping("zen_notification_port");

    if (_notificationSubscription != null) {
      await _notificationSubscription!.cancel();
      _notificationSubscription = null;
    }

    final rawPort = NotificationsListener.receivePort;
    if (rawPort != null) {
      IsolateNameServer.registerPortWithName(rawPort.sendPort, "zen_notification_port");

      _notificationSubscription = rawPort.listen((rawData) {
        if (rawData is NotificationEvent) {
          _handleIncomingUiNotification(rawData);
        }
      });
      print("Notification communication bridge successfully bound.");
    } else {
      print("Error: ReceivePort from NotificationsListener is completely null.");
    }
  }

  void _handleIncomingUiNotification(NotificationEvent event) {
    print('Notification intercepted from: ${event.packageName}');
    if (event.title == null && event.text == null) return;

    bool alreadyExists = collectedNotifications.any((n) => 
      n.packageName == event.packageName && 
      n.title == event.title && 
      n.text == event.text
    );

    if (!alreadyExists) {
      collectedNotifications.add(event); 
      collectedNotifications.refresh(); // FIX 2: Ensure UI is notified
    }
  }
}

// Global background runner function required by Flutter isolates
// Global background runner function required by Flutter isolates
void backgroundNotificationHandler(NotificationEvent event) {
  print("Background Isolate caught notification: ${event.title}");
  
  // Find the bridge communication port we registered in our main application layer
  final SendPort? sendPort = IsolateNameServer.lookupPortByName("zen_notification_port");
  
  if (sendPort != null) {
    // Send the notification event across the thread divide straight into your controller list
    sendPort.send(event);
  } else {
    print("Communication channel 'zen_notification_port' wasn't found yet.");
  }
}