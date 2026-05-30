import 'dart:developer';

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

    return Scaffold(
      backgroundColor: Colors.black, // Keeps your minimalist look seamless
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Obx(() {
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
                      const Expanded(
                        child: Text(
                          'Notification Vault',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 44, 
                            fontWeight: FontWeight.w900,
                            height: 0.9,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      
                      // --- MINIMALIST ZEN CLEAR BUTTON ---
                      TextButton(
                        onPressed: () {
                          controller.clearAllNotifications();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'CLEAR ALL',
                          style: TextStyle(
                            color: Color(0xFF595959), 
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
                    separatorBuilder: (context, index) => const SizedBox(height: 16), 
                    itemBuilder: (context, parentIndex) {
                      final packageName = packageNames[parentIndex];
                      final notificationsForApp = groupedMap[packageName] ?? [];
                      final appDisplayName = controller.getAppNameOf(packageName);
                  
                      return _CollapsibleAppCluster(
                        packageName: packageName,
                        appDisplayName: appDisplayName,
                        notifications: notificationsForApp,
                        controller: controller,
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
}

// =================================================================
// LOCAL COMPONENT: COLLAPSIBLE WORKSPACE ARCHITECTURE CLUSTER
// =================================================================
class _CollapsibleAppCluster extends StatefulWidget {
  final String packageName;
  final String appDisplayName;
  final List<dynamic> notifications; // Dynamic backing model matches controller maps
  final AppController controller;

  const _CollapsibleAppCluster({
    required this.packageName,
    required this.appDisplayName,
    required this.notifications,
    required this.controller,
  });

  @override
  State<_CollapsibleAppCluster> createState() => _CollapsibleAppClusterState();
}

class _CollapsibleAppClusterState extends State<_CollapsibleAppCluster> {
  bool _isExpanded = false; // Collapse notifications by app name on default rule

  String _formatNotificationTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    return DateFormat.jm().format(dateTime); 
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // --- APP HEADER ACCORDION BAR ---
        GestureDetector(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                      color: Colors.grey[400],
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.appDisplayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                // Footprint tracking counter layout tag
                Text(
                  '[ ${widget.notifications.length} ]',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        // --- EXPANDED INNER CLUSTER NOTIFICATIONS PANEL ---
        if (_isExpanded) ...[
          const SizedBox(height: 8),
          
          // --- LOCAL APP CLEAR ALL UTILITY TRIGGER BUTTON ---
          Padding(
            padding: const EdgeInsets.only(left: 14.0, top: 4.0, bottom: 4.0),
            child: GestureDetector(
              onTap: () {
                // Instantly remove everything tied to this specific package context selection
                widget.controller.clearNotificationsForPackage(widget.packageName);
                log(widget.packageName);
              },
              child: const Text(
                'CLEAR APP NOTIFICATIONS',
                style: TextStyle(
                  color: Color(0xFF8C8C8C),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  // decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 8),

          ListView.separated(
            shrinkWrap: true, 
            physics: const NeverScrollableScrollPhysics(), 
            itemCount: widget.notifications.length,
            separatorBuilder: (context, childIndex) => const Divider(
              color: Color(0xFF1A1A1A), 
              height: 16,
            ),
            itemBuilder: (context, childIndex) {
              final item = widget.notifications[childIndex];

              return Dismissible(
                // Preserved precise identity mapping rules to protect layout animations
                key: Key('dismiss_${item.packageName}_${item.createAt}_${item.hashCode}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red[900],
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16.0),
                  child: const Icon(Icons.delete_outline, color: Colors.white, size: 16),
                ),
                onDismissed: (direction) {
                  widget.controller.collectedNotifications.remove(item);
                },
                child: InkWell(
                  onTap: () => widget.controller.openNotificationTargetApp(item),
                  splashColor: const Color(0xFF1A1A1A), 
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Minimalist visual thread guide
                        Container(
                          width: 2,
                          height: 38,
                          color: const Color(0xFF262626), 
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
                                  Text(
                                    _formatNotificationTime(item.createAt),
                                    style: const TextStyle(
                                      color: Color(0xFF595959), 
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
          const SizedBox(height: 16), // Extra trailing spacer padding beneath the expanded group array
        ],
      ],
    );
  }
}