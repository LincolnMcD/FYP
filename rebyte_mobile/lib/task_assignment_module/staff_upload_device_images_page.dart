import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../device_tradein_module/models/device_model.dart';
import '../device_tradein_module/services/trade_in_service.dart';
import 'widgets/staff_app_bar_and_drawer.dart';
import 'staff_verify_device_information_page.dart';

enum StaffImageSlotStatus {
  empty,
  uploading,
  success,
  error,
  notPhoneDetected,
}

class StaffImageSlot {
  final String keyName;
  final String label;
  final bool isOptional;
  final bool hasInfo;
  final String? infoMessage;
  final String? localFilePath;
  final String? fileName;
  final StaffImageSlotStatus status;
  final double uploadProgress;
  final String? errorMessage;

  const StaffImageSlot({
    required this.keyName,
    required this.label,
    this.isOptional = false,
    this.hasInfo = false,
    this.infoMessage,
    this.localFilePath,
    this.fileName,
    this.status = StaffImageSlotStatus.empty,
    this.uploadProgress = 0.0,
    this.errorMessage,
  });

  StaffImageSlot copyWith({
    String? keyName,
    String? label,
    bool? isOptional,
    bool? hasInfo,
    String? infoMessage,
    String? localFilePath,
    String? fileName,
    StaffImageSlotStatus? status,
    double? uploadProgress,
    String? errorMessage,
  }) {
    return StaffImageSlot(
      keyName: keyName ?? this.keyName,
      label: label ?? this.label,
      isOptional: isOptional ?? this.isOptional,
      hasInfo: hasInfo ?? this.hasInfo,
      infoMessage: infoMessage ?? this.infoMessage,
      localFilePath: localFilePath ?? this.localFilePath,
      fileName: fileName ?? this.fileName,
      status: status ?? this.status,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  StaffImageSlot reset() {
    return StaffImageSlot(
      keyName: keyName,
      label: label,
      isOptional: isOptional,
      hasInfo: hasInfo,
      infoMessage: infoMessage,
      status: StaffImageSlotStatus.empty,
      localFilePath: null,
      fileName: null,
      uploadProgress: 0.0,
      errorMessage: null,
    );
  }
}

class StaffUploadDeviceImagesPage extends StatefulWidget {
  final Map<String, dynamic> task;
  final DeviceModel device;
  final VoidCallback? onTaskUpdated;

  const StaffUploadDeviceImagesPage({
    super.key,
    required this.task,
    required this.device,
    this.onTaskUpdated,
  });

  @override
  State<StaffUploadDeviceImagesPage> createState() =>
      _StaffUploadDeviceImagesPageState();
}

class _StaffUploadDeviceImagesPageState
    extends State<StaffUploadDeviceImagesPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ImagePicker _picker = ImagePicker();

  late List<StaffImageSlot> _slots;
  final Map<int, int> _slotTokens = {};
  bool _isUploadingToServer = false;

  bool get _areRequiredImagesUploaded =>
      _slots.length >= 7 &&
      _slots.sublist(0, 7).every(
            (s) => s.status == StaffImageSlotStatus.success && s.localFilePath != null,
          );

  @override
  void initState() {
    super.initState();
    final taskId = widget.task['taskID']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        widget.task['orderID']?.toString() ??
        '';
    StaffInspectionSession.ensureTask(taskId);

    _slots = [
      const StaffImageSlot(
        keyName: 'front_screen_closed',
        label: 'Front(Screen Closed)',
        hasInfo: true,
        infoMessage:
            'Please turn the display OFF (black screen) under good lighting to inspect for any surface hairline scratches, cracks, or chips on the glass.',
      ),
      const StaffImageSlot(
        keyName: 'front_screen_open',
        label: 'Front(Screen Open)',
        hasInfo: true,
        infoMessage:
            'Please turn the display ON to verify that the screen functions properly without dead pixels, tinting, or screen burn-in.',
      ),
      const StaffImageSlot(
        keyName: 'back',
        label: 'Back',
      ),
      const StaffImageSlot(
        keyName: 'frame_right',
        label: 'Frame(right)',
      ),
      const StaffImageSlot(
        keyName: 'frame_top',
        label: 'Frame(top)',
      ),
      const StaffImageSlot(
        keyName: 'frame_bottom',
        label: 'Frame(bottom)',
      ),
      const StaffImageSlot(
        keyName: 'camera_area',
        label: 'Camera area',
      ),
      const StaffImageSlot(
        keyName: 'any_angles',
        label: 'Any angles (Optional)',
        isOptional: true,
      ),
    ];

    // Restore previously uploaded images
    for (int i = 0; i < _slots.length; i++) {
      final key = _slots[i].keyName;
      final savedPath = StaffInspectionSession.savedImagePaths[key];
      if (savedPath != null && (savedPath.startsWith('http') || File(savedPath).existsSync())) {
        _slots[i] = _slots[i].copyWith(
          status: StaffImageSlotStatus.success,
          localFilePath: savedPath,
          fileName: StaffInspectionSession.savedImageNames[key] ?? '${_slots[i].label}.jpg',
          uploadProgress: 1.0,
        );
      }
    }

    _loadExistingStaffImages();
  }

  Future<void> _loadExistingStaffImages() async {
    final tradeInId = widget.task['tradeInRequestID']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        widget.task['orderID']?.toString() ??
        '';
    if (tradeInId.isEmpty) return;

    final details = await TradeInService.getTradeInRequestDetails(tradeInId);
    if (details != null && details['staffImages'] is Map && mounted) {
      final Map<String, dynamic> staffImages = Map<String, dynamic>.from(details['staffImages']);
      setState(() {
        for (int i = 0; i < _slots.length; i++) {
          final key = _slots[i].keyName;
          if (_slots[i].status != StaffImageSlotStatus.success && staffImages.containsKey(key)) {
            final imgUrl = staffImages[key]?.toString();
            if (imgUrl != null && imgUrl.isNotEmpty) {
              _slots[i] = _slots[i].copyWith(
                status: StaffImageSlotStatus.success,
                localFilePath: imgUrl,
                fileName: '${_slots[i].label}.jpg',
                uploadProgress: 1.0,
              );
              StaffInspectionSession.savedImagePaths[key] = imgUrl;
              StaffInspectionSession.savedImageNames[key] = '${_slots[i].label}.jpg';
            }
          }
        }
      });
    }
  }

  void _onSlotTap(int index) {
    final slot = _slots[index];
    if (slot.status == StaffImageSlotStatus.uploading) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Upload ${slot.label}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Supported formats: JPG, JPEG, PNG only (Max 5MB each).',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF0C5AD2)),
                ),
                title: const Text('Take Photo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('Capture with device camera', style: TextStyle(fontSize: 12)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndProcessImage(index, ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF0C5AD2)),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('JPG, JPEG, PNG only, max 5MB', style: TextStyle(fontSize: 12)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndProcessImage(index, ImageSource.gallery);
                },
              ),
              if (slot.status == StaffImageSlotStatus.success ||
                  slot.status == StaffImageSlotStatus.error ||
                  slot.status == StaffImageSlotStatus.notPhoneDetected) ...[
                const Divider(),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                  ),
                  title: Text(
                    slot.status == StaffImageSlotStatus.success
                        ? 'Remove Photo'
                        : 'Clear & Retake Photo',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFDC2626),
                      fontSize: 14,
                    ),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() {
                      StaffInspectionSession.savedImagePaths.remove(_slots[index].keyName);
                      StaffInspectionSession.savedImageNames.remove(_slots[index].keyName);
                      _slots[index] = _slots[index].reset();
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndProcessImage(int index, ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile == null) return;

      final String pathLower = pickedFile.path.toLowerCase();
      final String nameLower = pickedFile.name.toLowerCase();
      final bool isJpg = pathLower.endsWith('.jpg') ||
          pathLower.endsWith('.jpeg') ||
          nameLower.endsWith('.jpg') ||
          nameLower.endsWith('.jpeg');
      final bool isPng =
          pathLower.endsWith('.png') || nameLower.endsWith('.png');

      // 1. Format check
      if (!isJpg && !isPng) {
        if (!mounted) return;
        setState(() {
          StaffInspectionSession.savedImagePaths.remove(_slots[index].keyName);
          StaffInspectionSession.savedImageNames.remove(_slots[index].keyName);
          _slots[index] = _slots[index].copyWith(
            status: StaffImageSlotStatus.error,
            localFilePath: null,
            fileName: pickedFile.name,
            errorMessage: 'Must be JPG or PNG under 5MB. Tap to retry.',
          );
        });
        return;
      }

      // 2. Size check (5MB max)
      final fileLength = await pickedFile.length();
      const int maxSizeBytes = 5 * 1024 * 1024;
      if (fileLength > maxSizeBytes) {
        if (!mounted) return;
        setState(() {
          StaffInspectionSession.savedImagePaths.remove(_slots[index].keyName);
          StaffInspectionSession.savedImageNames.remove(_slots[index].keyName);
          _slots[index] = _slots[index].copyWith(
            status: StaffImageSlotStatus.error,
            localFilePath: null,
            fileName: pickedFile.name,
            errorMessage: 'Must be JPG or PNG under 5MB. Tap to retry.',
          );
        });
        return;
      }

      // 3. Mark uploading
      final int currentToken = (_slotTokens[index] ?? 0) + 1;
      _slotTokens[index] = currentToken;

      setState(() {
        _slots[index] = _slots[index].copyWith(
          status: StaffImageSlotStatus.uploading,
          uploadProgress: 0.35,
          errorMessage: null,
          localFilePath: pickedFile.path,
          fileName: pickedFile.name,
        );
      });

      // 4. Model 1 AI Phone Detection
      Map<String, dynamic> detectionResult = {};
      try {
        detectionResult = await TradeInService.detectPhone(pickedFile.path);
      } catch (e) {
        detectionResult = {
          'isPhone': false,
          'message': 'Phone verification failed. Please try again.',
        };
      }

      if (!mounted || _slotTokens[index] != currentToken) return;

      final bool isPhone = detectionResult['isPhone'] == true;
      if (!isPhone) {
        String errPrompt =
            'No smartphone detected in this image. Please ensure the phone is clearly visible without heavy obstructions and retake the photo.';
        if (detectionResult['message'] != null &&
            detectionResult['message'].toString().isNotEmpty) {
          errPrompt = detectionResult['message'].toString();
        }

        setState(() {
          StaffInspectionSession.savedImagePaths.remove(_slots[index].keyName);
          StaffInspectionSession.savedImageNames.remove(_slots[index].keyName);
          _slots[index] = _slots[index].copyWith(
            status: StaffImageSlotStatus.notPhoneDetected,
            localFilePath: pickedFile.path,
            fileName: pickedFile.name,
            uploadProgress: 0.0,
            errorMessage: errPrompt,
          );
        });
        return;
      }

      // Progress animation
      setState(() {
        _slots[index] = _slots[index].copyWith(uploadProgress: 0.75);
      });
      await Future.delayed(const Duration(milliseconds: 250));

      if (!mounted || _slotTokens[index] != currentToken) return;

      setState(() {
        _slots[index] = _slots[index].copyWith(
          status: StaffImageSlotStatus.success,
          localFilePath: pickedFile.path,
          fileName: pickedFile.name,
          uploadProgress: 1.0,
          errorMessage: null,
        );
      });
      StaffInspectionSession.savedImagePaths[_slots[index].keyName] = pickedFile.path;
      StaffInspectionSession.savedImageNames[_slots[index].keyName] = pickedFile.name;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        StaffInspectionSession.savedImagePaths.remove(_slots[index].keyName);
        StaffInspectionSession.savedImageNames.remove(_slots[index].keyName);
        _slots[index] = _slots[index].copyWith(
          status: StaffImageSlotStatus.error,
          errorMessage: 'Failed to process image: $e',
        );
      });
    }
  }

  Future<void> _onVerifyDeviceDetails() async {
    // Check if the 7 required slots (indices 0 to 6) are fulfilled
    final requiredSlots = _slots.sublist(0, 7);
    final unverifiedSlots = requiredSlots
        .where((s) => s.status != StaffImageSlotStatus.success || s.localFilePath == null)
        .toList();

    if (unverifiedSlots.isNotEmpty) {
      StaffToast.show(
        context,
        'Please upload all 7 required device angles before proceeding (${unverifiedSlots.first.label} is missing).',
        isError: true,
      );
      return;
    }

    // Build uploaded files map
    final Map<String, String> uploadedImages = {};
    for (final s in _slots) {
      if (s.localFilePath != null &&
          s.status == StaffImageSlotStatus.success) {
        uploadedImages[s.keyName] = s.localFilePath!;
      }
    }

    final tradeInId = widget.task['tradeInRequestID']?.toString() ??
        widget.task['tradeInID']?.toString() ??
        widget.task['orderID']?.toString() ??
        '';

    if (tradeInId.isNotEmpty) {
      setState(() => _isUploadingToServer = true);
      try {
        final res = await TradeInService.uploadStaffDeviceImages(
          tradeInRequestID: tradeInId,
          imagePaths: uploadedImages,
        );
        if (!mounted) return;
        if (res['success'] != true) {
          StaffToast.show(
            context,
            'Warning: Failed to sync images to server: ${res['message'] ?? 'Unknown error'}',
            isError: true,
          );
        }
      } catch (e) {
        if (!mounted) return;
        StaffToast.show(
          context,
          'Error uploading images: $e',
          isError: true,
        );
      } finally {
        if (mounted) {
          setState(() => _isUploadingToServer = false);
        }
      }
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'StaffVerifyDeviceInformationPage'),
        builder: (_) => StaffVerifyDeviceInformationPage(
          task: widget.task,
          device: widget.device,
          uploadedImages: uploadedImages,
          onTaskUpdated: widget.onTaskUpdated,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
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
                    // Top Back Button
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(height: 12),

                    // Title
                    const Text(
                      'Upload Device Images',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Description
                    const Text(
                      'Please provide clear, well-lit photos of your device from the angles specified below to ensure an accurate trade-in valuation. Supported formats: JPG, PNG (Max 5MB each).',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 2-Column Grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.85,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: _slots.length,
                      itemBuilder: (context, index) {
                        return _buildSlotCard(index);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Pinned Bottom Bar with Verify Device Details Button
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
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_areRequiredImagesUploaded && !_isUploadingToServer)
                      ? _onVerifyDeviceDetails
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0043CE),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isUploadingToServer
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Verify Device Details',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: (_areRequiredImagesUploaded && !_isUploadingToServer)
                                    ? Colors.white
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: (_areRequiredImagesUploaded && !_isUploadingToServer)
                                  ? Colors.white
                                  : const Color(0xFF94A3B8),
                              size: 20,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotCard(int index) {
    final slot = _slots[index];

    // Optional slot styling
    if (slot.isOptional && slot.status == StaffImageSlotStatus.empty) {
      return GestureDetector(
        onTap: () => _onSlotTap(index),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFCBD5E1),
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.add_circle_outline_rounded, size: 36, color: Color(0xFF94A3B8)),
              SizedBox(height: 10),
              Text(
                'Add Optional Image',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Determine state borders and colors
    Color borderColor = const Color(0xFFCBD5E1);
    Color backgroundColor = Colors.white;

    if (slot.status == StaffImageSlotStatus.success) {
      borderColor = const Color(0xFF93C5FD);
      backgroundColor = const Color(0xFFF8FAFC);
    } else if (slot.status == StaffImageSlotStatus.uploading) {
      borderColor = const Color(0xFF3B82F6);
      backgroundColor = const Color(0xFFEFF6FF);
    } else if (slot.status == StaffImageSlotStatus.error ||
        slot.status == StaffImageSlotStatus.notPhoneDetected) {
      borderColor = const Color(0xFFDC2626);
      backgroundColor = const Color(0xFFFEF2F2);
    }

    return GestureDetector(
      onTap: () => _onSlotTap(index),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            // Upper Area (Image / Spinner / Error / Placeholder)
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: _buildSlotContent(slot),
                  ),
                  if (slot.status == StaffImageSlotStatus.success)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, size: 14, color: Colors.white),
                      ),
                    ),
                  if (slot.status == StaffImageSlotStatus.uploading)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: slot.uploadProgress,
                        backgroundColor: const Color(0xFFDBEAFE),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0043CE)),
                        minHeight: 4,
                      ),
                    ),
                ],
              ),
            ),

            // Lower Label Row
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: Border(
                  top: BorderSide(
                    color: Colors.grey.shade200,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            slot.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: (slot.status == StaffImageSlotStatus.error ||
                                      slot.status == StaffImageSlotStatus.notPhoneDetected)
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (slot.hasInfo) ...[
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(slot.label),
                                  content: Text(slot.infoMessage ?? ''),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: const Icon(
                              Icons.info_outline_rounded,
                              size: 14,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotContent(StaffImageSlot slot) {
    if (slot.status == StaffImageSlotStatus.success &&
        slot.localFilePath != null) {
      final isNetwork = slot.localFilePath!.startsWith('http://') ||
          slot.localFilePath!.startsWith('https://');
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: isNetwork
              ? Image.network(
                  slot.localFilePath!,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  ),
                )
              : Image.file(
                  File(slot.localFilePath!),
                  fit: BoxFit.contain,
                ),
        ),
      );
    }

    if (slot.status == StaffImageSlotStatus.uploading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0043CE)),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Uploading...',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0043CE),
            ),
          ),
          Text(
            '${(slot.uploadProgress * 100).toInt()}%',
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      );
    }

    if (slot.status == StaffImageSlotStatus.error ||
        slot.status == StaffImageSlotStatus.notPhoneDetected) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 28, color: Color(0xFFDC2626)),
            const SizedBox(height: 6),
            Text(
              slot.status == StaffImageSlotStatus.notPhoneDetected
                  ? 'No Phone Detected'
                  : 'Invalid File',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFDC2626),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              slot.errorMessage ?? 'Must be JPG or PNG under 5MB. Tap to retry.',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                color: Color(0xFF991B1B),
                height: 1.2,
              ),
            ),
          ],
        ),
      );
    }

    // Default Empty State
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.camera_alt_outlined, size: 30, color: Color(0xFF94A3B8)),
        SizedBox(height: 6),
        Text(
          'Tap to upload',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
