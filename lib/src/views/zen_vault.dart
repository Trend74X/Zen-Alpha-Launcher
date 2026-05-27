import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:zen_launcher/src/controller/app_controller.dart';

class ZenVault extends StatelessWidget {
  const ZenVault({super.key});

  @override
  Widget build(BuildContext context) {
    // Locate or instantiate our state controller safely
    final AppController controller = Get.put(AppController());

    // CRITICAL FIX 1: Wrap the entire layout in a Scaffold with SafeArea 
    // to cleanly handle status bars and bottom navigation bars globally.
    return Scaffold(
      backgroundColor: Colors.black, // Keeps your minimalist look seamless
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Obx(() {
            // FIX 2: Consolidated Obx loop. If the core notification list is empty, 
            // display the serene center placeholder text instantly.
            if (controller.collectedNotifications.isEmpty) {
              return const Center(
                child: Text(
                  'VAULT EMPTY\nNO DISTRACTIONS DETECTED',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey, 
                    fontSize: 12, 
                    letterSpacing: 2,
                    height: 1.5,
                  ),
                ),
              );
            }

            final groupedMap = controller.groupedNotifications;
            final packageNames = groupedMap.keys.toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- VAULT HEADER TITLE ---
                Padding(
                  padding: const EdgeInsets.only(top: 28.0, left: 16.0, bottom: 24.0),
                  child: const Text(
                    'Notification Vault',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      height: 0.9,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                
                // --- GROUPED NOTIFICATION ENGINE LIST ---
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(left: 16, right: 8, bottom: 32, top: 12),
                    itemCount: packageNames.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 32), 
                    itemBuilder: (context, parentIndex) {
                      final packageName = packageNames[parentIndex];
                      final notificationsForApp = groupedMap[packageName] ?? [];
                      final appDisplayName = controller.getAppNameOf(packageName);
                  
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- APP HEADER BUBBLE ---
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              appDisplayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                  
                          // --- INNER NOTIFICATION CLUSTER ---
                          ListView.separated(
                            shrinkWrap: true, 
                            physics: const NeverScrollableScrollPhysics(), 
                            itemCount: notificationsForApp.length,
                            separatorBuilder: (context, childIndex) => Divider(
                              color: Colors.grey[900], 
                              height: 16,
                            ),
                            itemBuilder: (context, childIndex) {
                              final item = notificationsForApp[childIndex];

                              return Dismissible(
                                key: Key('dismiss_${item.packageName}_${item.createAt}_${item.hashCode}'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  color: Colors.red[900],
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 16.0),
                                  child: const Icon(Icons.delete_outline, color: Colors.white, size: 16),
                                ),
                                onDismissed: (direction) {
                                  controller.collectedNotifications.remove(item);
                                },
                                child: InkWell(
                                  onTap: () => controller.openNotificationTargetApp(item),
                                  splashColor: Colors.grey[900],
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Minimalist visual thread guide
                                        Container(
                                          width: 2,
                                          height: 38,
                                          color: Colors.grey[800],
                                          margin: const EdgeInsets.only(right: 12, top: 2),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // --- TITLE & TIME ROW ---
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      item.title ?? 'Notification',
                                                      style: const TextStyle(
                                                        color: Colors.white, 
                                                        fontSize: 15, 
                                                        fontWeight: FontWeight.w400
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  // SUBTLE TIMESTAMP DISPLAY
                                                  Text(
                                                    _formatNotificationTime(item.createAt),
                                                    style: TextStyle(
                                                      color: Colors.grey[700], // Muted colors keep the look clean
                                                      fontSize: 11, 
                                                      fontWeight: FontWeight.w300
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              // --- MESSAGE BODY ---
                                              Text(
                                                item.text ?? '',
                                                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),

                SizedBox(height: 80)
              ],
            );
          }),
        ),
      ),
    );
  }

  String _formatNotificationTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    // Formats time as "3:45 PM" or "14:20" based on system settings
    return DateFormat.jm().format(dateTime); 
  }

}