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
                // --- VAULT HEADER TITLE & CLEAR ACTION ROW ---
                Padding(
                  padding: const EdgeInsets.only(top: 28.0, left: 16.0, right: 16.0, bottom: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: const Text(
                          'Notification Vault',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 44, // Slightly adjusted size to sit elegantly next to the button
                            fontWeight: FontWeight.w900,
                            height: 0.9,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      
                      // --- MINIMALIST ZEN CLEAR BUTTON ---
                      TextButton(
                        onPressed: () {
                          // Triggers the master clear workflow we already have in AppController
                          controller.clearAllNotifications();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'CLEAR ALL',
                          style: TextStyle(
                            color: Color(0xFF595959), // Muted dark grey so it doesn't grab attention
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
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
                              color: const Color(0xFF1A1A1A), // Fixed null color crash
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
                            separatorBuilder: (context, childIndex) => const Divider(
                              color: Color(0xFF1A1A1A), // Fixed null color crash
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
                                  splashColor: const Color(0xFF1A1A1A), // Fixed null color crash
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Minimalist visual thread guide
                                        Container(
                                          width: 2,
                                          height: 38,
                                          color: const Color(0xFF262626), // Fixed null color crash
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
                                                    style: const TextStyle(
                                                      color: Color(0xFF595959), // Fixed null color crash
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

                const SizedBox(height: 80)
              ],
            );
          }),
        ),
      ),
    );
  }

  String _formatNotificationTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    return DateFormat.jm().format(dateTime); 
  }
}