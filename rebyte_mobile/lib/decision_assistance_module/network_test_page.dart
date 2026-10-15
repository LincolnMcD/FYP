import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../device_tradein_module/models/device_model.dart';
import 'gps_test_page.dart';

enum SubTestStatus { notTested, testing, pass, fail }

class NetworkTestPage extends StatefulWidget {
  final DeviceModel? device;
  final String? tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final int touchScore;
  final int displayScore;
  final int cameraScore;
  final int micScore;
  final int speakerScore;
  final int sensorScore;
  final bool isTouchSkipped;
  final bool isDisplaySkipped;
  final bool isCameraSkipped;
  final bool isMicSkipped;
  final bool isSpeakerSkipped;
  final bool isSensorSkipped;

  const NetworkTestPage({
    super.key,
    this.device,
    this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
    required this.touchScore,
    required this.displayScore,
    required this.cameraScore,
    required this.micScore,
    required this.speakerScore,
    required this.sensorScore,
    this.isTouchSkipped = false,
    this.isDisplaySkipped = false,
    this.isCameraSkipped = false,
    this.isMicSkipped = false,
    this.isSpeakerSkipped = false,
    this.isSensorSkipped = false,
  });

  @override
  State<NetworkTestPage> createState() => _NetworkTestPageState();
}

class _NetworkTestPageState extends State<NetworkTestPage> {
  static const MethodChannel _hardwareChannel = MethodChannel('com.tarumt.rebyte/hardware');

  // Sub-tests status
  SubTestStatus _wifiConnStatus = SubTestStatus.notTested;
  String _wifiConnMessage = 'Not tested yet. Enable Wi-Fi and connect to a network.';

  SubTestStatus _wifiInternetStatus = SubTestStatus.notTested;
  String _wifiInternetMessage = 'Not tested yet. Validates HTTPS communication over Wi-Fi.';

  SubTestStatus _mobileConnStatus = SubTestStatus.notTested;
  String _mobileConnMessage = 'Not tested yet. Requires active cellular connection.';

  SubTestStatus _mobileInternetStatus = SubTestStatus.notTested;
  String _mobileInternetMessage = 'Not tested yet. Validates HTTPS communication over cellular.';

  // Scoring
  // Scoring
  // Wi-Fi Connection: 20%
  // Wi-Fi Internet: 30%
  // Mobile Data Connection: 20%
  // Mobile Data Internet: 30%
  int get networkSeverity {
    int deduction = 0;
    if (_wifiConnStatus != SubTestStatus.pass) deduction += 20;
    if (_wifiInternetStatus != SubTestStatus.pass) deduction += 30;
    if (_mobileConnStatus != SubTestStatus.pass) deduction += 20;
    if (_mobileInternetStatus != SubTestStatus.pass) deduction += 30;
    return deduction;
  }

  int get networkPerformance => (100 - networkSeverity).clamp(0, 100);

  double get networkContribution => 15.0 * (networkPerformance / 100.0);

  // Run Test 1: Wi-Fi Connection
  Future<void> _runWifiConnectionTest() async {
    setState(() {
      _wifiConnStatus = SubTestStatus.testing;
      _wifiConnMessage = 'Checking Wi-Fi hardware and connection...';
    });

    try {
      // Modern Android requires location permission to read SSID and Wi-Fi scan details
      await _hardwareChannel.invokeMethod('requestLocationPermission');
      final Map<dynamic, dynamic>? res =
          await _hardwareChannel.invokeMethod<Map<dynamic, dynamic>>('checkWifiConnection');
      final bool connected = res?['connected'] == true;
      final bool enabled = res?['wifiEnabled'] == true;
      final String ssid = res?['ssid'] as String? ?? 'Wi-Fi';
      final int rssi = (res?['rssi'] as num?)?.toInt() ?? -55;

      setState(() {
        if (connected) {
          _wifiConnStatus = SubTestStatus.pass;
          _wifiConnMessage = 'Connected to "$ssid" ($rssi dBm).';
        } else if (!enabled) {
          _wifiConnStatus = SubTestStatus.fail;
          _wifiConnMessage = 'Wi-Fi is currently disabled. Please enable Wi-Fi in settings.';
          _wifiInternetStatus = SubTestStatus.fail;
          _wifiInternetMessage = 'Wi-Fi connection failed. Internet access unavailable.';
        } else {
          _wifiConnStatus = SubTestStatus.fail;
          _wifiConnMessage = 'Wi-Fi is enabled but not connected to any network.';
          _wifiInternetStatus = SubTestStatus.fail;
          _wifiInternetMessage = 'Wi-Fi connection failed. Internet access unavailable.';
        }
      });
    } catch (e) {
      setState(() {
        _wifiConnStatus = SubTestStatus.fail;
        _wifiConnMessage = 'Unable to access Wi-Fi hardware adapter.';
        _wifiInternetStatus = SubTestStatus.fail;
        _wifiInternetMessage = 'Wi-Fi connection failed. Internet access unavailable.';
      });
    }
  }

  // Run Test 2: Wi-Fi Internet Access
  Future<void> _runWifiInternetTest() async {
    if (_wifiConnStatus != SubTestStatus.pass) {
      setState(() {
        _wifiInternetStatus = SubTestStatus.fail;
        _wifiInternetMessage = 'Wi-Fi connection failed. Internet access unavailable.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wi-Fi is not connected. Internet access test failed.')),
      );
      return;
    }

    setState(() {
      _wifiInternetStatus = SubTestStatus.testing;
      _wifiInternetMessage = 'Sending HTTPS probe request through Wi-Fi...';
    });

    try {
      final bool? pass = await _hardwareChannel
          .invokeMethod<bool>('testWifiInternet')
          .timeout(const Duration(seconds: 6));
      setState(() {
        if (pass == true) {
          _wifiInternetStatus = SubTestStatus.pass;
          _wifiInternetMessage = 'HTTPS probe request succeeded through Wi-Fi route.';
        } else {
          _wifiInternetStatus = SubTestStatus.fail;
          _wifiInternetMessage = 'HTTPS probe request failed through Wi-Fi after 3 retries.';
        }
      });
    } catch (_) {
      setState(() {
        _wifiInternetStatus = SubTestStatus.fail;
        _wifiInternetMessage = 'Failed to route request through Wi-Fi (Connection blocked or timed out).';
      });
    }
  }

  // Run Test 3: Mobile Data Connection
  Future<void> _runMobileConnectionTest() async {
    setState(() {
      _mobileConnStatus = SubTestStatus.testing;
      _mobileConnMessage = 'Checking cellular data connection...';
    });

    try {
      final Map<dynamic, dynamic>? res =
          await _hardwareChannel.invokeMethod<Map<dynamic, dynamic>>('checkMobileConnection');
      final bool connected = res?['connected'] == true;

      setState(() {
        if (connected) {
          _mobileConnStatus = SubTestStatus.pass;
          _mobileConnMessage = 'Active cellular data connection established.';
        } else {
          _mobileConnStatus = SubTestStatus.fail;
          _mobileConnMessage = 'No active cellular data connection. Active SIM or mobile data missing.';
          _mobileInternetStatus = SubTestStatus.fail;
          _mobileInternetMessage = 'Mobile data connection failed. Internet access unavailable.';
        }
      });
    } catch (_) {
      setState(() {
        _mobileConnStatus = SubTestStatus.fail;
        _mobileConnMessage = 'Cellular telephony hardware unavailable.';
        _mobileInternetStatus = SubTestStatus.fail;
        _mobileInternetMessage = 'Mobile data connection failed. Internet access unavailable.';
      });
    }
  }

  // Run Test 4: Mobile Data Internet Access
  Future<void> _runMobileInternetTest() async {
    if (_mobileConnStatus != SubTestStatus.pass) {
      setState(() {
        _mobileInternetStatus = SubTestStatus.fail;
        _mobileInternetMessage = 'Mobile data connection failed. Internet access unavailable.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mobile data is not connected. Internet access test failed.')),
      );
      return;
    }

    setState(() {
      _mobileInternetStatus = SubTestStatus.testing;
      _mobileInternetMessage = 'Sending HTTPS probe request through cellular transport...';
    });

    try {
      final bool? pass = await _hardwareChannel
          .invokeMethod<bool>('testMobileInternet')
          .timeout(const Duration(seconds: 9));
      setState(() {
        if (pass == true) {
          _mobileInternetStatus = SubTestStatus.pass;
          _mobileInternetMessage = 'HTTPS probe request succeeded through Mobile Data.';
        } else {
          _mobileInternetStatus = SubTestStatus.fail;
          _mobileInternetMessage = 'HTTPS request timed out through cellular network after 3 retries.';
        }
      });
    } catch (_) {
      setState(() {
        _mobileInternetStatus = SubTestStatus.fail;
        _mobileInternetMessage = 'Failed to route probe request through cellular network (Connection blocked or timed out).';
      });
    }
  }

  // Run Wi-Fi Tests (Connection & Internet)
  Future<void> _runWifiTests() async {
    await _runWifiConnectionTest();
    if (_wifiConnStatus == SubTestStatus.pass) {
      await _runWifiInternetTest();
    } else {
      setState(() {
        _wifiInternetStatus = SubTestStatus.fail;
        _wifiInternetMessage = 'Wi-Fi connection failed. Internet access unavailable.';
      });
    }
  }

  // Run Mobile Data Tests (Connection & Internet)
  Future<void> _runMobileTests() async {
    await _runMobileConnectionTest();
    if (_mobileConnStatus == SubTestStatus.pass) {
      await _runMobileInternetTest();
    } else {
      setState(() {
        _mobileInternetStatus = SubTestStatus.fail;
        _mobileInternetMessage = 'Mobile data connection failed. Internet access unavailable.';
      });
    }
  }

  void _onProceedToGps() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        networkPerformance == 100
                            ? Icons.check_circle_rounded
                            : (networkPerformance >= 50
                                ? Icons.info_outline_rounded
                                : (networkPerformance >= 1 ? Icons.warning_amber_rounded : Icons.cancel_rounded)),
                        color: networkPerformance == 100
                            ? const Color(0xFF16A34A)
                            : (networkPerformance >= 50
                                ? const Color(0xFF0C5AD2)
                                : (networkPerformance >= 1 ? const Color(0xFFD97706) : const Color(0xFFE11D48))),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Score: $networkPerformance/100',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  if (networkPerformance != 100)
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• Wi-Fi Connection: ${_wifiConnStatus == SubTestStatus.pass ? "PASS" : "FAIL"}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569),
                      height: 1.6,
                    ),
                  ),
                  Text(
                    '• Wi-Fi Internet Access: ${_wifiInternetStatus == SubTestStatus.pass ? "PASS" : "FAIL"}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569),
                      height: 1.6,
                    ),
                  ),
                  Text(
                    '• Mobile Data Connection: ${_mobileConnStatus == SubTestStatus.pass ? "PASS" : "FAIL"}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569),
                      height: 1.6,
                    ),
                  ),
                  Text(
                    '• Mobile Data Internet Access: ${_mobileInternetStatus == SubTestStatus.pass ? "PASS" : "FAIL"}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF475569),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  if (networkPerformance != 100) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: const Text(
                          'CLOSE',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GpsTestPage(
                              device: widget.device,
                              tradeInRequestID: widget.tradeInRequestID,
                              isLoggedIn: widget.isLoggedIn,
                              email: widget.email,
                              name: widget.name,
                              touchScore: widget.touchScore,
                              displayScore: widget.displayScore,
                              cameraScore: widget.cameraScore,
                              micScore: widget.micScore,
                              speakerScore: widget.speakerScore,
                              sensorScore: widget.sensorScore,
                              networkScore: networkPerformance,
                              isTouchSkipped: widget.isTouchSkipped,
                              isDisplaySkipped: widget.isDisplaySkipped,
                              isCameraSkipped: widget.isCameraSkipped,
                              isMicSkipped: widget.isMicSkipped,
                              isSpeakerSkipped: widget.isSpeakerSkipped,
                              isSensorSkipped: widget.isSensorSkipped,
                              isNetworkSkipped: false,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C5AD2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'NEXT TEST',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSkip() async {
    final bool? confirmSkip = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.skip_next_rounded,
                    color: Color(0xFFF59E0B),
                    size: 24,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Skip Network Test?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Are you sure you want to skip this test? Skipped tests will be recorded with 0/100 score and may affect your overall device valuation.',
                textAlign: TextAlign.justify,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text(
                        'CANCEL',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0848AA),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'SKIP',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmSkip == true && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => GpsTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: widget.touchScore,
            displayScore: widget.displayScore,
            cameraScore: widget.cameraScore,
            micScore: widget.micScore,
            speakerScore: widget.speakerScore,
            sensorScore: widget.sensorScore,
            networkScore: 0,
            isTouchSkipped: widget.isTouchSkipped,
            isDisplaySkipped: widget.isDisplaySkipped,
            isCameraSkipped: widget.isCameraSkipped,
            isMicSkipped: widget.isMicSkipped,
            isSpeakerSkipped: widget.isSpeakerSkipped,
            isSensorSkipped: widget.isSensorSkipped,
            isNetworkSkipped: true,
          ),
        ),
      );
    }
  }

  Future<bool> _showExitConfirmationDialog() async {
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Exit Network Test?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Are you sure you want to exit the Network test? Your current progress will be lost.',
                textAlign: TextAlign.justify,
                style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: const Text(
                        'CANCEL',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE11D48),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'EXIT',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _handleBack() async {
    final bool shouldExit = await _showExitConfirmationDialog();
    if (shouldExit && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              // Header Row (Back button, Skip Test button, 7/8 indicator)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                      onPressed: _handleBack,
                    ),
                    ElevatedButton(
                      onPressed: _handleSkip,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0848AA),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Skip Test',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEBF3FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '7/8',
                        style: TextStyle(
                          color: Color(0xFF0848AA),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Title & Subtitle Instructions
              const SizedBox(height: 4),
              const Text(
                'Network Test',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F254B),
                ),
              ),
              const SizedBox(height: 8),

              // Highlighted Important Notice
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFFB45309), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Important Testing Instruction:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            '• When testing Wi-Fi: Turn ON Wi-Fi and Turn OFF Mobile Data.\n• When testing Mobile Data: Turn ON Mobile Data and Turn OFF Wi-Fi.',
                            textAlign: TextAlign.justify,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF92400E),
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section A: Wi-Fi Tests
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.wifi, color: Color(0xFF0848AA), size: 20),
                              SizedBox(width: 6),
                              Text(
                                'Wi-Fi Tests',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: _runWifiTests,
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: const Text('Run Wi-Fi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF0848AA),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Test 1: Wi-Fi Connection
                      _buildSubTestCard(
                        title: '1. Wi-Fi Connection',
                        instruction: 'Enable Wi-Fi and connect to a known working Wi-Fi network.',
                        status: _wifiConnStatus,
                        message: _wifiConnMessage,
                        onStart: _runWifiConnectionTest,
                      ),
                      const SizedBox(height: 10),

                      // Test 2: Wi-Fi Internet Access
                      _buildSubTestCard(
                        title: '2. Wi-Fi Internet Access',
                        instruction: 'Sends an HTTPS probe request specifically through the Wi-Fi network.',
                        status: _wifiInternetStatus,
                        message: _wifiInternetMessage,
                        onStart: _runWifiInternetTest,
                      ),
                      const SizedBox(height: 18),

                      // Section B: Mobile Data Tests
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.signal_cellular_alt, color: Color(0xFF0848AA), size: 20),
                              SizedBox(width: 6),
                              Text(
                                'Mobile Data Tests',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: _runMobileTests,
                            icon: const Icon(Icons.play_arrow, size: 16),
                            label: const Text('Run Mobile Data', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF0848AA),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Test 3: Mobile Data Connection
                      _buildSubTestCard(
                        title: '3. Mobile Data Connection',
                        instruction: 'Ensure active SIM/eSIM is inserted and cellular data is enabled.',
                        status: _mobileConnStatus,
                        message: _mobileConnMessage,
                        onStart: _runMobileConnectionTest,
                      ),
                      const SizedBox(height: 10),

                      // Test 4: Mobile Data Internet Access
                      _buildSubTestCard(
                        title: '4. Mobile Data Internet Access',
                        instruction: 'Routes an HTTPS probe request through the cellular data transport.',
                        status: _mobileInternetStatus,
                        message: _mobileInternetMessage,
                        onStart: _runMobileInternetTest,
                      ),
                      const SizedBox(height: 16),

                      // Performance Status Summary Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TEST SUMMARY',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Wi-Fi Connection', style: TextStyle(fontSize: 13, color: Color(0xFF334155))),
                                _buildMiniStatusBadge(_wifiConnStatus),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Wi-Fi Internet Access', style: TextStyle(fontSize: 13, color: Color(0xFF334155))),
                                _buildMiniStatusBadge(_wifiInternetStatus),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Mobile Data Connection', style: TextStyle(fontSize: 13, color: Color(0xFF334155))),
                                _buildMiniStatusBadge(_mobileConnStatus),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Mobile Data Internet Access', style: TextStyle(fontSize: 13, color: Color(0xFF334155))),
                                _buildMiniStatusBadge(_mobileInternetStatus),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),

              // Bottom Actions
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _onProceedToGps,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0848AA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Confirm & Next',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildSubTestCard({
    required String title,
    required String instruction,
    required SubTestStatus status,
    required String message,
    required VoidCallback onStart,
  }) {
    Color badgeColor;
    String badgeText;
    switch (status) {
      case SubTestStatus.pass:
        badgeColor = const Color(0xFF16A34A);
        badgeText = 'PASS';
        break;
      case SubTestStatus.fail:
        badgeColor = const Color(0xFFE11D48);
        badgeText = 'FAIL';
        break;
      case SubTestStatus.testing:
        badgeColor = const Color(0xFF2563EB);
        badgeText = 'TESTING...';
        break;
      case SubTestStatus.notTested:
        badgeColor = const Color(0xFF64748B);
        badgeText = 'NOT TESTED';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F254B)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(instruction, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                if (status == SubTestStatus.testing) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 11,
                      color: status == SubTestStatus.pass
                          ? const Color(0xFF16A34A)
                          : (status == SubTestStatus.fail
                              ? const Color(0xFFE11D48)
                              : const Color(0xFF475569)),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              height: 32,
              child: ElevatedButton(
                onPressed: status == SubTestStatus.testing ? null : onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEFF6FF),
                  foregroundColor: const Color(0xFF0848AA),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: Text(
                  status == SubTestStatus.notTested ? 'Start Test' : 'Retest',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatusBadge(SubTestStatus status) {
    Color color;
    String text;
    switch (status) {
      case SubTestStatus.pass:
        color = const Color(0xFF16A34A);
        text = 'PASS';
        break;
      case SubTestStatus.fail:
        color = const Color(0xFFE11D48);
        text = 'FAIL';
        break;
      case SubTestStatus.testing:
        color = const Color(0xFF2563EB);
        text = 'TESTING';
        break;
      case SubTestStatus.notTested:
        color = const Color(0xFF94A3B8);
        text = 'PENDING';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
