import 'package:flutter/material.dart';
import 'models/device_model.dart';
import 'assessment_result_page.dart';
import 'services/trade_in_service.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';

class DeviceAssessmentLoadingPage extends StatefulWidget {
  final DeviceModel device;
  final String tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final bool fromMyTradeInRequests;

  const DeviceAssessmentLoadingPage({
    super.key,
    required this.device,
    required this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
    this.fromMyTradeInRequests = false,
  });

  @override
  State<DeviceAssessmentLoadingPage> createState() =>
      _DeviceAssessmentLoadingPageState();
}

class _DeviceAssessmentLoadingPageState extends State<DeviceAssessmentLoadingPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late AnimationController _rotationController;

  // 0: validating, 1: analysing images, 2: detecting defects, 3: generating score, 4: all done
  int _completedStepIndex = 0;
  String? _assessmentError;
  bool _isProcessing = false;

  final List<Map<String, dynamic>> _steps = [
    {
      'title': 'Validating device',
      'subtitle': null,
      'icon': Icons.check_rounded,
    },
    {
      'title': 'Analysing images',
      'subtitle': null,
      'icon': Icons.check_rounded,
    },
    {
      'title': 'Detecting visible defects',
      'subtitle': 'Estimated a few minutes; time depends on photo count.',
      'icon': Icons.sync,
    },
    {
      'title': 'Generating condition score',
      'subtitle': null,
      'icon': Icons.query_stats_rounded,
    },
  ];

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _runAssessment();
  }

  Future<void> _runAssessment() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _assessmentError = null;
      _completedStepIndex = 2;
    });

    final result = await TradeInService.runDeviceAssessment(widget.tradeInRequestID);
    if (!mounted) return;
    if (result['success'] != true) {
      setState(() {
        _isProcessing = false;
        _assessmentError = result['message']?.toString() ?? 'Device assessment failed. Please try again.';
      });
      return;
    }

    setState(() {
      _isProcessing = false;
      _completedStepIndex = 4;
    });
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => AssessmentResultPage(
          device: widget.device,
          tradeInRequestID: widget.tradeInRequestID,
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
          fromMyTradeInRequests: widget.fromMyTradeInRequests,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: ReByteAppBar(scaffoldKey: _scaffoldKey),
      drawer: ReByteDrawer(
        isLoggedIn: widget.isLoggedIn,
        email: widget.email,
        name: widget.name,
        selectedIndex: 2,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                // Outer animating concentric radar circles
                _buildRadarLoader(),
                const SizedBox(height: 28),

                // Title
                const Text(
                  'Assessing Device',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                const Text(
                  'Please wait while our AI analyzes your\ndevice condition.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF64748B),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 36),

                // 5 Pipeline steps list
                _buildStepsList(),
                if (_assessmentError != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _assessmentError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFB42318), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _runAssessment,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try assessment again'),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: 2,
      ),
    );
  }

  Widget _buildRadarLoader() {
    return Center(
      child: SizedBox(
        width: 140,
        height: 140,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outermost rotating dashed arc ring
            RotationTransition(
              turns: _rotationController,
              child: SizedBox(
                width: 140,
                height: 140,
                child: CircularProgressIndicator(
                  value: 0.72,
                  strokeWidth: 3.5,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0C5AD2)),
                  backgroundColor: const Color(0xFF0C5AD2).withValues(alpha: 0.12),
                ),
              ),
            ),
            // Middle circle border
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF0C5AD2).withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
            ),
            // Inner circle with processor chip icon
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.memory_rounded,
                  color: Color(0xFF0C5AD2),
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsList() {
    return Column(
      children: List.generate(_steps.length, (index) {
        final step = _steps[index];
        final bool isCompleted = index < _completedStepIndex;
        final bool isCurrent = index == _completedStepIndex;
        final bool isPending = index > _completedStepIndex;
        final bool isLast = index == _steps.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon with vertical connector line
              Column(
                children: [
                  _buildStepNode(isCompleted, isCurrent, isPending, step),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: isCompleted
                            ? const Color(0xFF10B981)
                            : (isCurrent
                                ? const Color(0xFF0C5AD2)
                                : const Color(0xFFE2E8F0)),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),

              // Title and Subtitle text
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: isLast ? 0 : 22,
                    top: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step['title'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: (isCompleted || isCurrent)
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isCompleted
                              ? const Color(0xFF1E293B)
                              : (isCurrent
                                  ? const Color(0xFF0C5AD2)
                                  : const Color(0xFF94A3B8)),
                        ),
                      ),
                      if (step['subtitle'] != null && isCurrent) ...[
                        const SizedBox(height: 3),
                        Text(
                          step['subtitle'] as String,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStepNode(
    bool isCompleted,
    bool isCurrent,
    bool isPending,
    Map<String, dynamic> step,
  ) {
    if (isCompleted) {
      // Completed green checkmark circle
      return Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Color(0xFF10B981),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Icon(
            Icons.check_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      );
    } else if (isCurrent) {
      // Active blue spinning / loader node
      return Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Color(0xFF0C5AD2),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    } else {
      // Pending gray node with icon
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFCBD5E1),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Icon(
            step['icon'] as IconData,
            color: const Color(0xFF94A3B8),
            size: 18,
          ),
        ),
      );
    }
  }
}
