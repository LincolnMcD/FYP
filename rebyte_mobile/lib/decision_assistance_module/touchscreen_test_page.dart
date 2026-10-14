import 'package:flutter/material.dart';
import '../device_tradein_module/models/device_model.dart';
import 'display_test_page.dart';

class TouchscreenTestPage extends StatefulWidget {
  final DeviceModel? device;
  final String? tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;

  const TouchscreenTestPage({
    super.key,
    this.device,
    this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
  });

  @override
  State<TouchscreenTestPage> createState() => _TouchscreenTestPageState();
}

class _TouchscreenTestPageState extends State<TouchscreenTestPage> {
  static const int _columns = 7;
  static const int _rows = 14;
  late final int _totalTiles;

  late final Set<int> _touchedIndices;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _totalTiles = _columns * _rows;
    _touchedIndices = <int>{};
  }

  void _handlePointerEvent(Offset localPosition, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double tileWidth = size.width / _columns;
    final double tileHeight = size.height / _rows;

    final int col = (localPosition.dx / tileWidth).floor().clamp(0, _columns - 1);
    final int row = (localPosition.dy / tileHeight).floor().clamp(0, _rows - 1);

    final int index = row * _columns + col;
    if (!_touchedIndices.contains(index)) {
      setState(() {
        _touchedIndices.add(index);
      });

      // If user filled all tiles, automatically show completion or auto-pass
      if (_touchedIndices.length == _totalTiles) {
        _onTestComplete(isPassed: true, autoCompleted: true);
      }
    }
  }

  void _onTestComplete({required bool isPassed, bool autoCompleted = false, bool isSkipped = false}) {
    final int score = isSkipped
        ? 0
        : ((_touchedIndices.length / _totalTiles) * 100).round().clamp(0, 100);

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
                            : (score >= 80 ? Icons.check_circle_rounded : Icons.info_outline_rounded),
                        color: isSkipped
                            ? const Color(0xFFF59E0B)
                            : (score >= 80 ? const Color(0xFF16A34A) : const Color(0xFF0C5AD2)),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isSkipped ? 'Test Skipped' : 'Score: $score/100',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  if (score < 100)
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isSkipped
                    ? 'You chose to skip the Touchscreen test. This test will be recorded as skipped.'
                    : (score == 100
                        ? 'All $_totalTiles grid squares registered touch successfully! Touchscreen sensitivity is intact (Score: 100/100).'
                        : '${_touchedIndices.length} out of $_totalTiles grid squares filled. Touchscreen response calculated at $score/100.'),
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
                  // For success pop-up (score == 100), no need RETRY button
                  if (score < 100) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context); // Close dialog
                          _resetTest(); // Retry test
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
                        // Proceed to Test 2: Display Test with touch score passed
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DisplayTestPage(
                              device: widget.device,
                              tradeInRequestID: widget.tradeInRequestID,
                              isLoggedIn: widget.isLoggedIn,
                              email: widget.email,
                              name: widget.name,
                              touchScore: score,
                              isTouchSkipped: isSkipped,
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
                        'Skip Touchscreen Test?',
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
      // Directly proceed to Test 2: Display Test without a second pop-up
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DisplayTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: 0,
            isTouchSkipped: true,
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
                    'Exit Touchscreen Test?',
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
                'Are you sure you want to exit the Touchscreen test? Your current progress will be lost.',
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

  void _resetTest() {
    setState(() {
      _touchedIndices.clear();
    });
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
        backgroundColor: const Color(0xFFE2E8F0),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final Size canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) => _handlePointerEvent(e.localPosition, canvasSize),
                onPointerMove: (e) => _handlePointerEvent(e.localPosition, canvasSize),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Full-screen interactive Grid
                    _buildTouchGrid(constraints.maxWidth, constraints.maxHeight),

                    // Floating Top Bar (Back button, Step counter, Skip button)
                    Positioned(
                      top: 10,
                      left: 12,
                      right: 12,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1.0 : 0.25,
                        duration: const Duration(milliseconds: 200),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Back Arrow Button
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 20),
                                onPressed: _handleBack,
                                constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                                padding: EdgeInsets.zero,
                              ),
                            ),

                          // Center Skip Button
                          Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
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

                          // Progress Badge (e.g. 1/8)
                          Container(
                            height: 30,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFBFDBFE).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Center(
                              child: Text(
                                '1/8',
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
                  ),

                  // Floating Title & Instruction Header
                  Positioned(
                    top: 56,
                    left: 20,
                    right: 20,
                    child: IgnorePointer(
                      ignoring: true, // Let touches pass through directly to grid squares underneath!
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1.0 : 0.2,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Touchscreen Test',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F254B),
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Follow the pattern on the screen to test touch sensitivity. Fill all squares.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF475569),
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_touchedIndices.length} / $_totalTiles squares filled',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0C5AD2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Floating Action Bar at the bottom (Pass / Fail / Visibility toggle / Reset)
                  Positioned(
                    bottom: 14,
                    left: 20,
                    right: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Small overlay control (Toggle opacity & reset)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _controlsVisible = !_controlsVisible;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _controlsVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                      size: 14,
                                      color: const Color(0xFF475569),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _controlsVisible ? 'Minimize Buttons' : 'Show Buttons',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _resetTest,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF475569)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Reset',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Fail Action Button
                        IgnorePointer(
                          ignoring: !_controlsVisible,
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1.0 : 0.15,
                            duration: const Duration(milliseconds: 200),
                            child: SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton(
                                onPressed: () => _onTestComplete(isPassed: false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFE50914),
                                  foregroundColor: Colors.white,
                                  elevation: _controlsVisible ? 2 : 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'Fail',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
    );
  }

  Widget _buildTouchGrid(double width, double height) {
    final double tileWidth = width / _columns;
    final double tileHeight = height / _rows;

    return CustomPaint(
      size: Size(width, height),
      painter: _TouchGridPainter(
        columns: _columns,
        rows: _rows,
        tileWidth: tileWidth,
        tileHeight: tileHeight,
        touchedIndices: _touchedIndices,
      ),
    );
  }
}

class _TouchGridPainter extends CustomPainter {
  final int columns;
  final int rows;
  final double tileWidth;
  final double tileHeight;
  final Set<int> touchedIndices;

  _TouchGridPainter({
    required this.columns,
    required this.rows,
    required this.tileWidth,
    required this.tileHeight,
    required this.touchedIndices,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Unclicked block background (clean crisp off-white)
    final Paint unclickedPaint = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;

    // Touched/Clicked block background (vibrant, rich cobalt blue)
    final Paint touchedPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;

    // Inner highlight border for clicked tiles to make them pop out
    final Paint touchedInnerBorder = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Grid border paint
    final Paint borderPaint = Paint()
      ..color = const Color(0xFFCBD5E1) // Clean slate border
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // All-complete success paint (emerald green)
    final Paint successPaint = Paint()
      ..color = const Color(0xFF16A34A)
      ..style = PaintingStyle.fill;

    final bool allDone = touchedIndices.length == (columns * rows);

    // TextPainter for checkmark icon on touched blocks
    final TextPainter checkmarkPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < columns; c++) {
        final int index = r * columns + c;
        final Rect rect = Rect.fromLTWH(
          c * tileWidth,
          r * tileHeight,
          tileWidth,
          tileHeight,
        );

        final bool isTouched = touchedIndices.contains(index);

        if (isTouched) {
          // Draw vibrant touched fill
          canvas.drawRect(rect, allDone ? successPaint : touchedPaint);
          canvas.drawRect(rect.deflate(0.5), touchedInnerBorder);

          // Draw small white check icon in the center if tile has enough space
          if (tileWidth >= 20 && tileHeight >= 20) {
            checkmarkPainter.text = TextSpan(
              text: String.fromCharCode(Icons.check_rounded.codePoint),
              style: TextStyle(
                inherit: false,
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: (tileWidth < tileHeight ? tileWidth : tileHeight) * 0.42,
                fontFamily: Icons.check_rounded.fontFamily,
                package: Icons.check_rounded.fontPackage,
              ),
            );
            checkmarkPainter.layout();
            checkmarkPainter.paint(
              canvas,
              Offset(
                rect.left + (tileWidth - checkmarkPainter.width) / 2,
                rect.top + (tileHeight - checkmarkPainter.height) / 2,
              ),
            );
          }
        } else {
          // Draw unclicked background
          canvas.drawRect(rect, unclickedPaint);
        }

        // Draw tile border
        canvas.drawRect(rect, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TouchGridPainter oldDelegate) {
    return oldDelegate.touchedIndices.length != touchedIndices.length;
  }
}
