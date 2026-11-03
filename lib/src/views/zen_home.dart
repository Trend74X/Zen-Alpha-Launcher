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

              // --- HOME ROLE BANNER ---
              // Android cannot silently become the default launcher; the user
              // must choose Zen once. Keep this visible until they do.
              Obx(() {
                if (controller.isDefaultLauncher.value) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: GestureDetector(
                    onTap: () => controller.requestDefaultLauncher(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.home_outlined, color: Colors.white, size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'MAKE ZEN YOUR HOME',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Tap to stop Android returning to the stock launcher.',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward, color: Colors.white, size: 14),
                        ],
                      ),
                    ),
                  ),
                );
              }),

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