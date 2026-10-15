import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../device_tradein_module/models/device_model.dart';
import 'sensor_test_page.dart';

class SpeakerTestPage extends StatefulWidget {
  final DeviceModel? device;
  final String? tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final int touchScore;
  final int displayScore;
  final int cameraScore;
  final int micScore;
  final bool isTouchSkipped;
  final bool isDisplaySkipped;
  final bool isCameraSkipped;
  final bool isMicSkipped;

  const SpeakerTestPage({
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
    this.isTouchSkipped = false,
    this.isDisplaySkipped = false,
    this.isCameraSkipped = false,
    this.isMicSkipped = false,
  });

  @override
  State<SpeakerTestPage> createState() => _SpeakerTestPageState();
}

class _SpeakerTestPageState extends State<SpeakerTestPage> {
  late final AudioPlayer _audioPlayer;
  late final String _targetCode; // 4 random digits
  String _enteredCode = '';
  bool _hasPlayedInitial = false; // Initial play requires clicking the speaker button
  int _replaysLeft = 1; // 1 replay allowed after initial play
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    // Generate 4 random digits (0-9)
    final random = Random();
    final d1 = random.nextInt(10);
    final d2 = random.nextInt(10);
    final d3 = random.nextInt(10);
    final d4 = random.nextInt(10);
    _targetCode = '$d1$d2$d3$d4';
  }

  @override
  void dispose() {
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  static const MethodChannel _hardwareChannel = MethodChannel('com.tarumt.rebyte/hardware');

  Future<void> _playSequence() async {
    if (_isPlaying) return;
    setState(() {
      _isPlaying = true;
    });

    try {
      // 1. Try spoken voice via Android native TextToSpeech engine
      final bool? spoken = await _hardwareChannel.invokeMethod<bool>('speakDigits', {
        'digits': _targetCode,
      });

      // 2. Fallback to tone sequence if TTS isn't available or fails
      if (spoken != true) {
        for (int i = 0; i < _targetCode.length; i++) {
          if (!mounted) break;
          final digit = int.parse(_targetCode[i]);
          await _playDigitTone(digit);
          await Future.delayed(const Duration(milliseconds: 350));
        }
      }
    } catch (_) {
      // Fallback tone sequence
      for (int i = 0; i < _targetCode.length; i++) {
        if (!mounted) break;
        final digit = int.parse(_targetCode[i]);
        await _playDigitTone(digit);
        await Future.delayed(const Duration(milliseconds: 350));
      }
    }

    if (mounted) {
      setState(() {
        _isPlaying = false;
      });
    }
  }

  Future<void> _playDigitTone(int digit) async {
    // Generate a simple PCM/WAV beep buffer in memory with standard frequency
    try {
      final wavBytes = _createBeepWav(digit);
      await _audioPlayer.stop();
      await _audioPlayer.play(BytesSource(Uint8List.fromList(wavBytes)));
    } catch (_) {
      // Graceful ignore
    }
  }

  List<int> _createBeepWav(int digit) {
    // Frequencies: 500Hz + digit * 120Hz
    final sampleRate = 8000;
    final durationSeconds = 0.35;
    final numSamples = (sampleRate * durationSeconds).toInt();
    final frequency = 440.0 + (digit * 90.0);

    final byteData = <int>[];
    // WAV Header
    void writeString(String s) {
      for (int i = 0; i < s.length; i++) {
        byteData.add(s.codeUnitAt(i));
      }
    }

    void writeUint32(int value) {
      byteData.add(value & 0xFF);
      byteData.add((value >> 8) & 0xFF);
      byteData.add((value >> 16) & 0xFF);
      byteData.add((value >> 24) & 0xFF);
    }

    void writeUint16(int value) {
      byteData.add(value & 0xFF);
      byteData.add((value >> 8) & 0xFF);
    }

    final dataChunkSize = numSamples * 2; // 16-bit mono
    final fileSize = 36 + dataChunkSize;

    writeString('RIFF');
    writeUint32(fileSize);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16); // Subchunk1Size (16 for PCM)
    writeUint16(1); // AudioFormat (1 for PCM)
    writeUint16(1); // NumChannels (1 mono)
    writeUint32(sampleRate);
    writeUint32(sampleRate * 2); // ByteRate
    writeUint16(2); // BlockAlign
    writeUint16(16); // BitsPerSample
    writeString('data');
    writeUint32(dataChunkSize);

    // Audio samples: Sine wave with attack and decay to eliminate clicks
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double envelope = 1.0;
      if (i < 200) {
        envelope = i / 200;
      } else if (i > numSamples - 200) {
        envelope = (numSamples - i) / 200;
      }
      final sample = (sin(2 * pi * frequency * t) * 28000 * envelope).toInt();
      final clamped = sample.clamp(-32768, 32767);
      byteData.add(clamped & 0xFF);
      byteData.add((clamped >> 8) & 0xFF);
    }

    return byteData;
  }

  void _onSpeakerCircleTap() {
    if (_isPlaying) return;

    if (!_hasPlayedInitial) {
      // First time play
      setState(() {
        _hasPlayedInitial = true;
      });
      _playSequence();
    } else if (_replaysLeft > 0) {
      // Allowed replay
      setState(() {
        _replaysLeft--;
      });
      _playSequence();
    } else {
      // No replays left
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Replay limit reached (1 replay allowed). Please enter the 4 digits heard.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }



  void _onKeypadTap(String val) {
    if (_enteredCode.length < 4) {
      setState(() {
        _enteredCode += val;
      });
    }
  }

  void _onBackspaceTap() {
    if (_enteredCode.isNotEmpty) {
      setState(() {
        _enteredCode = _enteredCode.substring(0, _enteredCode.length - 1);
      });
    }
  }

  Future<void> _onNextTest() async {
    // Calculate speaker score
    int matchedCount = 0;
    for (int i = 0; i < 4; i++) {
      if (i < _enteredCode.length && _enteredCode[i] == _targetCode[i]) {
        matchedCount++;
      }
    }
    final int speakerScore = (matchedCount * 25).clamp(0, 100);

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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        speakerScore == 100
                            ? Icons.check_circle_rounded
                            : (speakerScore >= 50
                                ? Icons.info_outline_rounded
                                : (speakerScore >= 1 ? Icons.warning_amber_rounded : Icons.cancel_rounded)),
                        color: speakerScore == 100
                            ? const Color(0xFF16A34A)
                            : (speakerScore >= 50
                                ? const Color(0xFF0C5AD2)
                                : (speakerScore >= 1 ? const Color(0xFFD97706) : const Color(0xFFE11D48))),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Score: $speakerScore/100',
                        style: const TextStyle(
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
              Text(
                'Entered Code: ${_enteredCode.isNotEmpty ? _enteredCode : "None"}\n'
                'Target Code: $_targetCode\n'
                'Matching Digits: $matchedCount / 4\n'
                'Speaker Performance Score: $speakerScore/100',
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
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SensorTestPage(
                              device: widget.device,
                              tradeInRequestID: widget.tradeInRequestID,
                              isLoggedIn: widget.isLoggedIn,
                              email: widget.email,
                              name: widget.name,
                              touchScore: widget.touchScore,
                              displayScore: widget.displayScore,
                              cameraScore: widget.cameraScore,
                              micScore: widget.micScore,
                              speakerScore: speakerScore,
                              isTouchSkipped: widget.isTouchSkipped,
                              isDisplaySkipped: widget.isDisplaySkipped,
                              isCameraSkipped: widget.isCameraSkipped,
                              isMicSkipped: widget.isMicSkipped,
                              isSpeakerSkipped: false,
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
                    'Skip Speaker Test?',
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
          builder: (context) => SensorTestPage(
            device: widget.device,
            tradeInRequestID: widget.tradeInRequestID,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            touchScore: widget.touchScore,
            displayScore: widget.displayScore,
            cameraScore: widget.cameraScore,
            micScore: widget.micScore,
            speakerScore: 0,
            isTouchSkipped: widget.isTouchSkipped,
            isDisplaySkipped: widget.isDisplaySkipped,
            isCameraSkipped: widget.isCameraSkipped,
            isMicSkipped: widget.isMicSkipped,
            isSpeakerSkipped: true,
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
                    'Exit Speaker Test?',
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
                'Are you sure you want to exit the Speaker test? Your current progress will be lost.',
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
    final bool canNext = _enteredCode.length == 4;

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
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // Header Row (Back, Skip, 5/8 indicator)
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
                        '5/8',
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

              // Title & Subtitle
              const SizedBox(height: 4),
              const Text(
                'Speaker Test',
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
                  'Listen to the sequence of numbers and enter them below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Large Blue Speaker Button & Replay Pill
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _onSpeakerCircleTap,
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0848AA),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0848AA).withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            _isPlaying ? Icons.volume_up : Icons.volume_up_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Replay button / indicator
                    InkWell(
                      onTap: (!_hasPlayedInitial || _replaysLeft > 0) && !_isPlaying ? _onSpeakerCircleTap : null,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (!_hasPlayedInitial || _replaysLeft > 0)
                              ? const Color(0xFFF1F5F9)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: (!_hasPlayedInitial || _replaysLeft > 0)
                                ? const Color(0xFFCBD5E1)
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              !_hasPlayedInitial ? Icons.play_arrow_rounded : Icons.replay,
                              size: 14,
                              color: (!_hasPlayedInitial || _replaysLeft > 0)
                                  ? const Color(0xFF0848AA)
                                  : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              !_hasPlayedInitial
                                  ? 'Tap speaker to play'
                                  : (_replaysLeft > 0 ? 'Replay (1 left)' : 'No replays left'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: (!_hasPlayedInitial || _replaysLeft > 0)
                                    ? const Color(0xFF0848AA)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Code Input Box (4 dashes/digits)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDCE7F5), width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(4, (index) {
                      final bool hasChar = index < _enteredCode.length;
                      return SizedBox(
                        width: 32,
                        child: Center(
                          child: Text(
                            hasChar ? _enteredCode[index] : '—',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: hasChar ? const Color(0xFF0F254B) : const Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Numeric Keypad
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKeypadButton('1'),
                          _buildKeypadButton('2'),
                          _buildKeypadButton('3'),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKeypadButton('4'),
                          _buildKeypadButton('5'),
                          _buildKeypadButton('6'),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildKeypadButton('7'),
                          _buildKeypadButton('8'),
                          _buildKeypadButton('9'),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          const SizedBox(width: 84, height: 56), // Blank space
                          _buildKeypadButton('0'),
                          _buildBackspaceButton(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom CTA Button: Next Test
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: canNext ? _onNextTest : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canNext ? const Color(0xFF0848AA) : const Color(0xFFE2E8F0),
                      foregroundColor: canNext ? Colors.white : const Color(0xFF94A3B8),
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

  Widget _buildKeypadButton(String digit) {
    return SizedBox(
      width: 88,
      height: 54,
      child: OutlinedButton(
        onPressed: () => _onKeypadTap(digit),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Text(
          digit,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F254B),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceButton() {
    return SizedBox(
      width: 88,
      height: 54,
      child: OutlinedButton(
        onPressed: _onBackspaceTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: const Icon(
          Icons.backspace_outlined,
          color: Color(0xFF0F254B),
          size: 20,
        ),
      ),
    );
  }
}
