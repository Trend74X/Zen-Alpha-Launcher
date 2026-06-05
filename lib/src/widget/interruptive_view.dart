import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controller/app_controller.dart'; // Verify path alignment

class TheInterrupterView extends StatefulWidget {
  const TheInterrupterView({super.key});

  @override
  State<TheInterrupterView> createState() => _TheInterrupterViewState();
}

class _TheInterrupterViewState extends State<TheInterrupterView> with SingleTickerProviderStateMixin {
  final AppController controller = Get.find<AppController>();
  late AnimationController _holdAnimationController;

  @override
  void initState() {
    super.initState();
    // Controls the visual time required to hold down the confirmation sequence
    _holdAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2), // Must hold for 2 seconds to enter
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          controller.completeOverride();
        }
      });
  }

  @override
  void dispose() {
    _holdAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.isInterrupterActive.value) return const SizedBox.shrink();

      return Scaffold(
        backgroundColor: const Color(0xFF0F0F0F), // Ultra deep slate-black canvas
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- HEADER ACTIONS TRACK BAR ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'SOBRIETY',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                    Text(
                      'SYSTEM.HALT',
                      style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
                
                const Spacer(),

                // --- CENTER CONSCIOUSNESS CIRCLE TARGET ---
                Center(
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Is this intentional?',
                          style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '[${controller.interrupterRemainingSeconds.value}S REMAINING]',
                          style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                        const SizedBox(height: 24),
                        
                        // Progress Dashes Vector Generator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (index) {
                            bool isActive = index < controller.interrupterRemainingSeconds.value;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 24,
                              height: 2,
                              color: isActive ? Colors.white : Colors.white12,
                            );
                          }),
                        )
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // --- DISMISS REJECTION BUTTON ---
                ElevatedButton(
                  onPressed: () => controller.cancelInterrupter(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                  child: const Text(
                    'GO BACK',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                  ),
                ),

                const SizedBox(height: 32),

                // Locate this section at the bottom of your TheInterrupterView.dart file:
                GestureDetector(
                  behavior: HitTestBehavior.opaque, // Makes the entire empty row region highly touch-receptive
                  onTapDown: (_) {
                    log("Intentional pressure detected. Starting override system tracking...");
                    _holdAnimationController.forward();
                  },
                  onTapUp: (_) {
                    log("Pressure lifted prematurely. Reverting focus lock state.");
                    _holdAnimationController.reverse();
                  },
                  onTapCancel: () {
                    _holdAnimationController.reverse();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    color: Colors.transparent, // Ensures the entire box is clickable, not just the text lines
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _holdAnimationController,
                          builder: (context, child) {
                            return LinearProgressIndicator(
                              value: _holdAnimationController.value,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 2,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'HOLD BUTTON TO OVERRIDE',
                              style: TextStyle(color: Colors.grey[600], fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                            ),
                            const SizedBox(width: 8),
                            Container(width: 6, height: 6, color: Colors.grey[700]),
                            const SizedBox(width: 8),
                            
                            // Replaced static text with a live, clean clock readout matching your style
                            Text(
                              "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')} ${DateTime.now().hour >= 12 ? 'PM' : 'AM'}",
                              style: TextStyle(color: Colors.grey[600], fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      );
    });
  }
}