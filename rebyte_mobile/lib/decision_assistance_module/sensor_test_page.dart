import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../device_tradein_module/models/device_model.dart';
import 'network_test_page.dart';

class SensorTestPage extends StatefulWidget {
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
  final bool isTouchSkipped;
  final bool isDisplaySkipped;
  final bool isCameraSkipped;
  final bool isMicSkipped;
  final bool isSpeakerSkipped;

  const SensorTestPage({
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
    this.isTouchSkipped = false,
    this.isDisplaySkipped = false,
    this.isCameraSkipped = false,
    this.isMicSkipped = false,
    this.isSpeakerSkipped = false,
  });

  @override
  State<SensorTestPage> createState() => _SensorTestPageState();
}

class _SensorTestPageState extends State<SensorTestPage> with SingleTickerProviderStateMixin {
  // Sensor live values
  double _accelX = 0.26;
  double _accelY = 1.26;
  double _accelZ = 9.73;

  // Gyroscope angular velocity
  double _gyroX = 0.02;
  double _gyroY = 0.01;
  double _gyroZ = 0.05;

  // Proximity
  bool _isProximityNear = false;
  bool _proximityChanged = false;

  // Ambient light (lux)
  double _ambientLightLux = 320.0;
  bool _ambientLightChanged = false;

  // Movement detection flags
  bool _accelMoved = false;
  bool _gyroMoved = false;

  // Interactive drag / simulation tracking
  double _phoneTiltX = 0.0;
  double _phoneTiltY = 0.0;

  static const MethodChannel _hardwareChannel = MethodChannel('com.tarumt.rebyte/hardware');
  Timer? _liveHardwarePollTimer;

  // Baseline and previous readings to detect real delta movement
  double? _baselineAccelX;
  double? _baselineAccelY;
  double? _baselineAccelZ;
  double? _baselineGyroX;
  double? _baselineGyroY;
  double? _baselineGyroZ;
  double? _baselineProximity;
  double? _baselineLightLux;

  @override
  void initState() {
    super.initState();
    _startNativeSensors();
  }

  @override
  void dispose() {
    _liveHardwarePollTimer?.cancel();
    _hardwareChannel.invokeMethod('stopSensors').catchError((_) {});
    super.dispose();
  }

  Future<void> _startNativeSensors() async {
    try {
      await _hardwareChannel.invokeMethod('startSensors');
    } catch (_) {}

    _liveHardwarePollTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!mounted) return;
      try {
        final Map<dynamic, dynamic>? data =
            await _hardwareChannel.invokeMethod<Map<dynamic, dynamic>>('getSensorReadings');

        if (data != null && mounted) {
          final int accelCount = (data['accelCount'] as num?)?.toInt() ?? 0;
          final int gyroCount = (data['gyroCount'] as num?)?.toInt() ?? 0;
          final int proxCount = (data['proximityCount'] as num?)?.toInt() ?? 0;
          final int lightCount = (data['lightCount'] as num?)?.toInt() ?? 0;

          final double curAccelX = (data['accelX'] as num?)?.toDouble() ?? 0.0;
          final double curAccelY = (data['accelY'] as num?)?.toDouble() ?? 0.0;
          final double curAccelZ = (data['accelZ'] as num?)?.toDouble() ?? 9.8;

          final double curGyroX = (data['gyroX'] as num?)?.toDouble() ?? 0.0;
          final double curGyroY = (data['gyroY'] as num?)?.toDouble() ?? 0.0;
          final double curGyroZ = (data['gyroZ'] as num?)?.toDouble() ?? 0.0;

          final double curProx = (data['proximityDistance'] as num?)?.toDouble() ?? -1;
          final double curProxMax = (data['proximityMaxRange'] as num?)?.toDouble() ?? 5.0;
          final double curLight = (data['lightLux'] as num?)?.toDouble() ?? -1;

          // 1. Accelerometer motion check: user actively tilts phone (delta >= 4.0 m/s^2 from baseline)
          if (accelCount > 0) {
            _baselineAccelX ??= curAccelX;
            _baselineAccelY ??= curAccelY;
            _baselineAccelZ ??= curAccelZ;

            final double deltaAccel = (curAccelX - _baselineAccelX!).abs() +
                (curAccelY - _baselineAccelY!).abs() +
                (curAccelZ - _baselineAccelZ!).abs();

            if (deltaAccel >= 4.0) {
              _accelMoved = true;
            }
          }

          // 2. Gyroscope rotation check: user actively rotates phone (delta >= 1.5 rad/s from baseline)
          if (gyroCount > 0) {
            _baselineGyroX ??= curGyroX;
            _baselineGyroY ??= curGyroY;
            _baselineGyroZ ??= curGyroZ;

            final double deltaGyro = (curGyroX - _baselineGyroX!).abs() +
                (curGyroY - _baselineGyroY!).abs() +
                (curGyroZ - _baselineGyroZ!).abs();

            if (deltaGyro >= 1.5) {
              _gyroMoved = true;
            }
          }

          // 3. Proximity sensor: user covers top
          if (curProx >= 0 && proxCount > 0) {
            final bool near = curProx < curProxMax && curProx < 3.0;
            _baselineProximity ??= curProx;
            // Passed only when a true transition occurs (e.g. going from FAR to NEAR or distance shifting)
            if ((_baselineProximity! - curProx).abs() >= 1.5 || (near && _baselineProximity! >= 3.0)) {
              _proximityChanged = true;
            }
            _isProximityNear = near;
          }

          // 4. Ambient light sensor: higher threshold (diff >= 70 lux or >= 65% drop/rise with min 30 lux)
          if (curLight >= 0 && lightCount > 0) {
            _baselineLightLux ??= curLight;
            final double luxDiff = (curLight - _baselineLightLux!).abs();
            final double luxRatio = _baselineLightLux! > 0 ? (luxDiff / _baselineLightLux!) : 0.0;
            if (luxDiff >= 70.0 || (luxRatio >= 0.65 && luxDiff >= 30.0)) {
              _ambientLightChanged = true;
            }
            _ambientLightLux = curLight;
          }

          setState(() {
            _accelX = curAccelX;
            _accelY = curAccelY;
            _accelZ = curAccelZ;

            _gyroX = curGyroX;
            _gyroY = curGyroY;
            _gyroZ = curGyroZ;

            _phoneTiltX = (curAccelX / 9.8).clamp(-1.0, 1.0);
            _phoneTiltY = (-curAccelY / 9.8).clamp(-1.0, 1.0);
          });
        }
      } catch (_) {}
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _phoneTiltX = (_phoneTiltX + details.delta.dx / 100).clamp(-1.0, 1.0);
      _phoneTiltY = (_phoneTiltY + details.delta.dy / 100).clamp(-1.0, 1.0);
      _accelMoved = true;
      _gyroMoved = true;
      _gyroX = double.parse((details.delta.dx * 0.1).toStringAsFixed(2));
      _gyroY = double.parse((details.delta.dy * 0.1).toStringAsFixed(2));
      _gyroZ = 0.85;
    });
  }

  void _toggleProximity() {
    setState(() {
      _isProximityNear = !_isProximityNear;
      _proximityChanged = true;
    });
  }

  void _toggleLightSensor() {
    setState(() {
      if (_ambientLightLux > 100) {
        _ambientLightLux = 15.0; // Covered
      } else {
        _ambientLightLux = 380.0; // Exposed to light
      }
      _ambientLightChanged = true;
    });
  }

  Future<void> _onNextTest() async {
    // Scoring based on user specification:
    // Accelerometer: Fail -> 30% deduction
    // Gyroscope: Fail -> 25% deduction
    // Proximity: Fail -> 25% deduction
    // Ambient Light: Fail -> 20% deduction
    // Total = 100%
    int deductions = 0;
    if (!_accelMoved) deductions += 30;
    if (!_gyroMoved) deductions += 25;
    if (!_proximityChanged) deductions += 25;
    if (!_ambientLightChanged) deductions += 20;

    final int sensorScore = (100 - deductions).clamp(0, 100);

    await showDialog(
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
                        sensorScore == 100
                            ? Icons.check_circle_rounded
                            : (sensorScore >= 50
                                ? Icons.info_outline_rounded
                                : (sensorScore >= 1 ? Icons.warning_amber_rounded : Icons.cancel_rounded)),
                        color: sensorScore == 100
                            ? const Color(0xFF16A34A)
                            : (sensorScore >= 50
                                ? const Color(0xFF0C5AD2)
                                : (sensorScore >= 1 ? const Color(0xFFD97706) : const Color(0xFFE11D48))),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Score: $sensorScore/100',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  if (sensorScore != 100)
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '• Accelerometer: ${_accelMoved ? "PASS" : "FAIL"}\n'
                '• Gyroscope: ${_gyroMoved ? "PASS" : "FAIL"}\n'
                '• Proximity Sensor: ${_proximityChanged ? "PASS" : "FAIL"}\n'
                '• Ambient Light Sensor: ${_ambientLightChanged ? "PASS" : "FAIL"}',
                textAlign: TextAlign.justify,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  if (sensorScore != 100) ...[
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
                            builder: (context) => NetworkTestPage(
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
                              sensorScore: sensorScore,
                              isTouchSkipped: widget.isTouchSkipped,
                              isDisplaySkipped: widget.isDisplaySkipped,
                              isCameraSkipped: widget.isCameraSkipped,
                              isMicSkipped: widget.isMicSkipped,
                              isSpeakerSkipped: widget.isSpeakerSkipped,
                              isSensorSkipped: false,
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
                children: [
                  Icon(
                    Icons.skip_next_rounded,
                    color: Color(0xFFF59E0B),
                    size: 24,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Skip Sensor Test?',
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
                        backgroundColor: const Color(0xFF0C5AD2),
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
          builder: (context) => NetworkTestPage(
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
            sensorScore: 0,
            isTouchSkipped: widget.isTouchSkipped,
            isDisplaySkipped: widget.isDisplaySkipped,
            isCameraSkipped: widget.isCameraSkipped,
            isMicSkipped: widget.isMicSkipped,
            isSpeakerSkipped: widget.isSpeakerSkipped,
            isSensorSkipped: true,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Exit Sensor Test?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Are you sure you want to exit the Sensor test? Your current progress will be lost.',
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _showExitConfirmationDialog();
        if (shouldExit && mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              // Header Row (Back, Skip, 6/8 indicator)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
                      onPressed: () async {
                        final shouldExit = await _showExitConfirmationDialog();
                        if (shouldExit && mounted) {
                          Navigator.pop(context);
                        }
                      },
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
                        '6/8',
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

              // Title & Instruction
              const SizedBox(height: 4),
              const Text(
                'Sensor Test',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F254B),
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Tilt your device and cover the top sensor.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Scrollable Sensor Cards
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      // Card 1: Accelerometer & Gyroscope
                      _buildAccelerometerCard(),
                      const SizedBox(height: 16),

                      // Card 2: Proximity Sensor
                      _buildProximityCard(),
                      const SizedBox(height: 16),

                      // Card 3: Ambient Light Sensor
                      _buildAmbientLightCard(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // Bottom CTA Button: Next Test
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _onNextTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0848AA),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Done & Next Test',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
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

  Widget _buildAccelerometerCard() {
    final bool isPassed = _accelMoved && _gyroMoved;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row with Pending/Passed pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.screen_rotation_outlined, color: Color(0xFF0848AA), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Accelerometer & Gyro',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F254B),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPassed ? const Color(0xFFDCFCE7) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPassed ? Icons.check_circle : Icons.pending_outlined,
                      size: 13,
                      color: isPassed ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isPassed ? 'Passed' : 'Pending',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isPassed ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Interactive 3D phone graphic with tilt bubble
          GestureDetector(
            onPanUpdate: _onPanUpdate,
            child: Container(
              height: 170,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.002)
                    ..rotateX(-_phoneTiltY * 0.4)
                    ..rotateY(_phoneTiltX * 0.4),
                  child: Container(
                    width: 86,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF0848AA), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0848AA).withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF0848AA), width: 1.2),
                        ),
                        child: Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF0848AA),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Axis readout boxes for Accelerometer
          Row(
            children: [
              Expanded(
                child: _buildAxisPill('X-AXIS', _accelX.toStringAsFixed(2)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAxisPill('Y-AXIS', _accelY.toStringAsFixed(2)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAxisPill('Z-AXIS', _accelZ.toStringAsFixed(2)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Gyroscope Angular Velocity Readouts
          Row(
            children: [
              Expanded(
                child: _buildAxisPill('GYRO-X', '${_gyroX.toStringAsFixed(2)} rad/s'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAxisPill('GYRO-Y', '${_gyroY.toStringAsFixed(2)} rad/s'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAxisPill('GYRO-Z', '${_gyroZ.toStringAsFixed(2)} rad/s'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProximityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row with status pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.sensors, color: Color(0xFF0848AA), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Proximity',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F254B),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _proximityChanged ? const Color(0xFFDCFCE7) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      _proximityChanged ? Icons.check_circle : Icons.pending_outlined,
                      size: 13,
                      color: _proximityChanged ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _proximityChanged ? 'Passed' : 'Pending',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _proximityChanged ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Interactive Hover Hand Area
          GestureDetector(
            onTap: _toggleProximity,
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: _isProximityNear ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isProximityNear ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isProximityNear ? 'Sensor Covered (NEAR)' : 'Hover hand over top of screen',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _isProximityNear ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isProximityNear ? const Color(0xFF2563EB) : const Color(0xFFDCE7F5),
                    ),
                    child: Icon(
                      _isProximityNear ? Icons.front_hand : Icons.touch_app,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientLightCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row with status pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.light_mode_outlined, color: Color(0xFF0848AA), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Ambient Light Sensor',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F254B),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _ambientLightChanged ? const Color(0xFFDCFCE7) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      _ambientLightChanged ? Icons.check_circle : Icons.pending_outlined,
                      size: 13,
                      color: _ambientLightChanged ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _ambientLightChanged ? 'Passed' : 'Pending',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _ambientLightChanged ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Interactive Light toggle area
          GestureDetector(
            onTap: _toggleLightSensor,
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tap to simulate cover / room light',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_ambientLightLux.toStringAsFixed(0)} Lux (${_ambientLightLux < 50 ? "Dark" : "Bright"})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F254B),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _ambientLightLux > 100 ? const Color(0xFFF59E0B) : const Color(0xFF475569),
                    ),
                    child: Icon(
                      _ambientLightLux > 100 ? Icons.wb_sunny : Icons.nightlight_round,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAxisPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0848AA),
            ),
          ),
        ],
      ),
    );
  }
}
