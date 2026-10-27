import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RentalDeviceRestrictedPage extends StatefulWidget {
  final String? productID;
  static const MethodChannel hardwareChannel = MethodChannel('com.tarumt.rebyte/hardware');

  const RentalDeviceRestrictedPage({super.key, this.productID});

  static Future<void> unlockDevicePlatform() async {
    try {
      await hardwareChannel.invokeMethod('stopLockTaskMode');
    } catch (e) {
      debugPrint('Error stopping Lock Task Mode: $e');
    }
  }

  @override
  State<RentalDeviceRestrictedPage> createState() => _RentalDeviceRestrictedPageState();
}

class _RentalDeviceRestrictedPageState extends State<RentalDeviceRestrictedPage> {
  static const MethodChannel _hardwareChannel = MethodChannel('com.tarumt.rebyte/hardware');

  static _RentalDeviceRestrictedPageState? activeState;

  @override
  void initState() {
    super.initState();
    activeState = this;
    _startLockTaskMode();
  }

  @override
  void dispose() {
    if (activeState == this) {
      activeState = null;
    }
    super.dispose();
  }

  Future<void> _startLockTaskMode() async {
    try {
      await _hardwareChannel.invokeMethod('startLockTaskMode');
    } catch (e) {
      debugPrint('Error starting Lock Task Mode: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // PopScope prevents back button navigation so user cannot leave the restricted screen
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _startLockTaskMode();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A), // Dark restricted security theme
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Prominent Lock Icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.lock_rounded,
                        color: Color(0xFFEF4444),
                        size: 52,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Header: ReByte Rental Device
                  const Text(
                    'ReByte Rental Device',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Primary Message: This device has been restricted.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'This device has been restricted.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFCA5A5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Instruction Message: Please complete payment or contact ReByte.
                  const Text(
                    'Please complete payment\nor contact ReByte.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Support / Verification details card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.headset_mic_rounded, color: Color(0xFF38BDF8), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Support & Resolution',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Phone: +60 3-8999 1234',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Email: support@rebyte.com',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        ),
                        if (widget.productID != null && widget.productID!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Divider(color: Color(0xFF334155)),
                          const SizedBox(height: 6),
                          Text(
                            'Device ID: ${widget.productID}',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
