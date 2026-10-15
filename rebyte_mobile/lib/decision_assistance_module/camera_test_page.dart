import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../device_tradein_module/models/device_model.dart';
import 'microphone_test_page.dart';

class CameraTestPage extends StatefulWidget {
  final DeviceModel? device;
  final String? tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final int touchScore;
  final int displayScore;
  final bool isTouchSkipped;
  final bool isDisplaySkipped;

  const CameraTestPage({
    super.key,
    this.device,
    this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
    required this.touchScore,
    required this.displayScore,
    this.isTouchSkipped = false,
    this.isDisplaySkipped = false,
  });

  @override
  State<CameraTestPage> createState() => _CameraTestPageState();
}

class _CameraTestPageState extends State<CameraTestPage> {
  final ImagePicker _picker = ImagePicker();

  XFile? _rearPhoto;
  XFile? _frontPhoto;

  // Question options & severity scores:
  // Blurry Image / Cannot Focus: 20
  // Partially Black / Obstructed Image: 25
  // Abnormal Color / Discoloration: 15
  // Option severity marks:
  // 1. Blurry Image / Cannot Focus: 30
  // 2. Partially Black / Obstructed Image: 35
  // 3. Abnormal Color / Discoloration: 20
  // 4. Spots / Lines in Image: 15
  // 5. Camera Not Working / Blank Image: 100
  static const int _cameraMaxSeverity = 100;

  static const String _blankImageOption = 'Camera Not Working / Blank Image';

  final List<Map<String, dynamic>> _issueOptions = [
    {
      'title': 'Blurry Image / Cannot Focus',
      'score': 30,
      'desc': 'Image is out of focus, hazy, or unable to lock onto subjects properly.',
    },
    {
      'title': 'Partially Black / Obstructed Image',
      'score': 35,
      'desc': 'Dark corners, vignetting, or parts of the sensor view blocked or obstructed.',
    },
    {
      'title': 'Abnormal Color / Discoloration',
      'score': 20,
      'desc': 'Severe pink/green color cast, washed out hues, or unnatural tint.',
    },
    {
      'title': 'Spots / Lines in Image',
      'score': 15,
      'desc': 'Dust spots on the internal sensor, dead sensor pixels, or laser burn lines.',
    },
    {
      'title': 'Camera Not Working / Blank Image',
      'score': 100,
      'desc': 'Total black output, shutter failed to trigger, or camera module error.',
    },
  ];

  // Stage 0: Initial camera test page (Take rear & front photo)
  // Stage 1: Review & defect questionnaire (like display test: Has issue or not?)
  int _currentStage = 0;

  // Defect selection states
  bool? _rearHasIssue; // true: Has issue, false: Clear / Perfect
  final Set<String> _rearSelectedIssues = {};

  bool? _frontHasIssue; // true: Has issue, false: Clear / Perfect
  final Set<String> _frontSelectedIssues = {};

  Future<void> _capturePhoto({required bool isFront}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: isFront ? CameraDevice.front : CameraDevice.rear,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          if (isFront) {
            _frontPhoto = image;
          } else {
            _rearPhoto = image;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open camera: $e'),
            backgroundColor: const Color(0xFFE11D48),
          ),
        );
      }
    }
  }

  // Calculate Camera Score:
  // Rear camera is 60%
  // Front camera is 40%
  // Each camera score = ((100 - gainedSeverity) / 100) * 100 = 100 - gainedSeverity
  int _calculateCameraScore({required bool isSkipped}) {
    if (isSkipped) return 0;

    int rearSeverity = 0;
    if (_rearHasIssue == true) {
      for (final opt in _issueOptions) {
        if (_rearSelectedIssues.contains(opt['title'])) {
          rearSeverity += (opt['score'] as int? ?? 0);
        }
      }
    }
    final int rearScore = (_cameraMaxSeverity - rearSeverity).clamp(0, 100);

    int frontSeverity = 0;
    if (_frontHasIssue == true) {
      for (final opt in _issueOptions) {
        if (_frontSelectedIssues.contains(opt['title'])) {
          frontSeverity += (opt['score'] as int? ?? 0);
        }
      }
    }
    final int frontScore = (_cameraMaxSeverity - frontSeverity).clamp(0, 100);

    // Rear 60%, Front 40%
    final double finalScore = (rearScore * 0.60) + (frontScore * 0.40);
    return finalScore.round().clamp(0, 100);
  }

  void _onCompleteTest({bool isSkipped = false}) {
    final int cameraScore = _calculateCameraScore(isSkipped: isSkipped);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSkipped
                            ? Icons.skip_next_rounded
                            : (cameraScore == 100
                                ? Icons.check_circle_rounded
                                : (cameraScore >= 50
                                    ? Icons.info_outline_rounded
                                    : (cameraScore >= 1 ? Icons.warning_amber_rounded : Icons.cancel_rounded))),
                        color: isSkipped
                            ? const Color(0xFFF59E0B)
                            : (cameraScore == 100
                                ? const Color(0xFF16A34A)
                                : (cameraScore >= 50
                                    ? const Color(0xFF0C5AD2)
                                    : (cameraScore >= 1 ? const Color(0xFFD97706) : const Color(0xFFE11D48)))),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isSkipped ? 'Test Skipped' : 'Score: $cameraScore/100',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  if (cameraScore != 100)
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isSkipped
                    ? 'You chose to skip the Camera test. This test will be recorded as skipped.'
                    : (cameraScore == 100
                        ? 'Camera check completed! Both front and rear lenses are clear and defect-free with perfect condition (Score: 100/100).'
                        : 'Camera test evaluation completed. Camera quality evaluation result: $cameraScore/100.'),
                textAlign: TextAlign.justify,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  if (cameraScore != 100) ...[
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
                        Navigator.pop(context); // Close dialog
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MicrophoneTestPage(
                              device: widget.device,
                              tradeInRequestID: widget.tradeInRequestID,
                              isLoggedIn: widget.isLoggedIn,
                              email: widget.email,
                              name: widget.name,
                              touchScore: widget.touchScore,
                              displayScore: widget.displayScore,
                              cameraScore: cameraScore,
                              isTouchSkipped: widget.isTouchSkipped,
                              isDisplaySkipped: widget.isDisplaySkipped,
                              isCameraSkipped: isSkipped,
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
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.skip_next_rounded, color: Color(0xFFF59E0B), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Skip Camera Test?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
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
          builder: (context) => MicrophoneTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: widget.touchScore,
            displayScore: widget.displayScore,
            cameraScore: 0,
            isTouchSkipped: widget.isTouchSkipped,
            isDisplaySkipped: widget.isDisplaySkipped,
            isCameraSkipped: true,
          ),
        ),
      );
    }
  }

  Future<void> _handleBack() async {
    final bool? confirmExit = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    'Exit Camera Test?',
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
                'Are you sure you want to exit the Camera test? Your current progress will be lost.',
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

    if (confirmExit == true && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStage != 0) {
          setState(() => _currentStage = 0);
        } else {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: _currentStage == 0 ? _buildCaptureScreen() : _buildQuestionnaireScreen(),
        ),
      ),
    );
  }

  // Stage 0: Take Photo Screen
  Widget _buildCaptureScreen() {
    final bool bothCaptured = _rearPhoto != null && _frontPhoto != null;

    return Column(
      children: [
        // Top Navigation Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                  '3/8',
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

        // Title and Instructions
        const Text(
          'Camera Test',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F254B),
          ),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.0),
          child: Text(
            'Capture a clear photo using both cameras to verify lens clarity.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Camera Cards
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _buildCameraCard(
                  title: 'Rear Camera',
                  icon: Icons.camera_alt_rounded,
                  photo: _rearPhoto,
                  isFront: false,
                ),
                const SizedBox(height: 16),
                _buildCameraCard(
                  title: 'Front Camera',
                  icon: Icons.person_rounded,
                  photo: _frontPhoto,
                  isFront: true,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // Bottom Done / Continue Button
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
              onPressed: bothCaptured ? () => setState(() => _currentStage = 1) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0C5AD2),
                disabledBackgroundColor: const Color(0xFFE2E8F0),
                foregroundColor: Colors.white,
                disabledForegroundColor: const Color(0xFF94A3B8),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'Inspect Camera Quality',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraCard({
    required String title,
    required IconData icon,
    required XFile? photo,
    required bool isFront,
  }) {
    final bool isCaptured = photo != null;

    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header inside card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: const Color(0xFF0F254B)),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
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
                    color: isCaptured ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCaptured ? Icons.check_circle_rounded : Icons.pending_rounded,
                        size: 13,
                        color: isCaptured ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isCaptured ? 'CAPTURED' : 'PENDING',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isCaptured ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Image preview or placeholder
          Container(
            height: 180,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            clipBehavior: Clip.antiAlias,
            child: isCaptured
                ? Image.file(
                    File(photo.path),
                    fit: BoxFit.cover,
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 48, color: const Color(0xFF94A3B8)),
                        const SizedBox(height: 8),
                        Text(
                          'No photo captured for $title',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),

          // Action Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                onPressed: () => _capturePhoto(isFront: isFront),
                icon: Icon(
                  isCaptured ? Icons.refresh_rounded : Icons.camera_alt_outlined,
                  size: 18,
                ),
                label: Text(
                  isCaptured ? 'Retake Photo' : 'Take Photo',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCaptured ? const Color(0xFFEFF6FF) : const Color(0xFF0C5AD2),
                  foregroundColor: isCaptured ? const Color(0xFF0C5AD2) : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // Stage 1: Questionnaire Screen (Ask like display: Have issue or not?)
  Widget _buildQuestionnaireScreen() {
    // Both cameras must have their issue status specified
    // If has issue == true, at least one defect option must be selected
    final bool rearValid = _rearHasIssue == false ||
        (_rearHasIssue == true && _rearSelectedIssues.isNotEmpty);
    final bool frontValid = _frontHasIssue == false ||
        (_frontHasIssue == true && _frontSelectedIssues.isNotEmpty);
    final bool canSubmit = (_rearHasIssue != null) && (_frontHasIssue != null) && rearValid && frontValid;

    return Column(
      children: [
        // Top Navigation Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                onPressed: () => setState(() => _currentStage = 0),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Quality Check',
                  style: TextStyle(
                    color: Color(0xFF0C5AD2),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),

        const Text(
          'Camera Quality Inspection',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F254B),
          ),
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            'Review your photos. Did you notice any visual defect or hardware issue on either camera?',
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
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // QUESTION 1: REAR CAMERA
                _buildCameraQuestionSection(
                  cameraName: 'Rear Camera (Back)',
                  hasIssue: _rearHasIssue,
                  selectedIssues: _rearSelectedIssues,
                  onSelectStatus: (val) {
                    setState(() {
                      _rearHasIssue = val;
                      if (!val) _rearSelectedIssues.clear();
                    });
                  },
                  onToggleIssue: (title) {
                    setState(() {
                      if (_rearSelectedIssues.contains(title)) {
                        _rearSelectedIssues.remove(title);
                      } else {
                        _rearSelectedIssues.add(title);
                      }
                    });
                  },
                ),
                const SizedBox(height: 24),

                // QUESTION 2: FRONT CAMERA
                _buildCameraQuestionSection(
                  cameraName: 'Front Camera (Selfie)',
                  hasIssue: _frontHasIssue,
                  selectedIssues: _frontSelectedIssues,
                  onSelectStatus: (val) {
                    setState(() {
                      _frontHasIssue = val;
                      if (!val) _frontSelectedIssues.clear();
                    });
                  },
                  onToggleIssue: (title) {
                    setState(() {
                      if (_frontSelectedIssues.contains(title)) {
                        _frontSelectedIssues.remove(title);
                      } else {
                        _frontSelectedIssues.add(title);
                      }
                    });
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // Bottom Submission Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!canSubmit) ...[
                const Padding(
                  padding: EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'Please answer both camera quality questions to finish.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: canSubmit ? () => _onCompleteTest() : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'Done & Next Test',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraQuestionSection({
    required String cameraName,
    required bool? hasIssue,
    required Set<String> selectedIssues,
    required ValueChanged<bool> onSelectStatus,
    required ValueChanged<String> onToggleIssue,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cameraName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F254B),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Did you notice any defect or issue in the photo taken?',
            style: TextStyle(
              fontSize: 12.5,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),

          // Two Choice Buttons: Perfect / Clear vs Has Issue
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => onSelectStatus(false),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: hasIssue == false ? const Color(0xFFDCFCE7) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasIssue == false ? const Color(0xFF16A34A) : const Color(0xFFCBD5E1),
                        width: hasIssue == false ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: hasIssue == false ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'No, Clear',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: hasIssue == false ? const Color(0xFF15803D) : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => onSelectStatus(true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: hasIssue == true ? const Color(0xFFFEE2E2) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasIssue == true ? const Color(0xFFDC2626) : const Color(0xFFCBD5E1),
                        width: hasIssue == true ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.report_problem_rounded,
                          size: 16,
                          color: hasIssue == true ? const Color(0xFFDC2626) : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Yes, Has Issue',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: hasIssue == true ? const Color(0xFFB91C1C) : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // If Has Issue selected, show defect options
          if (hasIssue == true) ...[
            const SizedBox(height: 16),
            const Text(
              'Select issues noticed (Select all that apply):',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F254B),
              ),
            ),
            const SizedBox(height: 8),
            ..._issueOptions.map((opt) {
              final String title = opt['title'] as String;
              final String desc = opt['desc'] as String;
              final bool isSelected = selectedIssues.contains(title);

              final bool hasAnyPartialIssue = selectedIssues.any((t) => t != _blankImageOption);
              final bool hasBlankImage = selectedIssues.contains(_blankImageOption);

              final bool isBlankOption = title == _blankImageOption;
              final bool isDisabled = isBlankOption ? hasAnyPartialIssue : hasBlankImage;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Opacity(
                  opacity: isDisabled ? 0.45 : 1.0,
                  child: InkWell(
                    onTap: isDisabled ? null : () => onToggleIssue(title),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFF1F5F9)
                            : (isDisabled ? const Color(0xFFF8FAFC) : Colors.white),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF0C5AD2)
                              : (isDisabled ? const Color(0xFFE2E8F0) : const Color(0xFFCBD5E1)),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            size: 18,
                            color: isSelected
                                ? const Color(0xFF0C5AD2)
                                : (isDisabled ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                    color: isDisabled ? const Color(0xFF94A3B8) : const Color(0xFF0F254B),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  desc,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDisabled ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
