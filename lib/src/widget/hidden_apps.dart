import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zen_launcher/src/controller/app_controller.dart'; // Verify your controller path matches here

void showHiddenAppsManagementSheet(BuildContext context) {
  final AppController controller = Get.find<AppController>();

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.black,
    isScrollControlled: true,
    // Sharp edges matching your Zen architecture design tokens
    shape: const LinearBorder(), 
    builder: (context) {
      return PopScope(
        // Safety interceptor: drops visibility immediately if system context changes
        onPopInvokedWithResult: (didPop, result) {
          debugPrint("Hidden environment session safely invalidated.");
        },
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.only(top: 24.0, left: 24.0, right: 24.0, bottom: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER SECTION ---
              const Text(
                'HIDDEN APPLICATIONS',
                style: TextStyle(
                  color: Colors.white, 
                  fontSize: 16, 
                  fontWeight: FontWeight.w900, 
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Apps filtered out of your daily awareness loops.', 
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              
              // Minimalist custom layout rule divider
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Divider(color: Color(0xFF1A1A1A), height: 1),
              ),
              
              // --- RE-ARCHITECTED APPS LIST MATRIX ---
              Expanded(
                child: Obx(() {
                  // Pull from your master application array to isolate ONLY what is marked hidden
                  final hiddenAppsList = controller.installedApps.where(
                    (app) => controller.hiddenAppPackages.contains(app.packageName)
                  ).toList();

                  if (hiddenAppsList.isEmpty) {
                    return Center(
                      child: Text(
                        'NO APPS HIDDEN',
                        style: TextStyle(
                          color: Colors.grey[700], 
                          fontSize: 11, 
                          fontWeight: FontWeight.bold, 
                          letterSpacing: 2.0,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: hiddenAppsList.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final app = hiddenAppsList[index];

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // --- LEFT SIDE: APPLICATION LABEL ---
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 2,
                                    height: 14,
                                    color: const Color(0xFF262626),
                                    margin: const EdgeInsets.only(right: 12),
                                  ),
                                  Expanded(
                                    child: Text(
                                      app.name.toUpperCase(),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white, 
                                        fontSize: 13, 
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // --- RIGHT SIDE: SPLIT-ACTION TEXT TRACKS ---
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 1. INTENTIONAL LAUNCH ACTION (Keeps it hidden)
                                GestureDetector(
                                  onTap: () {
                                    // Launch the application using your existing controller method
                                    controller.launchApplicationContainer(app.packageName);
                                    // Optional: Close the bottom sheet so the app opens immediately on screen
                                    Navigator.pop(context); 
                                  },
                                  child: Text(
                                    'OPEN',
                                    style: TextStyle(
                                      color: Colors.grey[300], // Brighter high-contrast for primary action
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                
                                // Structural Spacer Divider Symbol
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                  child: Text(
                                    '/', 
                                    style: TextStyle(color: Colors.grey[800], fontSize: 11),
                                  ),
                                ),
                                
                                // 2. RE-ARCHITECT VISIBILITY ACTION (Unhides it)
                                GestureDetector(
                                  onTap: () => controller.revealApplication(app.packageName),
                                  child: Text(
                                    'REVEAL',
                                    style: TextStyle(
                                      color: Colors.grey[600], // Subdued gray since it's used less often
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      );
    },
  );
}