import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zen_launcher/src/controller/app_controller.dart';
import 'package:zen_launcher/src/views/zen_home.dart';
import 'package:zen_launcher/src/views/zen_index.dart';
import 'package:zen_launcher/src/views/zen_tools.dart';
import 'package:zen_launcher/src/views/zen_vault.dart';

class BottomNav extends StatefulWidget {
  const BottomNav({super.key});

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> {
  final AppController controller = Get.find<AppController>();
  int _selectedIndex = 0; // Default to "ZEN"

  final List<Widget> pages = [
    const ZenHome(),
    const ZenVault(),
    const ZenToolsPage(),
    const ZenIndex()
  ];

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // We wrap the entire PopScope layout inside an Obx worker.
      // This forces the Stack to instantly rebuild the moment controller.isInterrupterActive changes!
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          
          if (controller.isInterrupterActive.value) {
            controller.cancelInterrupter();
          }
        },
        child: GestureDetector(
          onDoubleTap: () {
            if (controller.isDoubleTapLockEnabled.value) {
              log("Double tap captured. Routing target intent to Android OS hardware modules.");
              controller.lockDeviceScreen();
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF0A0A0A),
            extendBodyBehindAppBar: true,
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                // 1. Core Page Layers
                Positioned.fill(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: pages,
                  ),
                ),
                
                // 2. Persistent Navigation Content Elements
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.only(top: 20, bottom: 30),
                        decoration: const BoxDecoration(
                          color: Color(0xFF111111),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildNavItem(0, Icons.nightlight_outlined, "ZEN"),
                            _buildNavItem(1, Icons.system_update_alt_rounded, "VAULT"),
                            _buildNavItem(2, Icons.crop_square_rounded, "TOOLS"),
                            _buildNavItem(3, Icons.search, "INDEX"),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. THE GLOBAL INTERRUPTER GUARD VECTOR OVERLAY
                if (controller.isInterrupterActive.value)
                  const Positioned.fill(
                    child: TheInterrupterView(),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isActive = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : Colors.grey[600],
              size: 26,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey[600],
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.transparent,
                shape: BoxShape.rectangle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// INTERRUPTER VIEW LAYER
// ====================================================================
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
    _holdAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2), 
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
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F), 
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                      Obx(() => Text(
                        '[${controller.interrupterRemainingSeconds.value}S REMAINING]',
                        style: TextStyle(color: Colors.grey[500], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                      )),
                      const SizedBox(height: 24),
                      
                      Obx(() => Row(
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
                      ))
                    ],
                  ),
                ),
              ),

              const Spacer(),

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

              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) {
                  log("Intentional pressure detected. Starting override and PAUSING countdown.");
                  _holdAnimationController.forward();
                  
                  // 1. PAUSE THE COUNTDOWN TIMER: Stop the strict ticking engine temporarily
                  controller.interrupterTimer?.cancel();
                },
                onTapUp: (_) {
                  log("Pressure lifted prematurely. Reverting focus lock state and RESUMING countdown.");
                  _holdAnimationController.reverse();
                  
                  // 2. RESUME THE COUNTDOWN TIMER: Pick up exactly where the countdown left off
                  controller.resumeInterrupterCountdown();
                },
                onTapCancel: () {
                  _holdAnimationController.reverse();
                  
                  // 3. SAFETY CATCH: If the gesture cancels, resume the countdown tracker
                  controller.resumeInterrupterCountdown();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  color: Colors.transparent,
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
  }
}