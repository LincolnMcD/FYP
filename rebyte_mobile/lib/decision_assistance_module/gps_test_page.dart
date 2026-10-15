import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../device_tradein_module/models/device_model.dart';
import 'diagnostic_result_page.dart';

enum GpsTestStatus { notTested, testing, pass, fail }

class GpsTestPage extends StatefulWidget {
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
  final int networkScore;
  final bool isTouchSkipped;
  final bool isDisplaySkipped;
  final bool isCameraSkipped;
  final bool isMicSkipped;
  final bool isSpeakerSkipped;
  final bool isSensorSkipped;
  final bool isNetworkSkipped;

  const GpsTestPage({
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
    required this.networkScore,
    this.isTouchSkipped = false,
    this.isDisplaySkipped = false,
    this.isCameraSkipped = false,
    this.isMicSkipped = false,
    this.isSpeakerSkipped = false,
    this.isSensorSkipped = false,
    this.isNetworkSkipped = false,
  });

  @override
  State<GpsTestPage> createState() => _GpsTestPageState();
}

class _GpsTestPageState extends State<GpsTestPage> {
  static const MethodChannel _hardwareChannel = MethodChannel('com.tarumt.rebyte/hardware');

  // Sub-tests
  // Test 1: Location Detection (40%)
  GpsTestStatus _detectionStatus = GpsTestStatus.notTested;
  String _detectionMessage = 'Not tested yet. Move outdoors to acquire high-accuracy location.';

  // Test 2: Location Accuracy (35%)
  GpsTestStatus _accuracyStatus = GpsTestStatus.notTested;
  String _accuracyMessage = 'Not evaluated. Requires fresh location lock first.';
  double _reportedAccuracyMeters = 0.0;

  // Test 3: Location Stability (25%)
  GpsTestStatus _stabilityStatus = GpsTestStatus.notTested;
  String _stabilityMessage = 'Not evaluated. Requires stationary readings over 30s.';
  double _maxDeviationMeters = 0.0;

  // Live Location Data
  double _latitude = 0.0;
  double _longitude = 0.0;
  bool _hasLock = false;

  Timer? _gpsMonitorTimer;
  Timer? _stabilitySampleTimer;
  final List<double> _stabilityLats = [];
  final List<double> _stabilityLngs = [];

  // GPS Scoring
  // Location Detection: 40%
  // Location Accuracy: 35%
  // Location Stability: 25%
  int get gpsSeverity {
    int deduction = 0;
    if (_detectionStatus != GpsTestStatus.pass) deduction += 40;
    if (_accuracyStatus != GpsTestStatus.pass) deduction += 35;
    if (_stabilityStatus != GpsTestStatus.pass) deduction += 25;
    return deduction;
  }

  int get gpsPerformance => (100 - gpsSeverity).clamp(0, 100);

  double get gpsContribution => 5.0 * (gpsPerformance / 100.0);

  @override
  void dispose() {
    _gpsMonitorTimer?.cancel();
    _stabilitySampleTimer?.cancel();
    _hardwareChannel.invokeMethod('stopGps').catchError((_) {});
    super.dispose();
  }

  // Run Test 1 & 2: Location Detection & Accuracy
  Future<void> _runLocationDetectionTest() async {
    setState(() {
      _detectionStatus = GpsTestStatus.testing;
      _detectionMessage = 'Acquiring high-accuracy location outdoors (up to 30s)...';
    });

    try {
      final bool? granted = await _hardwareChannel.invokeMethod<bool>('requestLocationPermission');
      if (granted == false && mounted) {
        setState(() {
          _detectionStatus = GpsTestStatus.fail;
          _detectionMessage = 'Location permission is required to evaluate GPS. Access was denied.';
        });
        return;
      }
      await _hardwareChannel.invokeMethod('startGps');
    } catch (_) {}

    final startTime = DateTime.now();

    _gpsMonitorTimer?.cancel();
    _gpsMonitorTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final elapsed = DateTime.now().difference(startTime).inSeconds;

      try {
        final Map<dynamic, dynamic>? data =
            await _hardwareChannel.invokeMethod<Map<dynamic, dynamic>>('getGpsData');

        if (data != null && mounted) {
          final bool hasLocation = data['hasLocation'] == true;
          final bool isLocationEnabled = data['isLocationEnabled'] == true;
          final bool hasPerm = data['hasPermission'] == true;

          if (!hasPerm) {
            timer.cancel();
            setState(() {
              _detectionStatus = GpsTestStatus.fail;
              _detectionMessage = 'Location permission denied. GPS evaluation failed.';
            });
            return;
          }

          if (!isLocationEnabled) {
            timer.cancel();
            setState(() {
              _detectionStatus = GpsTestStatus.fail;
              _detectionMessage = 'Location service is disabled in device settings.';
            });
            return;
          }

          if (hasLocation) {
            timer.cancel();
            final double lat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
            final double lng = (data['longitude'] as num?)?.toDouble() ?? 0.0;
            final double acc = (data['accuracy'] as num?)?.toDouble() ?? 10.0;

            setState(() {
              _hasLock = true;
              _latitude = lat;
              _longitude = lng;
              _reportedAccuracyMeters = acc;

              // 1. Detection Evaluation
              if (elapsed <= 30) {
                _detectionStatus = GpsTestStatus.pass;
                _detectionMessage = 'Fresh location obtained in ${elapsed}s (≤ 30s). PASS.';
              } else {
                _detectionStatus = GpsTestStatus.fail;
                _detectionMessage = 'Location lock took ${elapsed}s (> 30s). FAIL.';
              }

              // 2. Accuracy Evaluation
              if (acc <= 20.0) {
                _accuracyStatus = GpsTestStatus.pass;
                _accuracyMessage = 'High accuracy reported: ±${acc.toStringAsFixed(1)} m (≤ 20 m). PASS.';
              } else {
                _accuracyStatus = GpsTestStatus.fail;
                _accuracyMessage = 'Insufficient accuracy: ±${acc.toStringAsFixed(1)} m (> 20 m). FAIL.';
              }
            });
            return;
          }

          // Timeout check
          if (elapsed >= 35) {
            timer.cancel();
            setState(() {
              _detectionStatus = GpsTestStatus.fail;
              _detectionMessage = 'No location acquired within 30s. FAIL.';
            });
          }
        }
      } catch (_) {}
    });
  }

  // Run Test 3: Location Stability
  Future<void> _runLocationStabilityTest() async {
    if (!_hasLock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please acquire Location Detection first.')),
      );
      return;
    }

    setState(() {
      _stabilityStatus = GpsTestStatus.testing;
      _stabilityMessage = 'Place phone stationary. Collecting deviation readings (10s)...';
      _stabilityLats.clear();
      _stabilityLngs.clear();
      _maxDeviationMeters = 0.0;
    });

    int count = 0;
    _stabilitySampleTimer?.cancel();
    _stabilitySampleTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      count++;
      try {
        final Map<dynamic, dynamic>? data =
            await _hardwareChannel.invokeMethod<Map<dynamic, dynamic>>('getGpsData');
        if (data != null && data['hasLocation'] == true) {
          final double lat = (data['latitude'] as num?)?.toDouble() ?? _latitude;
          final double lng = (data['longitude'] as num?)?.toDouble() ?? _longitude;
          _stabilityLats.add(lat);
          _stabilityLngs.add(lng);

          if (_stabilityLats.length >= 2) {
            final double latDelta = (_stabilityLats.reduce((a, b) => a > b ? a : b) -
                    _stabilityLats.reduce((a, b) => a < b ? a : b)) *
                111000.0;
            final double lngDelta = (_stabilityLngs.reduce((a, b) => a > b ? a : b) -
                    _stabilityLngs.reduce((a, b) => a < b ? a : b)) *
                111000.0;
            _maxDeviationMeters = latDelta > lngDelta ? latDelta : lngDelta;
          }
        }
      } catch (_) {}

      if (count >= 10) {
        timer.cancel();
        if (mounted) {
          setState(() {
            if (_maxDeviationMeters <= 20.0) {
              _stabilityStatus = GpsTestStatus.pass;
              _stabilityMessage = 'Stationary readings steady (Max deviation: ${_maxDeviationMeters.toStringAsFixed(1)} m ≤ 20 m). PASS.';
            } else {
              _stabilityStatus = GpsTestStatus.fail;
              _stabilityMessage = 'Repeated deviation ${_maxDeviationMeters.toStringAsFixed(1)} m (> 20 m). FAIL.';
            }
          });
        }
      }
    });
  }


  void _onConfirmLocationData() {
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
                        gpsPerformance == 100
                            ? Icons.check_circle_rounded
                            : (gpsPerformance >= 50
                                ? Icons.info_outline_rounded
                                : (gpsPerformance >= 1 ? Icons.warning_amber_rounded : Icons.cancel_rounded)),
                        color: gpsPerformance == 100
                            ? const Color(0xFF16A34A)
                            : (gpsPerformance >= 50
                                ? const Color(0xFF0C5AD2)
                                : (gpsPerformance >= 1 ? const Color(0xFFD97706) : const Color(0xFFE11D48))),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Score: $gpsPerformance/100',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  if (gpsPerformance != 100)
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                          height: 1.5,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Location Coordinates:',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF475569),
                                height: 1.5,
                              ),
                            ),
                            Text(
                              _latitude != 0.0
                                  ? '(${_latitude.toStringAsFixed(4)}° N, ${_longitude.abs().toStringAsFixed(4)}° W)'
                                  : '(Not locked)',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF475569),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                          height: 1.5,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Location Detection: ${_detectionStatus == GpsTestStatus.pass ? "PASS" : "FAIL"}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF475569),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                          height: 1.5,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Location Accuracy: ${_accuracyStatus == GpsTestStatus.pass ? "PASS" : "FAIL"}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF475569),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                          height: 1.5,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Location Stability: ${_stabilityStatus == GpsTestStatus.pass ? "PASS" : "FAIL"}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF475569),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  if (gpsPerformance != 100) ...[
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
                            builder: (context) => DiagnosticResultPage(
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
                              networkScore: widget.networkScore,
                              gpsScore: gpsPerformance,
                              isTouchSkipped: widget.isTouchSkipped,
                              isDisplaySkipped: widget.isDisplaySkipped,
                              isCameraSkipped: widget.isCameraSkipped,
                              isMicSkipped: widget.isMicSkipped,
                              isSpeakerSkipped: widget.isSpeakerSkipped,
                              isSensorSkipped: widget.isSensorSkipped,
                              isNetworkSkipped: widget.isNetworkSkipped,
                              isGpsSkipped: false,
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
                        'VIEW RESULTS',
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
                    'Skip GPS Test?',
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
          builder: (context) => DiagnosticResultPage(
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
            networkScore: widget.networkScore,
            gpsScore: 0,
            isTouchSkipped: widget.isTouchSkipped,
            isDisplaySkipped: widget.isDisplaySkipped,
            isCameraSkipped: widget.isCameraSkipped,
            isMicSkipped: widget.isMicSkipped,
            isSpeakerSkipped: widget.isSpeakerSkipped,
            isSensorSkipped: widget.isSensorSkipped,
            isNetworkSkipped: widget.isNetworkSkipped,
            isGpsSkipped: true,
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
                'Exit GPS Test?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Are you sure you want to exit the GPS test? Your current progress will be lost.',
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
              // Header Row (Back button, Skip Test button, 8/8 indicator)
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
                        '8/8',
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
                'GPS Test',
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
                  'Tests hardware GNSS/GPS reception, accuracy, and position stability under outdoor conditions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Test 1: Location Detection
                      _buildSubTestCard(
                        title: '1. Location Detection',
                        instruction: 'Move outdoors. Must acquire fresh high-accuracy location within 30s.',
                        status: _detectionStatus,
                        message: _detectionMessage,
                        onStart: _runLocationDetectionTest,
                      ),
                      const SizedBox(height: 12),

                      // Test 2: Location Accuracy
                      _buildSubTestCard(
                        title: '2. Location Accuracy',
                        instruction: 'Evaluates estimated horizontal error radius (PASS ≤ 20 m).',
                        status: _accuracyStatus,
                        message: _accuracyMessage,
                        onStart: _runLocationDetectionTest,
                      ),
                      const SizedBox(height: 12),

                      // Test 3: Location Stability
                      _buildSubTestCard(
                        title: '3. Location Stability',
                        instruction: 'Keep phone stationary. Evaluates drift across readings over time (PASS ≤ 20 m).',
                        status: _stabilityStatus,
                        message: _stabilityMessage,
                        onStart: _runLocationStabilityTest,
                      ),
                    const SizedBox(height: 16),

                    // Live Coordinates Box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.explore_outlined, color: Color(0xFF0848AA), size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CURRENT COORDINATES',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _latitude != 0.0
                                      ? '${_latitude.toStringAsFixed(4)}° N, ${_longitude.abs().toStringAsFixed(4)}° W (±${_reportedAccuracyMeters.toStringAsFixed(1)} m)'
                                      : 'No position fix yet',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F254B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Performance Summary Card
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
                              const Text('Location Detection', style: TextStyle(fontSize: 13, color: Color(0xFF334155))),
                              _buildMiniGpsBadge(_detectionStatus),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Location Accuracy', style: TextStyle(fontSize: 13, color: Color(0xFF334155))),
                              _buildMiniGpsBadge(_accuracyStatus),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Location Stability', style: TextStyle(fontSize: 13, color: Color(0xFF334155))),
                              _buildMiniGpsBadge(_stabilityStatus),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _onConfirmLocationData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0848AA),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Confirm & View Results'),
                    ),
                  ),
                ],
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
    required GpsTestStatus status,
    required String message,
    required VoidCallback onStart,
  }) {
    Color badgeColor;
    String badgeText;
    switch (status) {
      case GpsTestStatus.pass:
        badgeColor = const Color(0xFF16A34A);
        badgeText = 'PASS';
        break;
      case GpsTestStatus.fail:
        badgeColor = const Color(0xFFE11D48);
        badgeText = 'FAIL';
        break;
      case GpsTestStatus.testing:
        badgeColor = const Color(0xFF2563EB);
        badgeText = 'TESTING...';
        break;
      case GpsTestStatus.notTested:
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
                if (status == GpsTestStatus.testing) ...[
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
                      color: status == GpsTestStatus.pass
                          ? const Color(0xFF16A34A)
                          : (status == GpsTestStatus.fail
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
                onPressed: status == GpsTestStatus.testing ? null : onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEFF6FF),
                  foregroundColor: const Color(0xFF0848AA),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: Text(
                  status == GpsTestStatus.notTested ? 'Start Test' : 'Retest',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniGpsBadge(GpsTestStatus status) {
    Color color;
    String text;
    switch (status) {
      case GpsTestStatus.pass:
        color = const Color(0xFF16A34A);
        text = 'PASS';
        break;
      case GpsTestStatus.fail:
        color = const Color(0xFFE11D48);
        text = 'FAIL';
        break;
      case GpsTestStatus.testing:
        color = const Color(0xFF2563EB);
        text = 'TESTING';
        break;
      case GpsTestStatus.notTested:
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
