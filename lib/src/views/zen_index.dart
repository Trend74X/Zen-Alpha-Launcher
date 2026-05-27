import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zen_launcher/src/controller/app_controller.dart';

class ZenIndex extends StatelessWidget {
  const ZenIndex({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = Get.find<AppController>();
    final TextEditingController searchTexController = TextEditingController();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- DRAWER TITLE ---
              const Padding(
                padding: EdgeInsets.only(top: 28.0, left: 8.0, bottom: 12.0),
                child: Text(
                  'Applications',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1,
                  ),
                ),
              ),

              // --- SEARCH BAR & TOGGLE ACTIONS CONTROLLER CONTAINER ---
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                child: Row(
                  children: [
                    // --- DYNAMIC SEARCH BAR INPUT ---
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D0D0D), // Bulletproof custom hex (replaces grey[950])
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF262626), width: 1),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: TextField(
                          controller: searchTexController,
                          onChanged: (value) => controller.searchQuery.value = value,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          cursorColor: Colors.grey,
                          decoration: InputDecoration(
                            hintText: 'search apps...',
                            hintStyle: TextStyle(color: const Color(0xFF404040), fontSize: 14), // Replaces grey[700]
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            suffixIcon: Obx(() => controller.searchQuery.value.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.grey, size: 16),
                                    onPressed: () {
                                      searchTexController.clear();
                                      controller.searchQuery.value = '';
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  )
                                : const SizedBox.shrink()),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // --- VISIBILITY CONFIG TOGGLE ICON ---
                    Obx(() => InkWell(
                          onTap: () => controller.showIcons.toggle(),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 44,
                            width: 44,
                            decoration: BoxDecoration(
                              color: controller.showIcons.value ? const Color(0xFF0D0D0D) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF262626), 
                                width: 1
                              ),
                            ),
                            child: Icon(
                              controller.showIcons.value 
                                  ? Icons.visibility_outlined 
                                  : Icons.visibility_off_outlined,
                              color: controller.showIcons.value ? Colors.white70 : const Color(0xFF595959), // Replaces grey[800]
                              size: 18,
                            ),
                          ),
                        )),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // --- FILTERED INDEX APP DRAWER LIST ---
              Expanded(
                child: Obx(() {
                  if (controller.isLoadingApps.value) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.grey),
                    );
                  }

                  final displayApps = controller.filteredApps;

                  if (displayApps.isEmpty) {
                    return const Center(
                      child: Text(
                        "No matching applications found.",
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 120, top: 4),
                    itemCount: displayApps.length,
                    itemBuilder: (context, index) {
                      final app = displayApps[index];

                      return InkWell(
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          controller.launchApplicationContainer(app.packageName);
                        },
                        splashColor: Colors.transparent,
                        highlightColor: const Color(0xFF0D0D0D),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
                          child: Row(
                            children: [
                              // --- FIXED: WRAPPED IN OBX FOR INSTANT TOGGLING ---
                              Obx(() {
                                if (!controller.showIcons.value) {
                                  return const SizedBox.shrink(); // Pulls the icon element out entirely
                                }
                                
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: ColorFiltered(
                                        colorFilter: const ColorFilter.matrix(<double>[
                                          0.2126 + 0.1, 0.7152 + 0.1, 0.0722 + 0.1, 0, 15, // Increase red offset and slight gain
                                          0.2126 + 0.1, 0.7152 + 0.1, 0.0722 + 0.1, 0, 15, // Increase green offset and slight gain
                                          0.2126 + 0.1, 0.7152 + 0.1, 0.0722 + 0.1, 0, 15, // Increase blue offset and slight gain
                                          0,      0,      0,      0.35, 0, // Preserve original opacity (35%)
                                        ]),
                                        child: app.iconBytes != null
                                            ? Image.memory(
                                                app.iconBytes!,
                                                width: 32, 
                                                height: 32,
                                                fit: BoxFit.contain,
                                              )
                                            : Container(
                                                width: 32,
                                                height: 32,
                                                color: const Color(0xFF1A1A1A),
                                                child: const Icon(Icons.android, color: Colors.white24, size: 16),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 16.0), // Space only when icon is active
                                  ],
                                );
                              }),
                              
                              // --- CLEAN TYPOGRAPHY APP TITLE ---
                              Text(
                                app.name,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),

            ],
          ),
        ),
      ),
    );
  }
}