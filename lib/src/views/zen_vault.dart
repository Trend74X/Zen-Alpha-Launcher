import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zen_launcher/src/controller/app_controller.dart';

class ZenVault extends StatelessWidget {
  const ZenVault({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = Get.put(AppController());

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Obx(() {
        if (controller.collectedNotifications.isEmpty) {
          return const Center(
            child: Text(
              'VAULT EMPTY\nNO DISTRACTIONS DETECTED',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12, letterSpacing: 2),
            ),
          );
        }
      
        return ListView.builder(
          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 0),
          itemCount: controller.collectedNotifications.length,
          itemBuilder: (context, index) {
            final item = controller.collectedNotifications[index];
            final appName = item.packageName?.split('.').last.toUpperCase() ?? 'APP';
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appName, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(item.title ?? 'No Title', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w400)),
                  Text(item.text ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}