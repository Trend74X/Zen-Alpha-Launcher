import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Play Store "prominent disclosure" dialog.
///
/// Google requires apps to explain what sensitive data/permission is used for
/// *before* sending the user to the system permission screen. This matches the
/// dark visual language used by the rest of Zen.
Future<bool> showPermissionDisclosure({
  required String eyebrow,
  required String title,
  required String body,
  String continueLabel = 'CONTINUE',
  String declineLabel = 'NOT NOW',
}) async {
  final bool? accepted = await Get.dialog<bool>(
    barrierDismissible: false,
    AlertDialog(
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const LinearBorder(),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            eyebrow,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
      content: Text(
        body,
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 13,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: Text(
            declineLabel,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Get.back(result: true),
          child: Text(
            continueLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );

  return accepted ?? false;
}
