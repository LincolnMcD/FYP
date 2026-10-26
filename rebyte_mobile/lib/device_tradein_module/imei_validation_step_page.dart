import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/device_model.dart';
import 'services/trade_in_service.dart';
import 'services/trade_in_flow_session.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import 'device_info_step_page.dart';
import 'improve_assessment_page.dart';
import '../widgets/device_title_formatter.dart';

class ImeiValidationStepPage extends StatefulWidget {
  final DeviceModel device;
  final String tradeInRequestID;
  final bool isLoggedIn;
  final String? email;
  final String? name;

  const ImeiValidationStepPage({
    super.key,
    required this.device,
    required this.tradeInRequestID,
    this.isLoggedIn = false,
    this.email,
    this.name,
  });

  @override
  State<ImeiValidationStepPage> createState() => _ImeiValidationStepPageState();
}

class _ImeiValidationStepPageState extends State<ImeiValidationStepPage> {
  final TextEditingController _imeiController = TextEditingController();
  bool _isValidating = false;
  bool _isFinalSubmitting = false;
  bool _isValidated = false;
  bool _isMismatch = false;
  String? _detectedModel;
  String? _detectedBrand;
  String? _mismatchType;
  String? _mismatchReason;
  String? _mismatchExpected;
  String? _mismatchDetected;
  String? _imeiError;

  @override
  void initState() {
    super.initState();
    TradeInFlowSession.setCurrentDevice(widget.device);
    if (widget.tradeInRequestID.isNotEmpty) {
      TradeInFlowSession.setTradeInRequestId(widget.tradeInRequestID);
    }
    TradeInFlowSession.currentStep = 4;

    if (widget.device.imeiNum != null && widget.device.imeiNum!.isNotEmpty) {
      _imeiController.text = widget.device.imeiNum!;
      _isValidated = true;
    }
    _imeiController.addListener(_onImeiChanged);
  }

  void _onImeiChanged() {
    final text = _imeiController.text.trim();
    // When text is cleared or modified, clear previous validated / mismatch states
    if (_isValidated || _isMismatch) {
      setState(() {
        _isValidated = false;
        _isMismatch = false;
      });
    }

    // Instant format validation
    if (text.isNotEmpty && text.length < 15) {
      if (_imeiError != 'IMEI must be exactly 15 digits.') {
        setState(() {
          _imeiError = 'IMEI must be exactly 15 digits.';
        });
      }
    } else if (text.length == 15) {
      if (_imeiError != null) {
        setState(() {
          _imeiError = null;
        });
      }
    } else if (text.isEmpty && _imeiError != null) {
      setState(() {
        _imeiError = null;
      });
    }
  }

  @override
  void dispose() {
    _imeiController.removeListener(_onImeiChanged);
    _imeiController.dispose();
    super.dispose();
  }

  void _onValidateImei() async {
    final imei = _imeiController.text.trim();

    // Validate 15-digit IMEI format
    if (imei.isEmpty) {
      setState(() {
        _imeiError = 'Please enter your 15-digit IMEI number.';
        _isValidated = false;
        _isMismatch = false;
      });
      return;
    }

    if (imei.length != 15 || !RegExp(r'^\d{15}$').hasMatch(imei)) {
      setState(() {
        _imeiError = 'IMEI must be exactly 15 digits.';
        _isValidated = false;
        _isMismatch = false;
      });
      return;
    }

    setState(() {
      _isValidating = true;
      _imeiError = null;
    });

    try {
      final result = await TradeInService.validateImei(
        imei: imei,
        expectedBrand: widget.device.brand,
        expectedModel: widget.device.model,
        expectedModelCode: widget.device.modelCode,
        expectedStorage: widget.device.storageCapacity,
        expectedColour: widget.device.colour,
        expectedDeviceAge: widget.device.deviceAge,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final bool isMismatch = result['isMismatch'] == true;
        setState(() {
          _isValidating = false;
          _isMismatch = isMismatch;
          _mismatchType = result['mismatchType'];
          _mismatchReason = result['mismatchReason'];
          _mismatchExpected = result['mismatchExpected']?.toString();
          _mismatchDetected = result['mismatchDetected']?.toString();
          _detectedModel = result['detectedModel'] ?? widget.device.model;
          _detectedBrand = result['detectedBrand'] ?? widget.device.brand;
          _isValidated = !isMismatch;
          _imeiError = null;
        });
      } else {
        setState(() {
          _isValidating = false;
          _imeiError = result['message'] ?? 'Failed to validate IMEI.';
          _isValidated = false;
          _isMismatch = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isValidating = false;
        _imeiError = 'Network error during validation. Please try again.';
        _isValidated = false;
        _isMismatch = false;
      });
    }
  }

  void _onContinueProcess() async {
    setState(() {
      _isFinalSubmitting = true;
    });

    try {
      // 1. If background image upload from Page 3 is still completing, await it
      if (TradeInFlowSession.backgroundUploadFuture != null) {
        await TradeInFlowSession.backgroundUploadFuture;
      }

      final String actualRequestId = TradeInFlowSession.currentTradeInRequestId ?? widget.tradeInRequestID;
      final String enteredImei = _imeiController.text.trim();

      // Update trade-in request in Firestore to 'Submitted' and store IMEI
      await TradeInService.finalizeTradeInRequest(actualRequestId, imeiNum: enteredImei);

      // Update in-memory and persistent session
      TradeInFlowSession.currentUserEmail = widget.email;
      TradeInFlowSession.setTradeInRequestId(actualRequestId);
      TradeInFlowSession.setCurrentDevice(widget.device);
      TradeInFlowSession.lastEnteredImei = enteredImei;
      TradeInFlowSession.currentStep = 5;

      if (!mounted) return;
      setState(() => _isFinalSubmitting = false);

      // Navigate to Page 5: Improve Your Assessment
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImproveAssessmentPage(
            device: widget.device,
            tradeInRequestID: actualRequestId,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFinalSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to continue: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: const ReByteAppBar(),
      drawer: ReByteDrawer(
        isLoggedIn: widget.isLoggedIn,
        email: widget.email,
        name: widget.name,
        selectedIndex: 2,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back Button
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 16),

              // Title
              const Text(
                'Verify Device IMEI',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F254B),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              const Text(
                'Enter the 15-digit International Mobile Equipment Identity number to check device status.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF4B5563),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),

              // Upper Card: Device IMEI Input & Validate button
              _buildImeiInputCard(),
              const SizedBox(height: 20),

              // Device Mismatch Result Card (matches screenshot)
              if (_isMismatch) _buildMismatchResultCard(),

              // Valid and matching result card
              if (_isValidated) _buildValidatedResultCard(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: 2,
      ),
    );
  }

  Widget _buildImeiInputCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          const Text(
            'DEVICE IMEI',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),

          // Text Field
          TextField(
            controller: _imeiController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(15),
            ],
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
              letterSpacing: 0.8,
            ),
            decoration: InputDecoration(
              hintText: 'e.g. 358923145609871',
              hintStyle: const TextStyle(
                fontSize: 14,
                color: Color(0xFF94A3B8),
                letterSpacing: 0,
                fontWeight: FontWeight.normal,
              ),
              errorText: _imeiError,
              errorMaxLines: 3,
              errorStyle: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFFDC2626),
                height: 1.35,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD3D8E2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD3D8E2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF003799), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Tip Box with Info Icon
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: Color(0xFF1D61E7),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.35),
                      children: [
                        const TextSpan(text: 'To find your IMEI, dial '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDBE7FD),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '*#06#',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF003799),
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(text: ' on the\ndevice keypad.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Validate IMEI Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isValidating ? null : _onValidateImei,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003799),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isValidating)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  else ...[
                    const Text(
                      'Validate IMEI',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.check_circle_outline_rounded, size: 18),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidatedResultCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Color(0xFF10B981),
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Green Badge + "Valid and matching"
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF10B981),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Valid and matching',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Brand Row
              _buildDetailRow(
                'Brand',
                widget.device.brand,
              ),
              Divider(color: Colors.grey.shade200, height: 24),

              // Model Row
              _buildDetailRow(
                'Model',
                widget.device.model,
              ),
              Divider(color: Colors.grey.shade200, height: 24),

              // Status Row with "Clean" pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Status',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F8F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Clean',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Continue Process -> Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: _isFinalSubmitting ? null : _onContinueProcess,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFF475569), width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isFinalSubmitting)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)),
                        )
                      else ...[
                        const Text(
                          'Continue Process',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  /// Device Mismatch Card matching the user's requested UI layout and design
  Widget _buildMismatchResultCard() {
    final expectedName = widget.device.displayTitle;
    final detectedName = _detectedModel != null
        ? formatDeviceTitle(_detectedBrand, _detectedModel)
        : 'Unknown Model';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Color(0xFFFF644A), // vibrant coral-orange/red left border accent
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Light circular warning badge + "Device mismatch"
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEECE9), // light pastel reddish-peach circle
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_rounded,
                      color: Color(0xFFEB5744),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Device mismatch',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2C3E50),
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Dynamic Attribute Comparison Rows based on _mismatchType
              Builder(
                builder: (context) {
                  String expectedLabel = 'Expected Model';
                  String detectedLabel = 'Detected Model';
                  String expectedVal = expectedName;
                  String detectedVal = detectedName;

                  final bool isModelMismatch = (_mismatchType == 'model' || _mismatchType == 'modelCode');

                  if (_mismatchType == 'brand') {
                    expectedLabel = 'Quoted Brand';
                    detectedLabel = 'Detected Brand';
                    expectedVal = _mismatchExpected ?? widget.device.brand;
                    detectedVal = _mismatchDetected ?? (_detectedBrand ?? 'Unknown');
                  } else if (isModelMismatch) {
                    expectedLabel = 'Quoted Model';
                    detectedLabel = 'Detected Model';
                    // User requirement: For quoted model just show model name, no need modelCode
                    expectedVal = widget.device.model;
                    detectedVal = _detectedModel ?? 'Unknown Device';
                  } else if (_mismatchType == 'storage') {
                    expectedLabel = 'Quoted Storage';
                    detectedLabel = 'Published Storage';
                    expectedVal = _mismatchExpected ?? widget.device.storageCapacity;
                    detectedVal = _mismatchDetected ?? 'Not available for this model';
                  } else if (_mismatchType == 'color') {
                    expectedLabel = 'Quoted Color';
                    detectedLabel = 'Published Colors';
                    expectedVal = _mismatchExpected ?? widget.device.colour;
                    detectedVal = _mismatchDetected ?? 'Not available for this model';
                  } else if (_mismatchType == 'age') {
                    expectedLabel = 'Quoted Device Age';
                    detectedLabel = 'Maximum Allowed Age';
                    expectedVal = _mismatchExpected ?? (widget.device.deviceAge ?? 'N/A');
                    detectedVal = _mismatchDetected ?? 'Exceeds release date';
                  }

                  return Column(
                    children: [
                      // Quoted / Expected Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(
                              expectedLabel,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              expectedVal,
                              textAlign: TextAlign.end,
                              softWrap: true,
                              overflow: TextOverflow.visible,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Divider(color: Colors.grey.shade200, height: 26),

                      // Detected / Allowed Row (Red highlight)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(
                              detectedLabel,
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              detectedVal,
                              textAlign: TextAlign.end,
                              softWrap: true,
                              overflow: TextOverflow.visible,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFDC2626),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),

              // Red-tinted alert box with justified text
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2), // subtle light rose/red background
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFECDD3), // light pinkish-red border
                    width: 1,
                  ),
                ),
                child: Text(
                  _mismatchReason ??
                      'The scanned IMEI does not match the quoted device specifications. Please verify the device or update the quote.',
                  textAlign: TextAlign.justify,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFBE123C),
                    height: 1.45,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Outlined "Review Quote" button with note/pencil icon
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () {
                    // Ensure session has current device saved
                    TradeInFlowSession.setCurrentDevice(widget.device);
                    // Navigate back to Page 2 (DeviceInfoStepPage) while preserving session
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DeviceInfoStepPage(
                          isLoggedIn: widget.isLoggedIn,
                          email: widget.email,
                          name: widget.name,
                          device: widget.device,
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF59E0B), // warm amber/gold text and border
                    side: const BorderSide(color: Color(0xFFFBBF24), width: 1.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Review Quote',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        Icons.description_outlined,
                        size: 18,
                        color: Color(0xFFF59E0B),
                      ),
                    ],
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
