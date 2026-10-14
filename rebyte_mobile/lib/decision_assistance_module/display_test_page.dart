import 'package:flutter/material.dart';
import '../device_tradein_module/models/device_model.dart';
import 'camera_test_page.dart';

class DisplayTestPage extends StatefulWidget {
  final DeviceModel? device;
  final String? tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final int touchScore;
  final bool isTouchSkipped;

  const DisplayTestPage({
    super.key,
    this.device,
    this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
    this.touchScore = 100,
    this.isTouchSkipped = false,
  });

  @override
  State<DisplayTestPage> createState() => _DisplayTestPageState();
}

class _DisplayTestPageState extends State<DisplayTestPage> {
  // Test stages:
  // 0: Introduction screen ("Tap to cycle colors")
  // 1: Red screen
  // 2: Green screen
  // 3: Blue screen
  // 4: White screen
  // 5: Black screen
  // 6: Evaluation screen (Pass / Fail questions)
  // 7: Defect questionnaire screen (when Fail is tapped)
  int _currentStage = 0;

  final List<Color> _cycleColors = [
    const Color(0xFFFF0000), // Red
    const Color(0xFF00FF00), // Green
    const Color(0xFF0000FF), // Blue
    const Color(0xFFFFFFFF), // White
    const Color(0xFF000000), // Black
  ];

  // Q1: What type of display issue did you notice?
  // Severity score per issue:
  // Dead / Stuck Pixel: 10
  // Vertical / Horizontal Lines: 25
  // Discoloration / Color Tint: 15
  // Uneven Brightness / Dark Spot: 20
  // Screen Flickering: 30
  // Screen Burn-in / Ghost Image: 25
  // Other Display Issue: 15
  final List<Map<String, dynamic>> _q1IssueOptions = [
    {
      'title': 'Dead / Stuck Pixel',
      'score': 10,
      'image': 'assets/images/defect_dead_pixel.jpg',
      'desc': 'Single or multiple isolated dots that stay permanently dark or lit with a fixed color (red/green/blue).'
    },
    {
      'title': 'Vertical / Horizontal Lines',
      'score': 25,
      'image': 'assets/images/defect_lines.jpg',
      'desc': 'Thin or thick straight lines running vertically or horizontally across the display due to digitizer or cable defects.'
    },
    {
      'title': 'Discoloration / Color Tint',
      'score': 15,
      'image': 'assets/images/defect_discoloration.jpg',
      'desc': 'Abnormal yellow, green, or pinkish color cast across portions of the display, especially noticeable on solid white.'
    },
    {
      'title': 'Uneven Brightness / Dark Spot',
      'score': 20,
      'image': 'assets/images/defect_dark_spot.jpg',
      'desc': 'Cloudy dark patches, uneven illumination, or backlight bleeding along screen corners and edges.'
    },
    {
      'title': 'Screen Flickering',
      'score': 30,
      'image': 'assets/images/defect_flickering.jpg',
      'desc': 'Rapid flashing, horizontal jumping scanlines, or fluctuating brightness during normal screen display.'
    },
    {
      'title': 'Screen Burn-in / Ghost Image',
      'score': 25,
      'image': 'assets/images/defect_burnin.jpg',
      'desc': 'Permanent faint shadows or ghosting of navigation bars, keyboards, or app icons visible across different screens.'
    },
    {
      'title': 'Other Display Issue',
      'score': 15,
      'image': null,
      'desc': 'Any other visual irregularity or graphical anomaly not covered in the list above.'
    },
  ];
  final Set<String> _selectedQ1Issues = {};

  // Q2: Where did you notice the issue? (Multiple select)
  // Location -> Severity score
  // Top of screen: 5
  // Center of screen: 10
  // Bottom of screen: 5
  // Left side: 5
  // Right side: 5
  final Map<String, int> _q2ScoreMap = {
    'Top of screen': 5,
    'Center of screen': 10,
    'Bottom of screen': 5,
    'Left side': 5,
    'Right side': 5,
  };
  late final List<String> _q2Options = _q2ScoreMap.keys.toList();
  final Set<String> _selectedQ2Locations = {};

  // Q3: How noticeable is the issue? (Single select)
  // Minor — Barely noticeable: 5
  // Moderate — Clearly visible: 15
  // Severe — Affects normal screen usage: 30
  final Map<String, int> _q3ScoreMap = {
    'Minor — Barely noticeable': 5,
    'Moderate — Clearly visible': 15,
    'Severe — Affects normal screen usage': 30,
  };
  late final List<String> _q3Options = _q3ScoreMap.keys.toList();
  String? _selectedQ3Severity;

  // Maximum possible severity score (all severity marks added together):
  // Q1 all options: 10 + 25 + 15 + 20 + 30 + 25 + 15 = 140
  // Q2 all options: 5 + 10 + 5 + 5 + 5 = 30
  // Q3 all options: 5 + 15 + 30 = 50
  // Total sum of all severity marks = 140 + 30 + 50 = 220
  static const int _maxDisplaySeverityScore = 220;

  int _calculateDisplayScore({required bool isPassed, bool isSkipped = false}) {
    if (isSkipped) return 0;
    if (isPassed) return 100;

    int gainedSeverityMark = 0;

    // Sum gained severity mark for Q1 issues
    for (final opt in _q1IssueOptions) {
      if (_selectedQ1Issues.contains(opt['title'])) {
        gainedSeverityMark += (opt['score'] as int? ?? 15);
      }
    }

    // Sum gained severity mark for Q2 locations
    for (final loc in _selectedQ2Locations) {
      gainedSeverityMark += (_q2ScoreMap[loc] ?? 5);
    }

    // Sum gained severity mark for Q3 severity
    if (_selectedQ3Severity != null) {
      gainedSeverityMark += (_q3ScoreMap[_selectedQ3Severity] ?? 0);
    }

    // Formula: (total - gained severity mark) / total * 100
    final double scoreFraction = (_maxDisplaySeverityScore - gainedSeverityMark) / _maxDisplaySeverityScore;
    final int finalScore = (scoreFraction * 100).round().clamp(0, 100);

    return finalScore;
  }

  void _onTapNextColor() {
    setState(() {
      if (_currentStage < _cycleColors.length) {
        _currentStage++;
      }
    });
  }

  void _onCompleteTest({required bool isPassed, bool isSkipped = false}) {
    final int displayScore = _calculateDisplayScore(isPassed: isPassed, isSkipped: isSkipped);

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
                            : (displayScore >= 80 ? Icons.check_circle_rounded : Icons.assignment_late_rounded),
                        color: isSkipped
                            ? const Color(0xFFF59E0B)
                            : (displayScore >= 80 ? const Color(0xFF16A34A) : const Color(0xFF0C5AD2)),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isSkipped ? 'Test Skipped' : 'Score: $displayScore/100',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  if (displayScore < 100)
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isSkipped
                    ? 'You chose to skip the Display test. This test will be recorded as skipped.'
                    : (displayScore == 100
                        ? 'Display check completed! Screen is uniform and defect-free with perfect condition (Score: 100/100).'
                        : 'Display test evaluation completed. Defect severity evaluation result: $displayScore/100.'),
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
                  // For success pop-up (displayScore == 100), no need RETRY button
                  if (displayScore < 100) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context); // Close dialog
                          setState(() {
                            _currentStage = 0; // Restart test
                            _selectedQ1Issues.clear();
                            _selectedQ2Locations.clear();
                            _selectedQ3Severity = null;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        child: const Text(
                          'RETRY',
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
                        // Navigate to Test 3: CameraTestPage
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CameraTestPage(
                              device: widget.device,
                              tradeInRequestID: widget.tradeInRequestID,
                              isLoggedIn: widget.isLoggedIn,
                              email: widget.email,
                              name: widget.name,
                              touchScore: widget.touchScore,
                              displayScore: displayScore,
                              isTouchSkipped: widget.isTouchSkipped,
                              isDisplaySkipped: isSkipped,
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

  void _onSkip() async {
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        'Skip Display Test?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
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
      // Directly proceed to CameraTestPage without a second pop-up
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => CameraTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: widget.touchScore,
            displayScore: 0,
            isTouchSkipped: widget.isTouchSkipped,
            isDisplaySkipped: true,
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
                    'Exit Display Test?',
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
                'Are you sure you want to exit the Display test? Your current progress will be lost.',
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
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        body: SafeArea(
          child: _currentStage == 0
              ? _buildIntroScreen()
              : (_currentStage <= _cycleColors.length
                  ? _buildFullScreenColorCycle()
                  : (_currentStage == 6
                      ? _buildEvaluationScreen()
                      : _buildFailQuestionnaireScreen())),
        ),
      ),
    );
  }

  // Stage 0: Initial Screen as shown in the mockup
  Widget _buildIntroScreen() {
    return Column(
      children: [
        // Top Header Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                onPressed: _handleBack,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),

              // Skip Test Button
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0848AA),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: InkWell(
                  onTap: _onSkip,
                  borderRadius: BorderRadius.circular(16),
                  child: const Center(
                    child: Text(
                      'Skip Test',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

              // Step Indicator 2/8
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFBFDBFE).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Center(
                  child: Text(
                    '2/8',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Title
        const Text(
          'Display Test',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F254B),
          ),
        ),
        const SizedBox(height: 8),

        // Subtitle instructions
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.0),
          child: Text(
            'The screen will cycle through Red, Green, and Blue. Look closely for any dead pixels or discoloration.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF475569),
              height: 1.4,
            ),
          ),
        ),

        // Center tap prompt area
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTapNextColor,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEEF2FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.touch_app_rounded,
                      size: 38,
                      color: Color(0xFF0C5AD2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tap to cycle colors',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F254B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Stage 1 to 5: Full-screen pure color cycle (Red, Green, Blue, White, Black)
  Widget _buildFullScreenColorCycle() {
    final Color currentColor = _cycleColors[_currentStage - 1];
    final bool isDarkColor = currentColor == Colors.black || currentColor == const Color(0xFF0000FF);
    final Color textColor = isDarkColor ? Colors.white70 : Colors.black87;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_currentStage < _cycleColors.length) {
          setState(() => _currentStage++);
        } else {
          setState(() => _currentStage++); // Go to evaluation question (Stage 6)
        }
      },
      child: Container(
        color: currentColor,
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          children: [
            // Center subtle indicator
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: (isDarkColor ? Colors.white : Colors.black).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Tap screen to continue ($_currentStage/${_cycleColors.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ),

            // Top exit button if needed
            Positioned(
              top: 12,
              left: 12,
              child: IconButton(
                icon: Icon(Icons.close, color: textColor),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Stage 6: Initial Evaluation Question after cycling colors
  Widget _buildEvaluationScreen() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFEEF2FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.phone_android_rounded,
              size: 32,
              color: Color(0xFF0C5AD2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Screen Check Complete',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F254B),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Did you notice any dead pixels, discoloration, lines, or dark spots while cycling through the colors?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.45),
          ),
          const Spacer(),

          // Pass Button (No defects found)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => _onCompleteTest(isPassed: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0848AA),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'No, Screen Looks Good (Pass)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Fail Button (Go to detailed defect questionnaire - Stage 7)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _currentStage = 7; // Open Fail questionnaire
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                'Yes, I Saw Issues (Fail)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // Stage 7: Detailed Display Issue Questionnaire when Fail is selected
  Widget _buildFailQuestionnaireScreen() {
    // Must answer Q1, Q2, and Q3 before allowing to complete the defect submission
    final bool canSubmit = _selectedQ1Issues.isNotEmpty &&
        _selectedQ2Locations.isNotEmpty &&
        _selectedQ3Severity != null;

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
                onPressed: () {
                  setState(() => _currentStage = 6); // Back to Pass / Fail choice
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const Text(
                'Report Display Issue',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 22),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Q1: What type of display issue did you notice?
                // Multiple selections allowed.
                _buildQuestionTitle(
                  'Q1. What type of display issue did you notice?',
                  subtitle: 'Multiple selections allowed. Select all issues that apply to your device.',
                ),
                const SizedBox(height: 10),
                ..._q1IssueOptions.map((issue) {
                  final String title = issue['title'] as String;
                  final String? imagePath = issue['image'] as String?;
                  final String desc = issue['desc'] as String? ?? '';
                  final bool isSelected = _selectedQ1Issues.contains(title);

                  return _buildQ1DefectTile(
                    title: title,
                    imagePath: imagePath,
                    desc: desc,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedQ1Issues.remove(title);
                        } else {
                          _selectedQ1Issues.add(title);
                        }
                      });
                    },
                    onViewImage: imagePath != null
                        ? () => _showDefectPreviewDialog(title, imagePath, desc)
                        : null,
                  );
                }),
                const SizedBox(height: 24),

                // Q2: Where did you notice the issue? (Select all that apply)
                _buildQuestionTitle(
                  'Q2. Where did you notice the issue?',
                  subtitle: 'Select all locations on the display where the defect is visible.',
                ),
                const SizedBox(height: 10),
                ..._q2Options.map((opt) {
                  final bool isSelected = _selectedQ2Locations.contains(opt);
                  return _buildMultiCheckTile(
                    title: opt,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedQ2Locations.remove(opt);
                        } else {
                          _selectedQ2Locations.add(opt);
                        }
                      });
                    },
                  );
                }),
                const SizedBox(height: 24),

                // Q3: How noticeable is the issue? (select one only)
                _buildQuestionTitle(
                  'Q3. How noticeable is the issue?',
                  subtitle: 'Select one option that best reflects the severity of the defect.',
                ),
                const SizedBox(height: 10),
                ..._q3Options.map((opt) {
                  final bool isSelected = _selectedQ3Severity == opt;
                  return _buildRadioTile(
                    title: opt,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() {
                        _selectedQ3Severity = opt;
                      });
                    },
                  );
                }),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),

        // Bottom Submission Bar - Only clickable when all questions are answered
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
                    'Please answer Q1, Q2, and Q3 above to complete your report.',
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
                  onPressed: canSubmit ? () => _onCompleteTest(isPassed: false) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'DONE',
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

  Widget _buildQuestionTitle(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F254B),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.justify,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQ1DefectTile({
    required String title,
    required String? imagePath,
    required String desc,
    required bool isSelected,
    required VoidCallback onTap,
    required VoidCallback? onViewImage,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
          width: isSelected ? 2.0 : 1.0,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: const Color(0xFF0C5AD2).withValues(alpha: 0.14),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                )
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                // Checkbox
                Icon(
                  isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF94A3B8),
                  size: 22,
                ),
                const SizedBox(width: 10),

                // Defect Image Thumbnail if available
                if (imagePath != null) ...[
                  GestureDetector(
                    onTap: onViewImage,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 52,
                            height: 52,
                            color: const Color(0xFF0F172A),
                            child: Image.asset(
                              imagePath,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.white54,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.zoom_in, color: Colors.white, size: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                ] else ...[
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFDBEAFE) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Icon(
                      Icons.help_outline_rounded,
                      color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF94A3B8),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                // Title without score badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected ? const Color(0xFF0F254B) : const Color(0xFF0F172A),
                        ),
                      ),
                      if (imagePath != null) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: onViewImage,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.visibility_outlined, size: 13, color: Color(0xFF0C5AD2)),
                              SizedBox(width: 4),
                              Text(
                                'Tap to view sample',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0C5AD2),
                                ),
                              ),
                            ],
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
    );
  }

  void _showDefectPreviewDialog(String title, String imagePath, String desc) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Image preview container
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 220),
                  color: const Color(0xFF0F172A),
                  child: Image.asset(
                    imagePath,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 40),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Pop up description text justified
              Text(
                desc,
                textAlign: TextAlign.justify,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF475569),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('GOT IT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMultiCheckTile({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
          width: isSelected ? 1.8 : 1.0,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: const Color(0xFF0C5AD2).withValues(alpha: 0.10),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF94A3B8),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? const Color(0xFF0F254B) : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
          width: isSelected ? 1.8 : 1.0,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: const Color(0xFF0C5AD2).withValues(alpha: 0.10),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF94A3B8),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? const Color(0xFF0F254B) : const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
