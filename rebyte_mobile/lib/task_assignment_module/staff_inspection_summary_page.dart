import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../device_tradein_module/models/device_model.dart';
import '../device_tradein_module/services/trade_in_service.dart';
import 'services/task_assignment_service.dart';
import 'staff_trade_in_result_page.dart';
import 'widgets/staff_app_bar_and_drawer.dart';

class StaffInspectionSummaryPage extends StatefulWidget {
  final Map<String, dynamic> task;
  final DeviceModel device;
  final Map<String, String> uploadedImages;
  final String? ownershipPhotoPath;
  final Map<String, dynamic>? evaluation;
  final VoidCallback? onTaskUpdated;

  const StaffInspectionSummaryPage({
    super.key,
    required this.task,
    required this.device,
    required this.uploadedImages,
    this.ownershipPhotoPath,
    this.evaluation,
    this.onTaskUpdated,
  });

  @override
  State<StaffInspectionSummaryPage> createState() =>
      _StaffInspectionSummaryPageState();
}

class _StaffInspectionSummaryPageState
    extends State<StaffInspectionSummaryPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isSubmitting = false;
  double? _finalOfferPrice;
  Map<String, dynamic>? _diagnosticData;
  Map<String, dynamic>? _evaluationData;
  bool _isLoadingEvaluation = false;

  Map<String, dynamic>? get _effectiveEvaluation => _evaluationData ?? widget.evaluation;

  String get _resolvedTradeInId {
    final tId = widget.task['tradeInRequestID']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        widget.task['orderID']?.toString() ??
        widget.task['id']?.toString() ??
        '';
    return tId.replaceAll('#', '').trim();
  }

  @override
  void initState() {
    super.initState();
    _evaluationData = widget.evaluation != null ? Map<String, dynamic>.from(widget.evaluation!) : null;
    final taskId = widget.task['taskID']?.toString() ??
        widget.task['id']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        widget.task['orderID']?.toString() ??
        '';
    StaffInspectionSession.recordPage5(
      taskId: taskId,
      device: widget.device,
      task: widget.task,
      uploadedImages: widget.uploadedImages,
      ownershipPhotoPath: widget.ownershipPhotoPath,
    );

    _initFinalOfferPrice();
    _loadDeviceDiagnostic();
    _loadEvaluationWithSegmentedImages();
  }

  Future<void> _loadEvaluationWithSegmentedImages() async {
    final tradeInId = _resolvedTradeInId;
    if (tradeInId.isEmpty) return;

    // If _evaluationData already has full evaluation info including grade and images, skip
    final hasImages = _evaluationData?['images'] is List && (_evaluationData!['images'] as List).isNotEmpty;
    final hasGrade = _evaluationData?['grade'] != null && _evaluationData!['grade'].toString().isNotEmpty;
    if (hasImages && hasGrade) {
      return;
    }

    setState(() => _isLoadingEvaluation = true);
    try {
      // First try to fetch staffEvaluation
      var eval = await TradeInService.getEvaluation(tradeInId, source: 'staffEvaluation');
      eval ??= await TradeInService.getEvaluation(tradeInId);
      if (eval != null && mounted) {
        setState(() {
          _evaluationData = eval;
          _isLoadingEvaluation = false;
        });
        // Check if evaluation contains diagnosticID or deviceID to reload diagnostic if missing
        if (_diagnosticData == null) {
          final diagId = eval['diagnosticID']?.toString();
          if (diagId != null && diagId.isNotEmpty && diagId.toUpperCase() != 'NULL') {
            _loadDeviceDiagnostic();
          }
        }
      } else if (mounted) {
        setState(() => _isLoadingEvaluation = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingEvaluation = false);
    }
  }

  Future<void> _loadDeviceDiagnostic() async {
    final devId = widget.device.deviceID.isNotEmpty
        ? widget.device.deviceID
        : (widget.task['deviceID']?.toString() ??
            (widget.task['device'] is Map ? widget.task['device']['deviceID']?.toString() : null) ??
            (_effectiveEvaluation?['deviceID']?.toString()) ??
            '');
    if (devId.isEmpty) return;

    try {
      final diag = await TradeInService.getDeviceDiagnostic(devId);
      if (mounted) {
        setState(() {
          _diagnosticData = diag;
        });
      }
    } catch (_) {}
  }

  Future<void> _initFinalOfferPrice() async {
    final tradeInId = _resolvedTradeInId;
    if (tradeInId.isEmpty) return;

    if (widget.task['finalOfferPrice'] != null) {
      final p = double.tryParse(widget.task['finalOfferPrice'].toString());
      if (p != null && p > 0) {
        if (mounted) setState(() => _finalOfferPrice = p);
        return;
      }
    }

    try {
      final res = await TradeInService.setStaffFinalOfferPrice(
        tradeInRequestID: tradeInId,
      );
      if (!mounted) return;
      if (res['success'] == true && res['finalOfferPrice'] != null) {
        final price = double.tryParse(res['finalOfferPrice'].toString());
        if (price != null && price > 0) {
          setState(() {
            _finalOfferPrice = price;
            widget.task['finalOfferPrice'] = price;
          });
        }
      }
    } catch (_) {}
  }

  void _backToMap() {
    Navigator.popUntil(context, (route) {
      return route.settings.name == 'StaffNavigationPage' || route.isFirst;
    });
  }

  Future<void> _onMarkSuccessful() async {
    if (_finalOfferPrice == null) {
      await _initFinalOfferPrice();
    }
    if (_finalOfferPrice == null) {
      if (mounted) {
        StaffToast.show(
          context,
          'The ML offer price is not available yet. Please try again before confirming.',
          isError: true,
        );
      }
      return;
    }
    _showConfirmSuccessfulDialog();
  }

  void _onMarkUnsuccessful() {
    _showConfirmUnsuccessfulDialog();
  }

  void _showConfirmSuccessfulDialog() {
    final modelName = widget.device.model.isNotEmpty
        ? widget.device.model
        : (widget.task['model']?.toString() ?? 'Device');
    final storage = widget.device.storageCapacity.isNotEmpty
        ? widget.device.storageCapacity
        : (widget.task['storage']?.toString() ?? '');
    final color = widget.device.colour.isNotEmpty
        ? widget.device.colour
        : (widget.task['colour']?.toString() ?? widget.task['color']?.toString() ?? '');
    final imei = widget.device.imeiNum ??
        widget.task['imei']?.toString() ??
        widget.task['imeiNum']?.toString() ??
        'N/A';
    final tradeInId = widget.task['tradeInRequestID']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        widget.task['orderID']?.toString() ??
        widget.task['id']?.toString() ??
        '';

    final formattedPrice = NumberFormat('#,##0.00').format(_finalOfferPrice!);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Confirm Trade-In',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please review the transaction valuation and trade-in details before finalizing.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 16),

            // Valuation highlight box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TRANSACTION PAYOUT PRICE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4F46E5),
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'RM $formattedPrice',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0043CE),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Basic Details Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _buildDialogDetailRow('Device', modelName),
                  const Divider(height: 16, thickness: 0.8, color: Color(0xFFE2E8F0)),
                  _buildDialogDetailRow('Storage', storage.isNotEmpty ? storage : 'N/A'),
                  const Divider(height: 16, thickness: 0.8, color: Color(0xFFE2E8F0)),
                  _buildDialogDetailRow('Color', color.isNotEmpty ? color : 'N/A'),
                  const Divider(height: 16, thickness: 0.8, color: Color(0xFFE2E8F0)),
                  _buildDialogDetailRow('IMEI', imei),
                  const Divider(height: 16, thickness: 0.8, color: Color(0xFFE2E8F0)),
                  _buildDialogDetailRow('tradeInRequestID', tradeInId.isNotEmpty ? '#$tradeInId' : 'N/A'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _executeFinalizeInspection(isSuccessful: true);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: const Color(0xFF0043CE),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Confirm & Pay',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showConfirmUnsuccessfulDialog() {
    final modelName = widget.device.model.isNotEmpty
        ? widget.device.model
        : (widget.task['model']?.toString() ?? 'Device');
    final tradeInId = widget.task['tradeInRequestID']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        widget.task['orderID']?.toString() ??
        widget.task['id']?.toString() ??
        '';
    final formattedPrice = _finalOfferPrice == null
        ? 'Unavailable'
        : NumberFormat('#,##0.00').format(_finalOfferPrice!);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFEE2E2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Reject Trade-In?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to mark this trade-in inspection as unsuccessful? The trade-in will be marked as Rejected and the device will be returned to the customer.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 16),

            // Basic Details Card (Device, tradeInRequestID, Final Offer)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _buildDialogDetailRow('Device', modelName),
                  const Divider(height: 16, thickness: 0.8, color: Color(0xFFE2E8F0)),
                  _buildDialogDetailRow('tradeInRequestID', tradeInId.isNotEmpty ? '#$tradeInId' : 'N/A'),
                  const Divider(height: 16, thickness: 0.8, color: Color(0xFFE2E8F0)),
                  _buildDialogDetailRow('Final Offer', 'RM $formattedPrice'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _executeFinalizeInspection(isSuccessful: false);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Confirm Reject',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDialogDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _executeFinalizeInspection({required bool isSuccessful}) async {
    setState(() => _isSubmitting = true);

    final taskId = widget.task['taskID']?.toString() ??
        widget.task['id']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        widget.task['orderID']?.toString() ??
        '';

    final orderId = widget.task['orderID']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        taskId;
    final scheduleId = widget.task['scheduleID']?.toString();
    final tradeInId = widget.task['tradeInRequestID']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        orderId;

    try {
      final res = await TaskAssignmentService.finalizeInspection(
        tradeInRequestID: tradeInId,
        taskID: taskId,
        orderID: orderId,
        scheduleID: scheduleId,
        isSuccessful: isSuccessful,
        finalOfferPrice: _finalOfferPrice,
        rejectionReason: isSuccessful ? null : 'Inspection failed or rejected by staff/customer',
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (res['success'] == true) {
        widget.onTaskUpdated?.call();
        StaffInspectionSession.clear();

        final modelName = widget.device.model.isNotEmpty
            ? widget.device.model
            : (widget.task['model']?.toString() ?? 'Device');

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StaffTradeInResultPage(
              isSuccessful: isSuccessful,
              finalOfferPrice: _finalOfferPrice ?? 0,
              tradeInRequestID: tradeInId,
              deviceModel: modelName,
            ),
          ),
        );
      } else {
        StaffToast.show(
          context,
          res['message']?.toString() ?? 'Failed to finalize inspection. Please try again.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        StaffToast.show(context, 'Error: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelName = widget.device.model.isNotEmpty
        ? widget.device.model
        : (widget.task['model']?.toString() ?? 'iPhone 13 Pro');
    final storage = widget.device.storageCapacity.isNotEmpty
        ? widget.device.storageCapacity
        : (widget.task['storage']?.toString() ?? '256GB');
    final color = widget.device.colour.isNotEmpty
        ? widget.device.colour
        : (widget.task['colour']?.toString() ?? widget.task['color']?.toString() ?? 'Sierra Blue');
    final imei = widget.device.imeiNum ??
        widget.task['imei']?.toString() ??
        widget.task['imeiNum']?.toString() ??
        '35 842109 765432 1';

    // Format IMEI with spaces if it's 15 digits
    String formattedImei = imei;
    if (imei.length == 15) {
      formattedImei =
          '${imei.substring(0, 2)} ${imei.substring(2, 8)} ${imei.substring(8, 14)} ${imei.substring(14)}';
    }

    final frontImgPath = widget.uploadedImages['front'] ??
        widget.uploadedImages['front_screen_open'] ??
        widget.uploadedImages['front_screen_closed'] ??
        widget.task['imageUrl']?.toString() ??
        widget.task['deviceImage']?.toString();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _backToMap();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: StaffAppBar(scaffoldKey: _scaffoldKey),
        drawer: const StaffDrawer(selectedIndex: 2),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Back arrow
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                        onPressed: _backToMap,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const SizedBox(height: 12),

                    // Title
                    const Text(
                      'Inspection Summary',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Subtitle
                    const Text(
                      'Review final diagnostic results and valuation before submission.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // 1. Device Info Card
                    _buildDeviceCard(
                      modelName: modelName,
                      storage: storage,
                      color: color,
                      imei: formattedImei,
                      frontImgPath: frontImgPath,
                    ),
                    const SizedBox(height: 16),

                    // 2. Final Assigned Grade & Estimated Valuation Card
                    _buildGradeAndValuationCard(),
                    const SizedBox(height: 16),

                    // 3. Diagnostic Summary Card
                    _buildDiagnosticSummaryCard(),
                    const SizedBox(height: 16),

                    // 4. Segmented / Inspection Photos Card
                    _buildSegmentedPhotosCard(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Bottom Buttons Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _onMarkSuccessful,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.verified_outlined, size: 20, color: Colors.white),
                      label: const Text(
                        'Mark Trade-In Successful',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0043CE),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: _onMarkUnsuccessful,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: const Text(
                        'Mark Trade-In Unsuccessful',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
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

  Widget _buildDeviceCard({
    required String modelName,
    required String storage,
    required String color,
    required String imei,
    String? frontImgPath,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
          // Top row with Verification Passed badge
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF16A34A)),
                    SizedBox(width: 4),
                    Text(
                      'Verification Passed',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Device Thumbnail & Title
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
              ),
              child: frontImgPath != null &&
                      (frontImgPath.startsWith('http') || File(frontImgPath).existsSync())
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: frontImgPath.startsWith('http')
                          ? Image.network(
                              frontImgPath,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => const Center(
                                child: Icon(Icons.broken_image, color: Colors.grey),
                              ),
                            )
                          : Image.file(File(frontImgPath), fit: BoxFit.contain),
                    )
                  : const Center(
                      child: Icon(
                        Icons.phone_iphone_rounded,
                        size: 52,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // Model & Storage
          Row(
            children: [
              Text(
                modelName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  storage,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Color
          Text(
            color,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),

          // IMEI
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'IMEI',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                imei,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGradeAndValuationCard() {
    final grade = _effectiveEvaluation?['grade']?.toString() ??
        widget.task['grade']?.toString() ??
        widget.task['evaluationGrade']?.toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF0043CE),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0043CE).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Final Assigned Grade',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            grade == null || grade.isEmpty ? '—' : grade,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 16),
          const Text(
            'ESTIMATED VALUATION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white70,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _finalOfferPrice != null
                ? 'RM ${NumberFormat('#,##0.00').format(_finalOfferPrice)}'
                : 'Pricing unavailable',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticSummaryCard() {
    // 3-Part Summary: Screen, Back, Frame damage coverage %
    final Map<String, dynamic>? parts = _effectiveEvaluation?['parts'] is Map<String, dynamic>
        ? _effectiveEvaluation!['parts'] as Map<String, dynamic>
        : (_effectiveEvaluation?['parts'] is Map
            ? Map<String, dynamic>.from(_effectiveEvaluation!['parts'] as Map)
            : null);

    final screenData = parts?['screen'] ?? _effectiveEvaluation?['screen'];
    final backData = parts?['back'] ?? _effectiveEvaluation?['back'];
    final frameData = parts?['frame'] ?? _effectiveEvaluation?['frame'];

    double getDmgCoverage(dynamic part) {
      if (part is Map) {
        final cov = part['dmgCoverage'] ?? part['coverage'];
        if (cov is num) return cov.toDouble();
        if (cov != null) return double.tryParse(cov.toString()) ?? 0.0;
      }
      return 0.0;
    }

    final double screenCov = getDmgCoverage(screenData);
    final double backCov = getDmgCoverage(backData);
    final double frameCov = getDmgCoverage(frameData);

    // Internal Diagnostic
    final String? diagnosticId = _effectiveEvaluation?['diagnosticID']?.toString();
    final bool hasDiagnostic = (diagnosticId != null &&
            diagnosticId.trim().isNotEmpty &&
            diagnosticId.trim().toUpperCase() != 'NULL' &&
            _diagnosticData != null) ||
        _diagnosticData != null;

    final diag = hasDiagnostic ? _diagnosticData : null;

    final List<Map<String, dynamic>> components = [
      {
        'title': 'Touchscreen',
        'icon': Icons.touch_app_rounded,
        'mark': diag?['touchScreenMark'],
      },
      {
        'title': 'Display Panel',
        'icon': Icons.smartphone_rounded,
        'mark': diag?['displayMark'],
      },
      {
        'title': 'Camera System',
        'icon': Icons.camera_alt_outlined,
        'mark': diag?['cameraMark'],
      },
      {
        'title': 'Microphone',
        'icon': Icons.mic_none_rounded,
        'mark': diag?['microphoneMark'],
      },
      {
        'title': 'Speaker & Audio',
        'icon': Icons.volume_up_outlined,
        'mark': diag?['speakerMark'],
      },
      {
        'title': 'Sensors',
        'icon': Icons.sensors_rounded,
        'mark': diag?['sensorMark'],
      },
      {
        'title': 'Network & Connectivity',
        'icon': Icons.wifi_rounded,
        'mark': diag?['connectivityMark'],
      },
      {
        'title': 'GPS Location',
        'icon': Icons.location_on_outlined,
        'mark': diag?['gpsMark'],
      },
    ];

    final int? diagScore = diag?['diagnosticScore'] is num
        ? (diag!['diagnosticScore'] as num).toInt()
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
          // Header Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: const [
                Icon(Icons.explore_outlined, size: 20, color: Color(0xFF0043CE)),
                SizedBox(width: 8),
                Text(
                  'Diagnostic Summary',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // EXTERNAL CONDITION HEADER
                Row(
                  children: [
                    const Text(
                      'EXTERNAL CONDITION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Tap part for details',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 3-PART EXTERNAL SUMMARY
                Row(
                  children: [
                    Expanded(
                      child: _buildPartSummaryItem(
                        partKey: 'screen',
                        title: 'Screen',
                        icon: Icons.phone_android_rounded,
                        dmgCoverage: screenCov,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildPartSummaryItem(
                        partKey: 'back',
                        title: 'Back',
                        icon: Icons.flip_to_back_rounded,
                        dmgCoverage: backCov,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildPartSummaryItem(
                        partKey: 'frame',
                        title: 'Frame',
                        icon: Icons.crop_portrait_rounded,
                        dmgCoverage: frameCov,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                Divider(color: Colors.grey.shade200, height: 1),
                const SizedBox(height: 16),

                // INTERNAL HARDWARE HEADER
                Row(
                  children: [
                    const Text(
                      'INTERNAL HARDWARE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: hasDiagnostic ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: hasDiagnostic ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        hasDiagnostic && diagScore != null ? 'Score: $diagScore/100' : 'Score: N/A',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: hasDiagnostic ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                if (!hasDiagnostic)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No internal diagnostic test record associated with this evaluation (N/A).',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...components.asMap().entries.map((entry) {
                    final int index = entry.key;
                    final item = entry.value;

                    final dynamic markVal = item['mark'];
                    final int score = (markVal is num)
                        ? markVal.toInt()
                        : (markVal != null ? int.tryParse(markVal.toString()) ?? 100 : 100);
                    final String scoreText = '$score%';

                    String statusText;
                    Color statusColor;
                    Color statusBgColor;
                    IconData statusIcon;

                    if (score >= 80) {
                      statusText = 'Pass';
                      statusColor = const Color(0xFF10B981);
                      statusBgColor = const Color(0xFFECFDF5);
                      statusIcon = Icons.check_circle_outline_rounded;
                    } else if (score >= 50) {
                      statusText = 'Degraded';
                      statusColor = const Color(0xFFD97706);
                      statusBgColor = const Color(0xFFFFFBEB);
                      statusIcon = Icons.error_outline_rounded;
                    } else {
                      statusText = 'Fail';
                      statusColor = const Color(0xFFDC2626);
                      statusBgColor = const Color(0xFFFEF2F2);
                      statusIcon = Icons.cancel_outlined;
                    }

                    return Column(
                      children: [
                        Row(
                          children: [
                            Icon(item['icon'] as IconData, size: 18, color: const Color(0xFF475569)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item['title'] as String,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            Text(
                              scoreText,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusBgColor,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon, size: 12, color: statusColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (index < components.length - 1)
                          const Divider(height: 18, color: Color(0xFFF1F5F9)),
                      ],
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartSummaryItem({
    required String partKey,
    required String title,
    required IconData icon,
    required double dmgCoverage,
  }) {
    final double dmgPct = (dmgCoverage * 100.0).clamp(0.0, 100.0);
    final String pctText = '${dmgPct.toStringAsFixed(2)}%';
    final bool hasDamage = dmgPct > 0.05;

    final Color statusColor = hasDamage
        ? (dmgPct > 5.0 ? const Color(0xFFDC2626) : const Color(0xFFD97706))
        : const Color(0xFF10B981);
    final Color bgColor = hasDamage
        ? (dmgPct > 5.0 ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB))
        : const Color(0xFFF0FDF4);

    return InkWell(
      onTap: () => _showPartDefectsDialog(partKey: partKey, partTitle: title),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: statusColor),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pctText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: statusColor,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hasDamage ? 'Damage Cov.' : 'Intact',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: statusColor.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 8,
                  color: statusColor.withValues(alpha: 0.6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase().trim()) {
      case 'critical':
        return const Color(0xFFDC2626);
      case 'major':
        return const Color(0xFFEA580C);
      case 'minor':
        return const Color(0xFFD97706);
      case 'low':
        return const Color(0xFF0284C7);
      case 'none':
      default:
        return const Color(0xFF10B981);
    }
  }

  void _showSeverityRankingDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final rankings = [
          {
            'level': 'Critical',
            'color': const Color(0xFFDC2626),
            'bgColor': const Color(0xFFFEF2F2),
            'icon': Icons.dangerous_rounded,
            'desc': 'Deep cracks, extensive shattered areas, or damage that impairs device function or touch response.',
          },
          {
            'level': 'Major',
            'color': const Color(0xFFEA580C),
            'bgColor': const Color(0xFFFFF7ED),
            'icon': Icons.warning_rounded,
            'desc': 'Noticeable cracks, deep scratches, or distinct discolouration patches clearly visible at arm’s length.',
          },
          {
            'level': 'Minor',
            'color': const Color(0xFFD97706),
            'bgColor': const Color(0xFFFFFBEB),
            'icon': Icons.error_outline_rounded,
            'desc': 'Light surface scratches, hairline marks, or slight cosmetic wear that does not affect functionality.',
          },
          {
            'level': 'Low',
            'color': const Color(0xFF0284C7),
            'bgColor': const Color(0xFFF0F9FF),
            'icon': Icons.info_outline_rounded,
            'desc': 'Micro-scratches or faint signs of handling visible only under direct angled light inspection.',
          },
          {
            'level': 'None',
            'color': const Color(0xFF10B981),
            'bgColor': const Color(0xFFF0FDF4),
            'icon': Icons.check_circle_outline_rounded,
            'desc': 'Pristine surface with zero detected cosmetic blemishes or structural anomalies.',
          },
        ];

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.help_outline_rounded,
                          color: Color(0xFF0C5AD2),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Severity Ranking Guide',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Defect severity classifications explained',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                        onPressed: () => Navigator.of(ctx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Ranking list
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: rankings.map((r) {
                      final Color col = r['color'] as Color;
                      final Color bg = r['bgColor'] as Color;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: col.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(r['icon'] as IconData, size: 20, color: col),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r['level'] as String,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: col,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    r['desc'] as String,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF475569),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Close Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C5AD2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPartDefectsDialog({
    required String partKey,
    required String partTitle,
  }) {
    // Collect defect types for this specific part
    final List<Map<String, dynamic>> defectConfig;
    if (partKey == 'screen') {
      defectConfig = [
        {'key': 'screenCrack', 'title': 'Crack', 'icon': Icons.bolt_rounded},
        {'key': 'screenDiscolouration', 'title': 'Discolouration', 'icon': Icons.palette_outlined},
        {'key': 'screenScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
      ];
    } else if (partKey == 'back') {
      defectConfig = [
        {'key': 'backCrack', 'title': 'Crack', 'icon': Icons.bolt_rounded},
        {'key': 'backScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
      ];
    } else {
      // frame
      defectConfig = [
        {'key': 'frameScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
        {'key': 'frameDent', 'title': 'Dent', 'icon': Icons.radio_button_checked_rounded},
      ];
    }

    final eval = _effectiveEvaluation;
    final Map<String, dynamic>? classes = eval?['classes'] is Map
        ? Map<String, dynamic>.from(eval!['classes'] as Map)
        : null;

    final List<Map<String, dynamic>> pages = defectConfig.map((cfg) {
      final key = cfg['key'] as String;
      final dynamic raw = classes?[key] ?? eval?[key];

      int count = 0;
      double? area;
      double? coverage;
      String severity = 'None';

      if (raw is Map) {
        if (raw['count'] is num) count = (raw['count'] as num).toInt();
        if (raw['area'] is num) area = (raw['area'] as num).toDouble();
        if (raw['coverage'] is num) coverage = (raw['coverage'] as num).toDouble();
        if (raw['severity'] != null && raw['severity'].toString().isNotEmpty) {
          severity = raw['severity'].toString();
        }
      }

      final bool isCrack = (cfg['title'] == 'Crack') || key.toLowerCase().contains('crack');

      return {
        'title': '$partTitle ${cfg['title']}',
        'defectType': cfg['title'] as String,
        'icon': cfg['icon'] as IconData,
        'isCrack': isCrack,
        'count': count,
        'area': area,
        'coverage': coverage,
        'severity': count > 0 ? severity : 'None',
      };
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) {
        final PageController pageController = PageController();
        int activePage = 0;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 520, maxWidth: 420),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dialog Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.analytics_outlined,
                              color: Color(0xFF0C5AD2),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$partTitle Defect Breakdown',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Swipe left / right to view each defect',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                GestureDetector(
                                  onTap: _showSeverityRankingDialog,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFBFDBFE)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.help_outline_rounded, color: Color(0xFF0C5AD2), size: 13),
                                        SizedBox(width: 4),
                                        Text(
                                          'Severity Ranking',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0C5AD2),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                            onPressed: () => Navigator.of(ctx).pop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),

                    // Page Indicator Dots
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(pages.length, (i) {
                          final isCurrent = i == activePage;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 6,
                            width: isCurrent ? 22 : 6,
                            decoration: BoxDecoration(
                              color: isCurrent ? const Color(0xFF0C5AD2) : const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),

                    // Swipeable PageView with defect details
                    Flexible(
                      child: SizedBox(
                        height: 380,
                        child: PageView.builder(
                          controller: pageController,
                          itemCount: pages.length,
                          onPageChanged: (i) {
                            setDialogState(() {
                              activePage = i;
                            });
                          },
                          itemBuilder: (context, idx) {
                            final page = pages[idx];
                            final int count = page['count'] as int;
                            final double? area = page['area'] as double?;
                            final double? coverage = page['coverage'] as double?;
                            final String severity = page['severity'] as String;
                            final bool hasDefect = count > 0;

                            final Color statusColor = hasDefect
                                ? _getSeverityColor(severity)
                                : const Color(0xFF10B981);

                            return SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Defect Category Badge & Icon
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: (page['isCrack'] == true)
                                          ? CustomPaint(
                                              size: const Size(28, 28),
                                              painter: _CrackPainter(color: statusColor),
                                            )
                                          : Icon(
                                              page['icon'] as IconData,
                                              size: 28,
                                              color: statusColor,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Defect Title
                                  Text(
                                    page['title'] as String,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      hasDefect ? '$count Detected' : 'No Defects Detected',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),

                                  // 4 Detail Grid Blocks: Count, Area, Severity, Coverage
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Count',
                                          value: '$count',
                                          icon: Icons.tag_rounded,
                                          valueColor: statusColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Severity',
                                          value: severity,
                                          icon: Icons.shield_outlined,
                                          valueColor: statusColor,
                                          onHelpTap: _showSeverityRankingDialog,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Damage Area',
                                          value: area != null ? '${area.toStringAsFixed(2)} cm²' : '0.00 cm²',
                                          icon: Icons.aspect_ratio_rounded,
                                          valueColor: const Color(0xFF1E293B),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Coverage',
                                          value: coverage != null
                                              ? '${(coverage * 100).toStringAsFixed(2)}%'
                                              : '0.00%',
                                          icon: Icons.pie_chart_outline_rounded,
                                          valueColor: const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Bottom helper status text
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          hasDefect ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded,
                                          size: 16,
                                          color: statusColor,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            hasDefect
                                                ? 'Detected during AI surface assessment. Severity level evaluated as $severity.'
                                                : 'Zero $partTitle ${page['defectType']} defects found during evaluation.',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF64748B),
                                              height: 1.35,
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

                    // Swipe Navigation controls
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: activePage > 0
                                ? () {
                                    pageController.previousPage(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_left_rounded, size: 20),
                            label: const Text('Previous', style: TextStyle(fontSize: 12.5)),
                          ),
                          Text(
                            '${activePage + 1} of ${pages.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: activePage < pages.length - 1
                                ? () {
                                    pageController.nextPage(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                            icon: const Text('Next', style: TextStyle(fontSize: 12.5)),
                            label: const Icon(Icons.chevron_right_rounded, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDefectMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color valueColor,
    VoidCallback? onHelpTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF64748B)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              if (onHelpTap != null)
                GestureDetector(
                  onTap: onHelpTap,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.help_outline_rounded,
                      size: 13,
                      color: Color(0xFF0C5AD2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildSegmentedPhotosCard() {
    // 1. Check for segmented evaluation images in _effectiveEvaluation
    final List<Map<String, dynamic>> evalImages = [];
    final rawImages = _effectiveEvaluation?['images'];
    if (rawImages is List) {
      for (final img in rawImages) {
        if (img is Map) {
          evalImages.add(Map<String, dynamic>.from(img));
        }
      }
    }

    // 2. Local/uploaded staff photos fallback
    final List<Map<String, String>> localPhotos = [];
    for (final entry in widget.uploadedImages.entries) {
      if (entry.value.isNotEmpty) {
        localPhotos.add({
          'key': entry.key,
          'path': entry.value,
        });
      }
    }

    final bool hasEvalImages = evalImages.isNotEmpty;
    final int itemCount = hasEvalImages ? evalImages.length : localPhotos.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
          const Text(
            'Segmented & Inspection Photos',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          if (itemCount > 0) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$itemCount photos (tap to zoom)',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),

          if (_isLoadingEvaluation)
            const SizedBox(
              height: 130,
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0043CE)),
              ),
            )
          else if (itemCount == 0)
            Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Text(
                  'No inspection photos available',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            // Horizontal scrollable list showing initial 2 photos in view
            LayoutBuilder(
              builder: (context, constraints) {
                // Show 2 items in default view with gap of 12
                final double itemWidth = (constraints.maxWidth - 12) / 2;
                return SizedBox(
                  height: 130,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: itemCount,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      String? url;
                      String? filePath;
                      String caption = 'Photo ${index + 1}';

                      if (hasEvalImages) {
                        final imgObj = evalImages[index];
                        url = imgObj['imageUrl']?.toString() ?? imgObj['originalImageUrl']?.toString();
                        final view = imgObj['imageView']?.toString();
                        if (view != null && view.isNotEmpty) {
                          caption = view.replaceAll('_', ' ').toUpperCase();
                        }
                      } else {
                        final item = localPhotos[index];
                        final rawPath = item['path']!;
                        if (rawPath.startsWith('http')) {
                          url = rawPath;
                        } else {
                          filePath = rawPath;
                        }
                        caption = item['key']!.replaceAll('_', ' ').toUpperCase();
                      }

                      return SizedBox(
                        width: itemWidth,
                        child: GestureDetector(
                          onTap: () {
                            _showImagePreviewDialog(
                              imageUrl: url,
                              filePath: filePath,
                              title: caption,
                            );
                          },
                          child: _buildPhotoThumbCard(
                            imageUrl: url,
                            filePath: filePath,
                            caption: caption,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoThumbCard({
    String? imageUrl,
    String? filePath,
    required String caption,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_rounded, color: Color(0xFF94A3B8)),
              ),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            )
          else if (filePath != null && filePath.isNotEmpty && File(filePath).existsSync())
            Image.file(
              File(filePath),
              fit: BoxFit.cover,
            )
          else
            Container(
              color: const Color(0xFFE2E8F0),
              child: const Center(
                child: Icon(Icons.smartphone_rounded, size: 36, color: Color(0xFF94A3B8)),
              ),
            ),

          // Caption overlay banner
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              color: Colors.black.withValues(alpha: 0.6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.zoom_in, color: Colors.white, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showImagePreviewDialog({
    String? imageUrl,
    String? filePath,
    required String title,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 600),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                        onPressed: () => Navigator.of(ctx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF334155)),

                // Interactive zoomable image
                Flexible(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Center(
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(
                                  child: CircularProgressIndicator(color: Colors.white),
                                );
                              },
                              errorBuilder: (_, __, ___) => const Center(
                                child: Text('Failed to load image', style: TextStyle(color: Colors.white70)),
                              ),
                            )
                          : (filePath != null && File(filePath).existsSync()
                              ? Image.file(File(filePath), fit: BoxFit.contain)
                              : const Center(
                                  child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 60),
                                )),
                    ),
                  ),
                ),

                // Footer hint
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Pinch or double tap to zoom',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CrackPainter extends CustomPainter {
  final Color color;

  const _CrackPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.miter
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    // Main crack trunk - erratic zigzag line from top to bottom
    final mainPath = Path();
    mainPath.moveTo(w * 0.32, h * 0.08);
    mainPath.lineTo(w * 0.44, h * 0.18);
    mainPath.lineTo(w * 0.38, h * 0.28);
    mainPath.lineTo(w * 0.50, h * 0.38);
    mainPath.lineTo(w * 0.46, h * 0.48);
    mainPath.lineTo(w * 0.38, h * 0.58);
    mainPath.lineTo(w * 0.44, h * 0.68);
    mainPath.lineTo(w * 0.40, h * 0.74);
    mainPath.lineTo(w * 0.50, h * 0.82);
    mainPath.lineTo(w * 0.64, h * 0.94);
    canvas.drawPath(mainPath, paint);

    // Left branch 1 (top left fissure)
    final bLeft1 = Path();
    bLeft1.moveTo(w * 0.38, h * 0.16);
    bLeft1.lineTo(w * 0.32, h * 0.26);
    bLeft1.lineTo(w * 0.18, h * 0.32);
    canvas.drawPath(bLeft1, paint);

    // Left branch 2 (mid left horizontal fork)
    final bLeft2 = Path();
    bLeft2.moveTo(w * 0.46, h * 0.48);
    bLeft2.lineTo(w * 0.34, h * 0.46);
    bLeft2.lineTo(w * 0.24, h * 0.40);
    canvas.drawPath(bLeft2, paint);

    // Left branch 3 (bottom left fork)
    final bLeft3 = Path();
    bLeft3.moveTo(w * 0.40, h * 0.74);
    bLeft3.lineTo(w * 0.30, h * 0.78);
    bLeft3.lineTo(w * 0.34, h * 0.88);
    canvas.drawPath(bLeft3, paint);

    // Right branch 1 (top right sharp shoot)
    final bRight1 = Path();
    bRight1.moveTo(w * 0.48, h * 0.28);
    bRight1.lineTo(w * 0.64, h * 0.20);
    canvas.drawPath(bRight1, paint);

    // Right branch 2 (upper-mid right meandering crack)
    final bRight2 = Path();
    bRight2.moveTo(w * 0.42, h * 0.36);
    bRight2.lineTo(w * 0.56, h * 0.32);
    bRight2.lineTo(w * 0.74, h * 0.34);
    bRight2.lineTo(w * 0.76, h * 0.44);
    bRight2.lineTo(w * 0.66, h * 0.52);
    bRight2.lineTo(w * 0.64, h * 0.60);
    canvas.drawPath(bRight2, paint);

    // Right branch 3 (bottom right fork)
    final bRight3 = Path();
    bRight3.moveTo(w * 0.64, h * 0.60);
    bRight3.lineTo(w * 0.58, h * 0.68);
    canvas.drawPath(bRight3, paint);

    final bRight4 = Path();
    bRight4.moveTo(w * 0.64, h * 0.60);
    bRight4.lineTo(w * 0.70, h * 0.70);
    canvas.drawPath(bRight4, paint);
  }

  @override
  bool shouldRepaint(covariant _CrackPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
