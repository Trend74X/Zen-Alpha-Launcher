import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zen_launcher/src/widget/dot_matrix.dart';
import 'package:zen_launcher/src/widget/zen_clock.dart'; 

class ZenHome extends StatelessWidget {
  const ZenHome({super.key});

  // Helper to launch Phone
  Future<void> _launchPhone() async {
    final Uri url = Uri(scheme: 'tel');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void openContactsList() {
    const intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      category: 'android.intent.category.APP_CONTACTS',
    );
    intent.launch();
  }

  void openMessagesList() {
    const intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      type: 'vnd.android-dir/mms-sms',
    );
    intent.launch();
  }

  // Helper to launch Camera
  void _launchCamera() {
    const intent = AndroidIntent(
      action: 'android.media.action.IMAGE_CAPTURE',
    );
    intent.launch();
  }

  // Helper to launch Calendar via official system category
  void openCalendar() {
    const intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      category: 'android.intent.category.APP_CALENDAR',
    );
    intent.launch();
  }

  // Helper to launch Notes safely across different Android OEMs
  void openNotes() {
    // 1. Try the official Android implicit action for creating a note
    final intent = const AndroidIntent(
      action: 'android.intent.action.CREATE_NOTE',
    );
    
    intent.launch().catchError((e) {
      // 2. Direct Vendor Fallbacks if the device doesn't resolve the implicit action cleanly
      final commonNotesApps = [
        'com.google.android.apps.notes', // Google Keep
        'com.samsung.android.app.notes', // Samsung Notes
        'com.miui.notes',                // Xiaomi Notes
        'com.oneplus.note',              // OnePlus Notes
        'com.apple.news',                // Alternative matches
      ];

      for (var package in commonNotesApps) {
        try {
          final fallbackIntent = AndroidIntent(
            action: 'android.intent.action.MAIN',
            category: 'android.intent.category.LAUNCHER',
            package: package,
          );
          fallbackIntent.launch();
          return; // Stop processing once one successfully triggers
        } catch (_) {}
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Ensures the background fits under the stack cleanly
      body: Stack(
        children: [
          // Background dots
          Positioned.fill(
            child: CustomPaint(
              painter: DotMatrixPainter(),
            ),
          ),
          // App List
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView( // Keeps the giant text labels scrollable on smaller displays
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 50.0),
                  Center(child: const ZenClock()),
                  const SizedBox(height: 50.0),
                  _buildLargeLink('PHONE', _launchPhone),
                  // _buildLargeLink('CONTACTS', openContactsList),
                  _buildLargeLink('MESSAGES', openMessagesList),
                  _buildLargeLink('CALENDAR', openCalendar),
                  _buildLargeLink('NOTES', openNotes),
                  _buildLargeLink('CAMERA', _launchCamera),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeLink(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 52.0, // Large minimalist font preserved
            fontWeight: FontWeight.w600,
            letterSpacing: 4.0,
          ),
        ),
      ),
    );
  }
}