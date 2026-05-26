import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // Add this to pubspec.yaml
// Ensure this path is correct and the class DotMatrixPainter exists there!
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
      type: 'vnd.android-dir/mms-sms', // This tells Android to open the SMS directory
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

  @override
  Widget build(BuildContext context) {
    return Stack(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 50.0),
              Center(child: ZenClock()),
              SizedBox(height: 50.0),
              _buildLargeLink('PHONE', _launchPhone),
              _buildLargeLink('CONTACTS', openContactsList),
              _buildLargeLink('MESSAGES', openMessagesList),
              _buildLargeLink('CAMERA', _launchCamera),
            ],
          ),
        ),
      ],
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
            fontSize: 52.0, // Large minimalist font
            fontWeight: FontWeight.w600,
            letterSpacing: 4.0,
          ),
        ),
      ),
    );
  }
}