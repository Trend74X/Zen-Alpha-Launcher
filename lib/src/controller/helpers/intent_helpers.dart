// Helper to launch Phone
  import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> launchPhone() async {
    final Uri url = Uri(scheme: 'tel');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void openMessagesList() {
    const intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      type: 'vnd.android-dir/mms-sms', 
    );
    intent.launch();
  }

  // Helper to launch Camera
  void launchCamera() {
    const intent = AndroidIntent(
      action: 'android.media.action.IMAGE_CAPTURE',
    );
    intent.launch();
  }

  // Helper to launch Notes safely without hitting the file manager
  void openNotes() {
    const intent = AndroidIntent(
      action: 'android.intent.action.CREATE_NOTE',
    );
    
    intent.launch().catchError((e) {
      final commonNotesApps = [
        'com.google.android.apps.notes', // Google Keep
        'com.samsung.android.app.notes', // Samsung Notes
        'com.miui.notes',                // Xiaomi Notes
        'com.oneplus.note',              // OnePlus Notes
      ];

      for (var package in commonNotesApps) {
        try {
          final fallbackIntent = AndroidIntent(
            action: 'android.intent.action.MAIN',
            category: 'android.intent.category.LAUNCHER',
            package: package,
          );
          fallbackIntent.launch();
          return; 
        } catch (_) {}
      }
    });
  }

   // Helper to launch standard Maps view directly
  void openMaps() {
    const intent = AndroidIntent(
      action: 'android.intent.action.VIEW',
      data: 'geo:0,0?q=', // Standard geographical mapping layout tag
    );
    
    intent.launch().catchError((e) {
      // Fallback: If geo-intent target fails, execute explicit lookup query for core Maps package
      const fallbackIntent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.LAUNCHER',
        package: 'com.google.android.apps.maps',
      );
      fallbackIntent.launch();
    });
  }

  // // Helper to safely target and launch the device's native Calculator
  // Future<void> openCalculator() async {
  //   final commonCalculators = [
  //     'com.miui.calculator',                 // Xiaomi / Redmi / POCO
  //     'com.google.android.calculator',       // Pixel / Motorola / Stock Android
  //     'com.sec.android.app.popupcalculator', // Samsung Galaxy
  //     'com.oneplus.calculator',              // OnePlus
  //     'com.oppo.calculator',                 // Oppo
  //     'com.transsion.calculator',            // Tecno / Infinix
  //     'com.android.calculator2',             // Generic AOSP Fallback
  //   ];

  //   // 1. Try launching via a direct package URI scheme using url_launcher
  //   for (var package in commonCalculators) {
  //     final Uri url = Uri.parse('package:$package');
  //     try {
  //       if (await canLaunchUrl(url)) {
  //         await launchUrl(url);
  //         return; // Success! It opened on the device. Stop execution.
  //       }
  //     } catch (_) {
  //       // Quietly catch and try the next package tag in the loop array
  //     }
  //   }

  //   // 2. LAST RESORT FALLBACK: If url_launcher package deep-links fail, 
  //   // fall back to a raw, un-categorized Android Intent.
  //   try {
  //     const systemIntent = AndroidIntent(
  //       action: 'android.intent.action.MAIN',
  //       package: 'com.miui.calculator', // Direct hardcoded injection for your test device
  //     );
  //     await systemIntent.launch();
  //   } catch (e) {
  //     debugPrint("Absolute calculator fallback failure: $e");
  //   }
  // }