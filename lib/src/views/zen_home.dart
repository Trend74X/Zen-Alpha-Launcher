import 'package:flutter/material.dart';
import 'package:zen_launcher/src/controller/helpers/intent_helpers.dart';
import 'package:zen_launcher/src/widget/dot_matrix.dart';
import 'package:zen_launcher/src/widget/zen_clock.dart'; 

class ZenHome extends StatelessWidget {
  const ZenHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background dots matrix preserved completely
        Positioned.fill(
          child: CustomPaint(
            painter: DotMatrixPainter(),
          ),
        ),
        // App List Canvas layer
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40.0),
              Center(child: const ZenClock()), // Interactive clock hooks are live here now!
              const SizedBox(height: 50.0),
              _buildLargeLink('PHONE', launchPhone),
              _buildLargeLink('MESSAGES', openMessagesList),
              _buildLargeLink('CAMERA', launchCamera),
              // _buildLargeLink('CALENDAR', openCalendar),
              _buildLargeLink('NOTES', openNotes),
              _buildLargeLink('MAPS', openMaps),
              // _buildLargeLink('CALCULATOR', openCalculator),
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
            fontSize: 52.0, // Your signature large font scale
            fontWeight: FontWeight.w600,
            letterSpacing: 4.0,
          ),
        ),
      ),
    );
  }
}