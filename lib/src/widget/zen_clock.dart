import 'dart:async';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ZenClock extends StatefulWidget {
  const ZenClock({super.key});

  @override
  State<ZenClock> createState() => _ZenClockState();
}

class _ZenClockState extends State<ZenClock> {
  late Timer _timer;
  late DateTime _currentDateTime;

  @override
  void initState() {
    super.initState();
    _currentDateTime = DateTime.now();
    // Update the clock state dynamically every second
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) => _getTime());
  }

  @override
  void dispose() {
    _timer.cancel(); // Always cancel timers to prevent memory leaks
    super.dispose();
  }

  void _getTime() {
    if (mounted) {
      setState(() {
        _currentDateTime = DateTime.now();
      });
    }
  }

  // Router Gateway: Opens standard Alarms matrix securely across different Android vendors
  void _openClockApp() {
    const intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
    );
    intent.launch().catchError((e) {
      // Fallback cluster sequence if standard SET_ALARM action is locked by the OEM
      final commonClocks = [
        'com.google.android.deskclock',
        'com.sec.android.app.clockpackage',
        'com.android.deskclock',
        'com.miui.clock',
      ];
      for (var package in commonClocks) {
        try {
          AndroidIntent(
            action: 'android.intent.action.MAIN',
            category: 'android.intent.category.LAUNCHER',
            package: package,
          ).launch();
          return;
        } catch (_) {}
      }
    });
  }

  // Router Gateway: Opens native system Calendar directly
  void _openCalendarApp() {
    const intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      category: 'android.intent.category.APP_CALENDAR',
    );
    intent.launch();
  }

  @override
  Widget build(BuildContext context) {
    // Generate layout string tokens based on your specific format guidelines
    final String dateDisplayString = DateFormat('E d, MMM').format(_currentDateTime);
    final String timeDisplayString = DateFormat('HH:mm').format(_currentDateTime);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- DATE STRING -> ROUTES TO CALENDAR ---
        GestureDetector(
          onTap: _openCalendarApp,
          behavior: HitTestBehavior.opaque, // Ensures smooth interaction tracking on text surfaces
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
            child: Text(
              dateDisplayString,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 18,
                fontWeight: FontWeight.w500,
                letterSpacing: 2,
              ),
            ),
          ),
        ),

        // --- TIME STRING -> ROUTES TO CLOCK/ALARMS ---
        GestureDetector(
          onTap: _openClockApp,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              timeDisplayString,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 100, // Large "Zen" style completely preserved
                fontWeight: FontWeight.w500, 
                letterSpacing: -5,
                height: 1.1, // Keeps the vertical composition layout completely uniform
              ),
            ),
          ),
        ),
      ],
    );
  }
}