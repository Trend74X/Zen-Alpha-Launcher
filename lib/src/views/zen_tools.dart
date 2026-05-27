import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zen_launcher/src/controller/app_controller.dart';

class ZenToolsPage extends StatelessWidget {
  const ZenToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = Get.find<AppController>();

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0), 
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 50.0), 
                
                // Header Design Block
                const Text(
                  'ZEN\nCONTROL',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    height: 0.9,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ENVIRONMENTAL ARCHITECTURE',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 60),
            
                // Reactive Toggles Block
                Obx(() => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggleSetting(
                      'Do Not Disturb', 
                      'Silence all incoming calls and message alerts.', 
                      controller.isDndActive.value, 
                      (newValue) => controller.toggleDoNotDisturb(context, newValue),
                    ),
                    
                    _buildToggleSetting(
                      'App Timers', 
                      'Hard-lock distracting applications.', 
                      controller.appTimersActive.value, 
                      (newValue) => controller.toggleAppTimers(newValue),
                    ),
                  ],
                )),
            
                const SizedBox(height: 20),

                const Divider(color: Colors.white, thickness: 1),
                const SizedBox(height: 20),
                
                // Obx handles the reactive timer string changes smoothly
                Obx(() => Row(
                  children: [
                    _buildStat('DEVICE ACTIVE TODAY', controller.todayScreenTime.value),
                  ],
                )),
        
                const SizedBox(height: 120.0)
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleSetting(String title, String subtitle, bool currentValue, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ),
          
          GestureDetector(
            onTap: () => onChanged(!currentValue), 
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 24,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: currentValue ? Colors.white : Colors.grey[700]!, 
                  width: 2,
                ),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: currentValue ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 14,
                  height: 14,
                  color: currentValue ? Colors.white : Colors.grey[800],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Colors.grey, width: 1))
      ),
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}