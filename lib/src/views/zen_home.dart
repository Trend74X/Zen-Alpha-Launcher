import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zen_launcher/src/controller/app_controller.dart';
import 'package:zen_launcher/src/controller/helpers/intent_helpers.dart';
import 'package:zen_launcher/src/widget/dot_matrix.dart';
import 'package:zen_launcher/src/widget/zen_clock.dart'; 

class ZenHome extends StatelessWidget {
  const ZenHome({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = Get.find<AppController>();

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: DotMatrixPainter(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40.0),
              const Center(child: ZenClock()), 
              const SizedBox(height: 50.0),
              
              // --- PERMANENT COMPULSORY LINKS ---
              _buildLargeLink('PHONE', launchPhone),
              _buildLargeLink('MESSAGES', openMessagesList),
              
              // --- DYNAMICALLY IMPORTED LINKS VIA INDEX PAGE ---
              Obx(() {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: controller.pinnedHomeApps.map((packageName) {
                    // Find the app details from our master listing array using the package name identifier
                    final appMatch = controller.installedApps.firstWhereOrNull(
                      (element) => element.packageName == packageName,
                    );

                    // If the app was uninstalled or can't be found, render nothing safely
                    if (appMatch == null) return const SizedBox.shrink();

                    return _buildLargeLink(
                      appMatch.name.toUpperCase(), // Displays raw app label uppercase matching design rules
                      () => controller.launchApplicationContainer(appMatch.packageName)
                    );
                  }).toList(),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLargeLink(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis, // Prevents layout snapping if an app name is very long
        style: const TextStyle(
          color: Colors.white,
          fontSize: 38.0, 
          fontWeight: FontWeight.w600,
          letterSpacing: 4.0,
        ),
      ),
    );
  }
}