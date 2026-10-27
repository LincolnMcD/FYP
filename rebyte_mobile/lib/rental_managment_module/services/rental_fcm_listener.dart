import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../rental_device_restricted_page.dart';
import '../../account_management_module/home_page.dart';
import '../../account_management_module/services/session_service.dart';

// Global navigator key to navigate to restricted page from background/foreground FCM handlers
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handles background messages
  debugPrint('Handling a background message: ${message.messageId}, data: ${message.data}');
}

class RentalFcmListener {
  static void initialize() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Foreground FCM messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM onMessage] received: ${message.data}');
      _handleMessage(message);
    });

    // When the app is opened from a notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM onMessageOpenedApp] received: ${message.data}');
      _handleMessage(message);
    });

    // Check if app was launched from a terminated state via FCM
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('[FCM getInitialMessage] received: ${message.data}');
        _handleMessage(message);
      }
    });
  }

  static void _handleMessage(RemoteMessage message) {
    final action = message.data['action'] ?? message.data['command'];
    if (action == 'LOCK_DEVICE') {
      final productID = message.data['productID'];
      lockDeviceLocally(productID: productID);
    } else if (action == 'UNLOCK_DEVICE') {
      unlockDeviceLocally();
    }
  }

  static void lockDeviceLocally({String? productID}) {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => RentalDeviceRestrictedPage(productID: productID),
      ),
      (route) => false,
    );
  }

  static Future<void> unlockDeviceLocally() async {
    // 1. Release Android Lock Task Mode via DPM
    await RentalDeviceRestrictedPage.unlockDevicePlatform();

    // 2. Fetch current user session to restore Customer Home Page
    final session = await SessionService.getSession();
    final bool isLoggedIn = session.isNotEmpty;
    final String? email = session['email'];
    final String? name = session['name'];

    // Evict cached textures to prevent GPU/surface texture corruption after lock task mode
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    // 3. Navigate directly to customer HomePage
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => HomePage(
          isLoggedIn: isLoggedIn,
          email: email,
          name: name,
          toastMessage: 'Device unlocked. Restored to normal operation.',
          toastIsError: false,
        ),
      ),
      (route) => false,
    );
  }
}
