import 'package:flutter/material.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import '../device_tradein_module/models/device_model.dart';
import '../account_management_module/welcome_page.dart';
import 'touchscreen_test_page.dart';
import 'display_test_page.dart';
import 'camera_test_page.dart';
import 'microphone_test_page.dart';
import 'speaker_test_page.dart';
import 'sensor_test_page.dart';
import 'network_test_page.dart';
import 'gps_test_page.dart';

class DiagnosticSuitePage extends StatefulWidget {
  final DeviceModel? device;
  final String? tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;

  const DiagnosticSuitePage({
    super.key,
    this.device,
    this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
  });

  @override
  State<DiagnosticSuitePage> createState() => _DiagnosticSuitePageState();
}

class _DiagnosticSuitePageState extends State<DiagnosticSuitePage> {
  final List<Map<String, dynamic>> _diagnosticItems = [
    {
      'title': 'Touchscreen',
      'icon': Icons.touch_app_outlined,
      'isAvailable': true,
    },
    {
      'title': 'Display',
      'icon': Icons.phone_android_outlined,
      'isAvailable': true,
    },
    {
      'title': 'Camera',
      'icon': Icons.camera_alt_outlined,
      'isAvailable': true,
    },
    {
      'title': 'Microphone',
      'icon': Icons.mic_none_outlined,
      'isAvailable': true,
    },
    {
      'title': 'Speaker',
      'icon': Icons.volume_up_outlined,
      'isAvailable': true,
    },
    {
      'title': 'Sensors',
      'icon': Icons.sensors_outlined,
      'isAvailable': true,
    },
    {
      'title': 'Wi-Fi',
      'icon': Icons.wifi_outlined,
      'isAvailable': true,
    },
    {
      'title': 'GPS',
      'icon': Icons.location_on_outlined,
      'isAvailable': true,
    },
  ];

  bool _checkLoginRequired() {
    if (!widget.isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
      return false;
    }
    return true;
  }

  void _onStartDiagnostic() {
    if (!_checkLoginRequired()) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TouchscreenTestPage(
          device: widget.device,
          tradeInRequestID: widget.tradeInRequestID,
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
        ),
      ),
    );
  }

  void _onTileTapped(Map<String, dynamic> item) {
    if (!_checkLoginRequired()) return;

    if (item['title'] == 'Touchscreen') {
      _onStartDiagnostic();
    } else if (item['title'] == 'Display') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DisplayTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
          ),
        ),
      );
    } else if (item['title'] == 'Camera') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CameraTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: 100,
            displayScore: 100,
          ),
        ),
      );
    } else if (item['title'] == 'Microphone') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MicrophoneTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: 100,
            displayScore: 100,
            cameraScore: 100,
          ),
        ),
      );
    } else if (item['title'] == 'Speaker') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SpeakerTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: 100,
            displayScore: 100,
            cameraScore: 100,
            micScore: 100,
          ),
        ),
      );
    } else if (item['title'] == 'Sensors') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SensorTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: 100,
            displayScore: 100,
            cameraScore: 100,
            micScore: 100,
            speakerScore: 100,
          ),
        ),
      );
    } else if (item['title'] == 'Wi-Fi') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NetworkTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: 100,
            displayScore: 100,
            cameraScore: 100,
            micScore: 100,
            speakerScore: 100,
            sensorScore: 100,
          ),
        ),
      );
    } else if (item['title'] == 'GPS') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GpsTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: 100,
            displayScore: 100,
            cameraScore: 100,
            micScore: 100,
            speakerScore: 100,
            sensorScore: 100,
            networkScore: 100,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: const ReByteAppBar(),
      drawer: ReByteDrawer(
        isLoggedIn: widget.isLoggedIn,
        email: widget.email,
        name: widget.name,
        selectedIndex: 5,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back arrow button
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(height: 14),

                    // Title
                    const Center(
                      child: Text(
                        'Device Diagnostic Suite',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F254B),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Subtitle / explanation
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'Completing these self-tests ensures accurate valuation and expedites your trade-in process by verifying hardware functionality.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Color(0xFF475569),
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // 2-column Grid of diagnostic test cards
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                        childAspectRatio: 1.15,
                      ),
                      itemCount: _diagnosticItems.length,
                      itemBuilder: (context, index) {
                        final item = _diagnosticItems[index];
                        return _buildTestCard(item);
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Bottom pinned action bar
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Estimated time badge
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF0C5AD2)),
                      SizedBox(width: 6),
                      Text(
                        'Estimated time: 3-5 minutes',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Start Diagnostic button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _onStartDiagnostic,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0848AA),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Start Diagnostic',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: -1,
      ),
    );
  }

  Widget _buildTestCard(Map<String, dynamic> item) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _onTileTapped(item),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0).withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Circular icon container
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  item['icon'] as IconData,
                  size: 24,
                  color: const Color(0xFF0C5AD2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item['title'] as String,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
