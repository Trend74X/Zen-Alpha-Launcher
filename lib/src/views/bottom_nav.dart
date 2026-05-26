import 'package:flutter/material.dart';
import 'package:zen_launcher/src/views/zen_home.dart';
import 'package:zen_launcher/src/views/zen_tools.dart';
import 'package:zen_launcher/src/views/zen_vault.dart';

class BottomNav extends StatefulWidget {
  const BottomNav({super.key});

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> {
  int _selectedIndex = 0; // Default to "ZEN"

  // 1. Define your pages here
  final List<Widget> pages = [
    ZenHome(),
    ZenVault(),
    ZenToolsPage(),
    const Center(child: Text("INDEX PAGE", style: TextStyle(color: Colors.white))),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A), // Near black background
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. The Dot Matrix Background
          Positioned.fill(
            child: IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),
          ),
          
          // 2. Main Content
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The "Reset System State" Button
                // Padding(
                //   padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                //   child: OutlinedButton(
                //     onPressed: () {},
                //     style: OutlinedButton.styleFrom(
                //       side: const BorderSide(color: Color(0xFF3D2B2B), width: 1.5),
                //       minimumSize: const Size(double.infinity, 56),
                //       shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                //     ),
                //     child: const Text(
                //       "RESET SYSTEM STATE",
                //       style: TextStyle(
                //         color: Color(0xFFD48A8A),
                //         letterSpacing: 2.0,
                //         fontSize: 13,
                //         fontWeight: FontWeight.w600,
                //       ),
                //     ),
                //   ),
                // ),

                // The Bottom Navigation Bar
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
        ],
      ),
    );
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
            // The Square Indicator
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

/// Custom Painter to draw the grid of dots
