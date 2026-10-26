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
  final VoidCallback? onTaskUpdated;

  const StaffInspectionSummaryPage({
    super.key,
    required this.task,
    required this.device,
    required this.uploadedImages,
    this.ownershipPhotoPath,
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

  @override
  void initState() {
    super.initState();
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
  }

  Future<void> _initFinalOfferPrice() async {
    final tradeInId = widget.task['tradeInRequestID']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        widget.task['orderID']?.toString() ??
        widget.task['id']?.toString() ??
        '';
    if (tradeInId.isEmpty) return;

    if (widget.task['finalOfferPrice'] != null) {
      final p = double.tryParse(widget.task['finalOfferPrice'].toString());
      if (p != null && p > 0) {
        if (mounted) setState(() => _finalOfferPrice = p);
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

  void _onMarkSuccessful() {
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

    final formattedPrice = NumberFormat('#,##0.00').format(_finalOfferPrice ?? 1350.0);

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
    final formattedPrice = NumberFormat('#,##0.00').format(_finalOfferPrice ?? 1350.0);

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
              finalOfferPrice: _finalOfferPrice ?? 1350.0,
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

                    // 4. Detected Defects Log Card
                    _buildDetectedDefectsCard(),
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

          // IMEI & Battery Health
          Row(
            children: [
              Expanded(
                child: Column(
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
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Battery Health',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: const [
                        Text(
                          '88%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Good',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGradeAndValuationCard() {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: const [
              Text(
                'B+',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 10),
              Text(
                'Good Condition',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
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
                : 'RM 1,350.00',
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
                // EXTERNAL CONDITION
                const Text(
                  'EXTERNAL CONDITION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                _buildDiagnosticRow(
                  Icons.phone_android_outlined,
                  'Screen Glass',
                  'Scratched (Minor)',
                  const Color(0xFF0F172A),
                ),
                const SizedBox(height: 8),
                _buildDiagnosticRow(
                  Icons.crop_portrait_rounded,
                  'Housing/Frame',
                  'Dented (Bottom Left)',
                  const Color(0xFF0F172A),
                ),
                const SizedBox(height: 8),
                _buildDiagnosticRow(
                  Icons.camera_alt_outlined,
                  'Camera Lens',
                  'Perfect',
                  const Color(0xFF16A34A),
                ),

                const SizedBox(height: 18),
                Divider(color: Colors.grey.shade200, height: 1),
                const SizedBox(height: 16),

                // INTERNAL HARDWARE
                const Text(
                  'INTERNAL HARDWARE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                _buildDiagnosticRow(
                  Icons.battery_5_bar_rounded,
                  'Battery Health',
                  '84%',
                  const Color(0xFF0F172A),
                ),
                const SizedBox(height: 8),
                _buildDiagnosticRow(
                  Icons.wifi_rounded,
                  'Connectivity',
                  'Passed',
                  const Color(0xFF16A34A),
                ),
                const SizedBox(height: 8),
                _buildDiagnosticRow(
                  Icons.fingerprint_rounded,
                  'Sensors (FaceID/Touch)',
                  'Passed',
                  const Color(0xFF16A34A),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticRow(
      IconData icon, String label, String value, Color valColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF475569),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valColor,
          ),
        ),
      ],
    );
  }

  Widget _buildDetectedDefectsCard() {
    return Container(
      width: double.infinity,
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
          const Text(
            'Detected Defects log',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _buildDefectCard(
                  'assets/images/defect_lines.jpg',
                  'SCRATCH-01',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDefectCard(
                  'assets/images/defect_dark_spot.jpg',
                  'DENT-FRM-02',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDefectCard(String assetPath, String tag) {
    return Container(
      height: 95,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            assetPath,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: const Color(0xFF334155),
              child: const Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.white60),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: const Color(0xFF334155).withValues(alpha: 0.85),
              alignment: Alignment.center,
              child: Text(
                tag,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
