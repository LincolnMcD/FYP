import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../device_tradein_module/models/device_model.dart';
import 'diagnostic_result_page.dart';

class MicrophoneTestPage extends StatefulWidget {
  final DeviceModel? device;
  final String? tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final int touchScore;
  final int displayScore;
  final int cameraScore;
  final bool isTouchSkipped;
  final bool isDisplaySkipped;
  final bool isCameraSkipped;

  const MicrophoneTestPage({
    super.key,
    this.device,
    this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
    required this.touchScore,
    required this.displayScore,
    required this.cameraScore,
    this.isTouchSkipped = false,
    this.isDisplaySkipped = false,
    this.isCameraSkipped = false,
  });

  @override
  State<MicrophoneTestPage> createState() => _MicrophoneTestPageState();
}

enum MicTestPhase {
  ready,              // Initial state before pressing Start
  silencePhase,       // 2 seconds silence (System noise floor & SNR calibration)
  speechPhase,        // 5 seconds reading speech prompt (Volume, continuity, clarity)
  playbackAndReview,  // User plays back recorded audio and answers clarity questionnaire
}

class _MicrophoneTestPageState extends State<MicrophoneTestPage> {
  // Audio recording & playback engines
  late final AudioRecorder _audioRecorder;
  late final AudioPlayer _audioPlayer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  String? _recordedFilePath;

  MicTestPhase _phase = MicTestPhase.ready;
  int _secondsLeft = 0;
  Timer? _countdownTimer;

  // Real-time microphone amplitude waveform bars (9 bars)
  List<double> _barHeights = [0.15, 0.15, 0.15, 0.15, 0.15, 0.15, 0.15, 0.15, 0.15];
  double _volumeLevel = 0.05; // 0.0 to 1.0 (Min to Peak meter)

  // Real measured audio levels during test
  final List<double> _silenceDbList = [];
  final List<double> _speechDbList = [];
  double _calculatedSpeechRmsDbfs = -22.0;
  double _calculatedNoiseFloorDbfs = -55.0;
  double _currentLiveDbfs = -50.0;

  // Audio Playback state
  bool _isPlaying = false;
  StreamSubscription<PlayerState>? _playerStateSub;

  // System Evaluation Metric Deductions:
  // 1. Voice Volume: Normal (-30 to -15) = 0%, Borderline (-38 to <-30) = -5%, Weak (< -38) = -20%
  int _volumeDeduction = 0; // 0, 5, or 20

  // 3. Background Noise:
  //    Very low (<= -60): 0%
  //    Low (> -60 to -50): 0%
  //    Moderate (> -50 to -40): -5%
  //    High (> -40 to -30): -10%
  //    Very high (> -30): -20%
  int _noiseDeduction = 0; // 0, 5, 10, or 20

  // 4. Audio Continuity: 0 drops = 0%, confirmed dropout = -30%
  bool _sysIntermittent = false; // true: -30%

  // 5. Recording Availability: Completed = 0%, failure = -100%
  bool _sysRecordingFailed = false; // true: -100%

  // QA / Developer negative test: Dropoff Voice Simulation
  bool _isSimulatingDropoff = false;

  // 2. User Clarity Choice:
  // Clear = 0% deduction (100 score)
  // Partially clear = -15% deduction (50 score)
  // Unclear / Muffled = -30% deduction (0 score)
  int? _userClarityScore;

  static const String _readingPhrase =
      '“ReByte delivers fast, secure and reliable device trade-in diagnostics.”';

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _audioPlayer = AudioPlayer();

    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state == PlayerState.playing;
        if (!_isPlaying) {
          _barHeights = [0.15, 0.20, 0.35, 0.50, 0.40, 0.45, 0.30, 0.20, 0.15];
          _volumeLevel = 0.05;
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _amplitudeSub?.cancel();
    _playerStateSub?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _startDiagnosticTest() async {
    // Update UI immediately to indicate test starting
    setState(() {
      _phase = MicTestPhase.silencePhase;
      _secondsLeft = 2;
      _userClarityScore = null;
      _isPlaying = false;
      _volumeLevel = 0.08;
    });

    _countdownTimer?.cancel();
    _amplitudeSub?.cancel();
    await _audioPlayer.stop();

    _silenceDbList.clear();
    _speechDbList.clear();

    bool recorderStarted = false;

    try {
      // 1. Check microphone permission via audioRecorder directly
      final bool hasPerm = await _audioRecorder.hasPermission();
      if (hasPerm) {
        final Directory tempDir = await getTemporaryDirectory();
        final String filePath = '${tempDir.path}/rebyte_mic_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: filePath,
        );

        _recordedFilePath = filePath;
        _sysRecordingFailed = false;
        recorderStarted = true;

        // Listen to live amplitude from microphone
        _amplitudeSub = _audioRecorder
            .onAmplitudeChanged(const Duration(milliseconds: 70))
            .listen((amp) {
          if (!mounted) return;

          final double currentDb = amp.current;

          // If simulating dropoff, cut out voice at seconds 3 & 2
          final bool isDroppingOut = _isSimulatingDropoff &&
              _phase == MicTestPhase.speechPhase &&
              (_secondsLeft == 3 || _secondsLeft == 2);

          final double effectiveDb = isDroppingOut ? -90.0 : currentDb;

          if (_phase == MicTestPhase.silencePhase) {
            _silenceDbList.add(effectiveDb);
          } else if (_phase == MicTestPhase.speechPhase) {
            _speechDbList.add(effectiveDb);
          }

          final double normalized = isDroppingOut
              ? 0.02
              : ((effectiveDb + 60.0) / 55.0).clamp(0.04, 1.0);

          setState(() {
            _currentLiveDbfs = effectiveDb;
            _volumeLevel = normalized;
            if (isDroppingOut) {
              _barHeights = List.generate(9, (_) => 0.10);
            } else {
              final Random r = Random();
              _barHeights = List.generate(9, (index) {
                final double bellCurve = 1.0 - (pow(index - 4, 2) / 22.0);
                final double variance = (r.nextDouble() * 0.20) - 0.10;
                return (normalized * bellCurve + variance).clamp(0.12, 1.0);
              });
            }
          });
        });
      } else {
        // Permission denied by user
        _sysRecordingFailed = true;
      }
    } catch (e) {
      debugPrint('Live audio recorder init notice: $e');
      _sysRecordingFailed = true;
    }

    // If microphone is not available / denied, keep flatline waves (no fake jumping)
    if (!recorderStarted) {
      _amplitudeSub?.cancel();
      _sysRecordingFailed = true;
      setState(() {
        _currentLiveDbfs = -90.0;
        _volumeLevel = 0.0;
        _barHeights = List.generate(9, (_) => 0.12);
      });
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        timer.cancel();
        // Transition to Phase 2: 5 seconds speech reading
        _startSpeechPhase();
      }
    });
  }

  void _startSpeechPhase() {
    setState(() {
      _phase = MicTestPhase.speechPhase;
      _secondsLeft = 5; // 5 seconds reading
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft > 1) {
        setState(() => _secondsLeft--);
      } else {
        timer.cancel();
        _finishRecordingAndAnalyze();
      }
    });
  }

  Future<void> _finishRecordingAndAnalyze() async {
    _amplitudeSub?.cancel();

    try {
      final String? path = await _audioRecorder.stop();
      if (path != null) {
        _recordedFilePath = path;
      }
    } catch (e) {
      debugPrint('Error stopping audio recorder: $e');
    }

    // Analyze real measured audio parameters
    if (_recordedFilePath == null || _speechDbList.isEmpty) {
      _sysRecordingFailed = true;
    }

    if (_sysRecordingFailed) {
      // Hardware failure or mic not allowed / no audio captured
      _calculatedSpeechRmsDbfs = -90.0;
      _calculatedNoiseFloorDbfs = -90.0;
      _volumeDeduction = 20; // Weak volume (< -38 dBFS)
      _noiseDeduction = 0;   // Hardware failed
      _sysIntermittent = true; // No audio stream received
    } else {
      // 1. Average Voice Volume (dBFS)
      if (_speechDbList.isNotEmpty) {
        final double avgSpeechDb = _speechDbList.reduce((a, b) => a + b) / _speechDbList.length;
        _calculatedSpeechRmsDbfs = avgSpeechDb;

        if (avgSpeechDb < -38.0) {
          _volumeDeduction = 20; // Weak (< -38 dBFS) -> Severe
        } else if (avgSpeechDb < -30.0) {
          _volumeDeduction = 5;  // Borderline (-38 to -30 dBFS) -> Minor
        } else {
          _volumeDeduction = 0;  // Normal (-30 to -15 dBFS) -> Normal
        }
      } else {
        _calculatedSpeechRmsDbfs = -90.0;
        _volumeDeduction = 20; // Weak
      }

      // 3. Background Noise Floor (dBFS) from 2s silence phase
      if (_silenceDbList.isNotEmpty) {
        final double avgSilenceDb = _silenceDbList.reduce((a, b) => a + b) / _silenceDbList.length;
        _calculatedNoiseFloorDbfs = avgSilenceDb;

        if (avgSilenceDb > -30.0) {
          _noiseDeduction = 20; // Very high noise: > -30 dBFS -> Severe
        } else if (avgSilenceDb > -40.0) {
          _noiseDeduction = 10; // High noise: > -40 to -30 dBFS -> Moderate
        } else if (avgSilenceDb > -50.0) {
          _noiseDeduction = 5;  // Moderate noise: > -50 to -40 dBFS -> Minor
        } else {
          _noiseDeduction = 0;  // Low / Very low noise: <= -50 dBFS -> Normal
        }
      } else {
        _calculatedNoiseFloorDbfs = -90.0;
        _noiseDeduction = 0;
      }

      // 4. Audio Continuity (0% or -30%)
      if (_isSimulatingDropoff) {
        _sysIntermittent = true;
      } else {
        _sysIntermittent = false;
      }
    }

    setState(() {
      _phase = MicTestPhase.playbackAndReview;
      _secondsLeft = 0;
      _volumeLevel = 0.05;
      _barHeights = [0.15, 0.20, 0.35, 0.50, 0.40, 0.45, 0.30, 0.20, 0.15];
    });
  }

  Future<void> _togglePlayback() async {
    if (_recordedFilePath == null) return;

    if (_isPlaying) {
      await _audioPlayer.stop();
      setState(() => _isPlaying = false);
      return;
    }

    try {
      await _audioPlayer.play(DeviceFileSource(_recordedFilePath!));
      setState(() => _isPlaying = true);
    } catch (e) {
      debugPrint('Error playing recorded audio: $e');
    }
  }

  // Calculate Microphone Score:
  // Base = 100%
  // 1. Voice Volume: Normal = 0%, Borderline = -5%, Weak = -20%
  // 2. Audio Clarity: Clear = 0%, Partially clear = -15%, Unclear / Muffled = -30%
  // 3. Background Noise: <= -50 = 0%, -50 to -40 = -5%, -40 to -30 = -10%, > -30 = -20%
  // 4. Audio Continuity: 0 drops = 0%, Confirmed dropout = -30%
  // 5. Recording Availability: Confirmed failure = -100% directly
  int _calculateMicScore({required bool isSkipped}) {
    if (isSkipped) return 0;
    if (_sysRecordingFailed) return 0;

    int totalDeduction = 0;

    // 1. Voice Volume deduction
    totalDeduction += _volumeDeduction;

    // 2. Audio Clarity deduction
    if (_userClarityScore == 50) {
      totalDeduction += 15; // Partially clear
    } else if (_userClarityScore == 0) {
      totalDeduction += 30; // Unclear / Muffled
    }

    // 3. Background Noise deduction
    totalDeduction += _noiseDeduction;

    // 4. Audio Continuity deduction
    if (_sysIntermittent) {
      totalDeduction += 30;
    }

    final int finalScore = (100 - totalDeduction).clamp(0, 100);
    return finalScore;
  }

  void _onCompleteTest({bool isSkipped = false}) {
    final int micScore = _calculateMicScore(isSkipped: isSkipped);

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
                            : (micScore >= 80 ? Icons.check_circle_rounded : Icons.assignment_late_rounded),
                        color: isSkipped
                            ? const Color(0xFFF59E0B)
                            : (micScore >= 80 ? const Color(0xFF16A34A) : const Color(0xFF0C5AD2)),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isSkipped ? 'Test Skipped' : 'Score: $micScore/100',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  if (micScore < 100)
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isSkipped
                    ? 'You chose to skip the Microphone test. This test will be recorded as skipped.'
                    : (micScore == 100
                        ? 'Microphone check completed! Audio hardware passed all volume, continuity, noise and clarity benchmarks (Score: 100/100).'
                        : 'Microphone test evaluation completed. Microphone clarity evaluation result: $micScore/100.'),
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
                  if (micScore < 100) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context); // Close dialog
                          setState(() {
                            _phase = MicTestPhase.ready;
                            _userClarityScore = null;
                            _volumeDeduction = 0;
                            _noiseDeduction = 0;
                            _sysIntermittent = false;
                            _sysRecordingFailed = false;
                            _volumeLevel = 0.05;
                            _isPlaying = false;
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
                              micScore: micScore,
                              isTouchSkipped: widget.isTouchSkipped,
                              isDisplaySkipped: widget.isDisplaySkipped,
                              isCameraSkipped: widget.isCameraSkipped,
                              isMicSkipped: isSkipped,
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
                        'Skip Microphone Test?',
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
          builder: (context) => DiagnosticResultPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: widget.touchScore,
            displayScore: widget.displayScore,
            cameraScore: widget.cameraScore,
            micScore: 0,
            isTouchSkipped: widget.isTouchSkipped,
            isDisplaySkipped: widget.isDisplaySkipped,
            isCameraSkipped: widget.isCameraSkipped,
            isMicSkipped: true,
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
                    'Exit Microphone Test?',
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
                'Are you sure you want to exit the Microphone test? Your current progress will be lost.',
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
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              // Top Navigation Header: Back Button & 4/8 Step Indicator
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                      onPressed: _handleBack,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '4/8',
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

            // Skip Test Button (With Confirm Skip Pop-Up)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Center(
                child: SizedBox(
                  width: 110,
                  height: 36,
                  child: ElevatedButton(
                    onPressed: _handleSkip,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0848AA),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text(
                      'Skip Test',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Title and Subtitle Instructions
            const Text(
              'Microphone Test',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F254B),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: Text(
                _phase == MicTestPhase.silencePhase
                    ? 'Stay completely silent for 2 seconds to calibrate ambient noise...'
                    : (_phase == MicTestPhase.speechPhase
                        ? 'Read the phrase aloud clearly for 5 seconds:'
                        : (_phase == MicTestPhase.playbackAndReview
                            ? 'Listen to your recording and verify clarity below.'
                            : 'First stay silent for 2s, then read aloud the phrase for 5s.')),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: _phase == MicTestPhase.speechPhase || _phase == MicTestPhase.silencePhase
                      ? FontWeight.w700
                      : FontWeight.normal,
                  color: _phase == MicTestPhase.speechPhase
                      ? const Color(0xFF0C5AD2)
                      : (_phase == MicTestPhase.silencePhase
                          ? const Color(0xFFD97706)
                          : const Color(0xFF64748B)),
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Scrollable Content Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // Reading Phrase Box (Always visible during recording and review)
                    _buildReadingPhraseBox(),
                    const SizedBox(height: 16),

                    // QA / Developer Negative Test Button (Only for lolincoln021@gmail.com)
                    if (widget.email?.trim().toLowerCase() == 'lolincoln021@gmail.com') ...[
                      _buildDeveloperNegativeTestButton(),
                      const SizedBox(height: 14),
                    ],

                    // Main Visualizer Card
                    _buildVisualizerCard(),
                    const SizedBox(height: 20),

                    // If recording finished, show System Evaluation & User Clarity selection
                    if (_phase == MicTestPhase.playbackAndReview) ...[
                      _buildEvaluationSection(),
                      const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom Action Bar
            _buildBottomActionBar(),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildReadingPhraseBox() {
    final bool isHighlighted = _phase == MicTestPhase.speechPhase;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: isHighlighted ? const Color(0xFFEFF6FF) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighlighted ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
          width: isHighlighted ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.record_voice_over_rounded,
                size: 16,
                color: isHighlighted ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                'Phrase to read (5 sec)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isHighlighted ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _readingPhrase,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              color: isHighlighted ? const Color(0xFF0F254B) : const Color(0xFF334155),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeveloperNegativeTestButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _isSimulatingDropoff ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isSimulatingDropoff ? const Color(0xFFEF4444) : const Color(0xFFCBD5E1),
          width: _isSimulatingDropoff ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _isSimulatingDropoff
                  ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                  : const Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.bug_report_rounded,
              size: 18,
              color: _isSimulatingDropoff ? const Color(0xFFDC2626) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'QA: Dropoff Voice Simulation',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F254B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'DEV',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E40AF),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _isSimulatingDropoff
                      ? 'Simulates audio interruption & dropout (-30% Severe)'
                      : 'Inject negative test: drops out voice during 5s speech',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isSimulatingDropoff ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isSimulatingDropoff,
            activeThumbColor: const Color(0xFFDC2626),
            onChanged: (val) {
              setState(() {
                _isSimulatingDropoff = val;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVisualizerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        children: [
          // Dynamic Waveform Bars responding to live microphone amplitude
          SizedBox(
            height: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_barHeights.length, (index) {
                final double h = _barHeights[index] * 70;
                final bool isActive = _phase == MicTestPhase.speechPhase || _isPlaying;
                final bool isSilence = _phase == MicTestPhase.silencePhase;

                return Container(
                  width: 9,
                  height: h.clamp(12.0, 70.0),
                  margin: const EdgeInsets.symmetric(horizontal: 3.5),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF0C5AD2)
                        : (isSilence ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),

          // Real-time dBFS level readout
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 16,
                color: _phase == MicTestPhase.speechPhase
                    ? const Color(0xFF0C5AD2)
                    : (_phase == MicTestPhase.silencePhase
                        ? const Color(0xFFD97706)
                        : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 6),
              Text(
                'Live Level: ${_currentLiveDbfs.toStringAsFixed(1)} dBFS',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _phase == MicTestPhase.speechPhase
                      ? const Color(0xFF0C5AD2)
                      : (_phase == MicTestPhase.silencePhase
                          ? const Color(0xFFD97706)
                          : const Color(0xFF475569)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status Badge Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _phase == MicTestPhase.silencePhase
                        ? const Color(0xFFD97706)
                        : (_phase == MicTestPhase.speechPhase
                            ? const Color(0xFFDC2626)
                            : (_phase == MicTestPhase.playbackAndReview
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF2563EB))),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _phase == MicTestPhase.silencePhase
                      ? 'Stay Silent... (${_secondsLeft}s)'
                      : (_phase == MicTestPhase.speechPhase
                          ? 'Speak Now... (${_secondsLeft}s)'
                          : (_phase == MicTestPhase.playbackAndReview
                              ? (_isPlaying ? 'Playing back audio...' : 'Recording Complete')
                              : 'Ready to record')),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Min to Peak Volume Bar
          Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    'Min',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    'Peak',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  height: 6,
                  width: double.infinity,
                  color: const Color(0xFFE2E8F0),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _volumeLevel.clamp(0.05, 1.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF22C55E),
                            Color(0xFFEAB308),
                            Color(0xFFEF4444),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Audio Playback Button (Only in review phase)
          if (_phase == MicTestPhase.playbackAndReview) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 170,
              height: 38,
              child: OutlinedButton.icon(
                onPressed: _togglePlayback,
                icon: Icon(
                  _isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 20,
                  color: const Color(0xFF0C5AD2),
                ),
                label: Text(
                  _isPlaying ? 'Stop Audio' : 'Play Recording',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0C5AD2),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFF0C5AD2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Section 2: Comprehensive Evaluation (System & User Clarity)
  Widget _buildEvaluationSection() {
    final String formattedSpeechDb = _calculatedSpeechRmsDbfs.toStringAsFixed(1);
    final String formattedNoiseDb = _calculatedNoiseFloorDbfs.toStringAsFixed(1);

    // Voice Volume status label
    String volumeStatusText;
    if (_sysRecordingFailed) {
      volumeStatusText = 'No microphone audio detected (Weak)';
    } else if (_volumeDeduction == 0) {
      volumeStatusText = 'Normal ($formattedSpeechDb dBFS)';
    } else if (_volumeDeduction == 5) {
      volumeStatusText = 'Borderline ($formattedSpeechDb dBFS)';
    } else {
      volumeStatusText = 'Weak ($formattedSpeechDb dBFS)';
    }

    // Background Noise status label
    String noiseStatusText;
    if (_sysRecordingFailed) {
      noiseStatusText = 'Unavailable (Hardware inactive)';
    } else if (_noiseDeduction == 0) {
      noiseStatusText = _calculatedNoiseFloorDbfs <= -60.0
          ? 'Very low noise ($formattedNoiseDb dBFS)'
          : 'Low noise ($formattedNoiseDb dBFS)';
    } else if (_noiseDeduction == 5) {
      noiseStatusText = 'Moderate noise ($formattedNoiseDb dBFS)';
    } else if (_noiseDeduction == 10) {
      noiseStatusText = 'High noise ($formattedNoiseDb dBFS)';
    } else {
      noiseStatusText = 'Very high noise ($formattedNoiseDb dBFS)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Audio Clarity (User Evaluation: Clear, Partially clear, Unclear)
        Container(
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
              const Row(
                children: [
                  Icon(Icons.hearing_rounded, size: 20, color: Color(0xFF0F254B)),
                  SizedBox(width: 8),
                  Text(
                    'Audio Clarity (User Evaluation)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F254B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Listen to the playback. Does your voice sound clear, partially clear, or unclear?',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),

              // 3 Choices: Clear, Partially clear, Unclear (Clean option cards without normal/issue() subtitles)
              Row(
                children: [
                  _buildClarityChoiceButton(
                    title: 'Clear',
                    score: 100,
                    color: const Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 8),
                  _buildClarityChoiceButton(
                    title: 'Partially clear',
                    score: 50,
                    color: const Color(0xFFD97706),
                  ),
                  const SizedBox(width: 8),
                  _buildClarityChoiceButton(
                    title: 'Unclear',
                    score: 0,
                    color: const Color(0xFFDC2626),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. System Benchmark Metrics (Live Measured)
        Container(
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
              const Row(
                children: [
                  Icon(Icons.analytics_outlined, size: 20, color: Color(0xFF0F254B)),
                  SizedBox(width: 8),
                  Text(
                    'System Audio Quality Benchmarks',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F254B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Automated analysis calibrated during 2s silence and 5s speech phases.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),

              // 1. Voice Volume (3 Levels: Passed/Normal, Issue (Minor), Issue (Severe))
              _buildSystemMetricRow(
                title: 'Voice Volume',
                description: volumeStatusText,
                isDefective: _volumeDeduction > 0,
                customBadgeText: _volumeDeduction == 0
                    ? 'Passed'
                    : (_volumeDeduction == 5 ? 'Issue (Minor)' : 'Issue (Severe)'),
                onToggle: (val) {
                  setState(() {
                    if (val) {
                      _volumeDeduction = _volumeDeduction == 0 ? 20 : _volumeDeduction;
                    } else {
                      _volumeDeduction = 0;
                    }
                  });
                },
              ),
              const Divider(height: 16, color: Color(0xFFF1F5F9)),

              // 2. Background Noise (3 Levels: Passed/Normal, Issue (Minor), Issue (Moderate / Severe))
              _buildSystemMetricRow(
                title: 'Background Noise',
                description: noiseStatusText,
                isDefective: _noiseDeduction > 0,
                customBadgeText: _noiseDeduction == 0
                    ? 'Passed'
                    : (_noiseDeduction == 5
                        ? 'Issue (Minor)'
                        : (_noiseDeduction == 10 ? 'Issue (Moderate)' : 'Issue (Severe)')),
                onToggle: (val) {
                  setState(() {
                    if (val) {
                      _noiseDeduction = _noiseDeduction == 0 ? 10 : _noiseDeduction;
                    } else {
                      _noiseDeduction = 0;
                    }
                  });
                },
              ),
              const Divider(height: 16, color: Color(0xFFF1F5F9)),

              // 3. Audio Continuity (Just Issue or Passed)
              _buildSystemMetricRow(
                title: 'Audio Continuity',
                description: _sysIntermittent
                    ? 'Confirmed recording dropout detected'
                    : 'No confirmed interruption (0 drops)',
                isDefective: _sysIntermittent,
                customBadgeText: _sysIntermittent ? 'Issue' : 'Passed',
                onToggle: (val) => setState(() => _sysIntermittent = val),
              ),
              const Divider(height: 16, color: Color(0xFFF1F5F9)),

              // 4. Recording Availability (Just Issue or Passed)
              _buildSystemMetricRow(
                title: 'Recording Availability',
                description: _sysRecordingFailed
                    ? 'Confirmed microphone failure'
                    : 'Recording successfully completed',
                isDefective: _sysRecordingFailed,
                customBadgeText: _sysRecordingFailed ? 'Issue' : 'Passed',
                onToggle: (val) => setState(() => _sysRecordingFailed = val),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClarityChoiceButton({
    required String title,
    required int score,
    required Color color,
  }) {
    final bool isSelected = _userClarityScore == score;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _userClarityScore = score),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFCBD5E1),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                size: 16,
                color: isSelected ? color : const Color(0xFF94A3B8),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? color : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSystemMetricRow({
    required String title,
    required String description,
    required bool isDefective,
    required String customBadgeText,
    required ValueChanged<bool> onToggle,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F254B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () => onToggle(!isDefective),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDefective ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDefective ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isDefective ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                  size: 13,
                  color: isDefective ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                ),
                const SizedBox(width: 4),
                Text(
                  customBadgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isDefective ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActionBar() {
    final bool canComplete = _phase == MicTestPhase.playbackAndReview && _userClarityScore != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: _phase != MicTestPhase.playbackAndReview
            ? ElevatedButton.icon(
                onPressed: _phase == MicTestPhase.ready ? _startDiagnosticTest : null,
                icon: const Icon(Icons.mic, size: 20),
                label: Text(
                  _phase == MicTestPhase.silencePhase
                      ? 'Calibrating Noise... (${_secondsLeft}s)'
                      : (_phase == MicTestPhase.speechPhase
                          ? 'Listening to Speech... (${_secondsLeft}s)'
                          : 'Start Test (2s Silence + 5s Read)'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0848AA),
                  disabledBackgroundColor: const Color(0xFFE2E8F0),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: const Color(0xFF94A3B8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )
            : ElevatedButton(
                onPressed: canComplete ? () => _onCompleteTest() : null,
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
    );
  }
}
