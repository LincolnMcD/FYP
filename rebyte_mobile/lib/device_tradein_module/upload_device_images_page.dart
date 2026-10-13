import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'models/device_model.dart';
import 'services/trade_in_service.dart';
import 'services/trade_in_flow_session.dart';
import 'imei_validation_step_page.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import '../widgets/rebyte_app_bar.dart';

enum ImageSlotStatus {
  empty,
  uploading,
  success,
  error,
  notPhoneDetected,
}

class ImageSlotItem {
  final String keyName;
  final String label;
  final String? localFilePath;
  final String? previewBase64;
  final String? fileName;
  final bool isOptional;
  final bool hasInfo;
  final String? infoTitle;
  final String? infoMessage;
  final ImageSlotStatus status;
  final double uploadProgress;
  final String? errorMessage;

  const ImageSlotItem({
    required this.keyName,
    required this.label,
    this.localFilePath,
    this.previewBase64,
    this.fileName,
    this.isOptional = false,
    this.hasInfo = false,
    this.infoTitle,
    this.infoMessage,
    this.status = ImageSlotStatus.empty,
    this.uploadProgress = 0.0,
    this.errorMessage,
  });

  ImageSlotItem copyWith({
    String? keyName,
    String? label,
    String? localFilePath,
    String? previewBase64,
    String? fileName,
    bool? isOptional,
    bool? hasInfo,
    String? infoTitle,
    String? infoMessage,
    ImageSlotStatus? status,
    double? uploadProgress,
    String? errorMessage,
  }) {
    return ImageSlotItem(
      keyName: keyName ?? this.keyName,
      label: label ?? this.label,
      localFilePath: localFilePath ?? this.localFilePath,
      previewBase64: previewBase64 ?? this.previewBase64,
      fileName: fileName ?? this.fileName,
      isOptional: isOptional ?? this.isOptional,
      hasInfo: hasInfo ?? this.hasInfo,
      infoTitle: infoTitle ?? this.infoTitle,
      infoMessage: infoMessage ?? this.infoMessage,
      status: status ?? this.status,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  /// Returns a clean empty slot item with all image paths, files, and errors cleared
  ImageSlotItem reset() {
    return ImageSlotItem(
      keyName: keyName,
      label: label,
      isOptional: isOptional,
      hasInfo: hasInfo,
      infoTitle: infoTitle,
      infoMessage: infoMessage,
      status: ImageSlotStatus.empty,
      localFilePath: null,
      previewBase64: null,
      fileName: null,
      uploadProgress: 0.0,
      errorMessage: null,
    );
  }
}

class UploadDeviceImagesPage extends StatefulWidget {
  final DeviceModel device;
  final bool isLoggedIn;
  final String? email;
  final String? name;

  const UploadDeviceImagesPage({
    super.key,
    required this.device,
    this.isLoggedIn = false,
    this.email,
    this.name,
  });

  @override
  State<UploadDeviceImagesPage> createState() => _UploadDeviceImagesPageState();
}

class _UploadDeviceImagesPageState extends State<UploadDeviceImagesPage> {
  late List<ImageSlotItem> _slots;

  // Track upload generation tokens per slot to cancel processing if navigated away
  final Map<int, int> _slotTokens = {};

  void _cancelAndEmptyUploadingSlots() {
    bool changed = false;
    for (int i = 0; i < _slots.length; i++) {
      if (_slots[i].status == ImageSlotStatus.uploading) {
        // Invalidate generation token
        _slotTokens[i] = (_slotTokens[i] ?? 0) + 1;
        _slots[i] = _slots[i].reset();
        changed = true;
      }
    }
    if (changed) {
      TradeInFlowSession.saveSlots(_slots);
    }
  }

  @override
  void dispose() {
    _cancelAndEmptyUploadingSlots();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // If returning from Page 4 to Page 3, restore existing uploaded image slots
    if (TradeInFlowSession.savedSlots != null &&
        TradeInFlowSession.savedSlots!.isNotEmpty) {
      _slots = TradeInFlowSession.savedSlots!.map((slot) {
        // Sanitize: If a slot was left in 'uploading' when leaving the screen, reset it to empty
        if (slot.status == ImageSlotStatus.uploading) {
          return slot.reset();
        }
        return slot;
      }).toList();
    } else {
      _slots = [
        const ImageSlotItem(
          keyName: 'front_screen_closed',
          label: 'Front (Screen Closed)',
          hasInfo: true,
          infoTitle: 'Front (Screen Closed)',
          infoMessage:
              'Please turn the display OFF (black screen) under good lighting to inspect for any surface hairline scratches, cracks, or chips on the glass.',
        ),
        const ImageSlotItem(
          keyName: 'front_screen_open',
          label: 'Front (Screen Open)',
          hasInfo: true,
          infoTitle: 'Front (Screen Open)',
          infoMessage:
              'Please turn the display ON to show that the screen functions properly without dead pixels, tinting, or screen burn-in.',
        ),
        const ImageSlotItem(
          keyName: 'back',
          label: 'Back',
        ),
        const ImageSlotItem(
          keyName: 'frame_right',
          label: 'Frame (right)',
        ),
        const ImageSlotItem(
          keyName: 'frame_top',
          label: 'Frame (top)',
        ),
        const ImageSlotItem(
          keyName: 'frame_bottom',
          label: 'Frame (bottom)',
        ),
        const ImageSlotItem(
          keyName: 'camera_area',
          label: 'Camera area',
        ),
        const ImageSlotItem(
          keyName: 'any_angles',
          label: 'Any angles',
          isOptional: true,
        ),
      ];
    }
  }

  void _onSlotTap(int index) {
    final slot = _slots[index];

    // If this specific slot is already uploading, ignore tap
    if (slot.status == ImageSlotStatus.uploading) return;

    // Show source picker bottom sheet (Camera, Gallery, or mock simulation)
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
                  GestureDetector(
                    onTap: () => Navigator.pop(sheetContext),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Supported formats: JPG, JPEG, PNG only (Max 5MB per image).',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.35),
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
                  _pickImage(index, ImageSource.camera);
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
                  _pickImage(index, ImageSource.gallery);
                },
              ),
              if (slot.status == ImageSlotStatus.success ||
                  slot.status == ImageSlotStatus.error ||
                  slot.status == ImageSlotStatus.notPhoneDetected) ...[
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
                    slot.status == ImageSlotStatus.success ? 'Remove Photo' : 'Clear & Retake Photo',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFDC2626), fontSize: 14),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    TradeInFlowSession.removeUploadedImage(_slots[index].keyName);
                    setState(() {
                      _slots[index] = _slots[index].reset();
                    });
                    TradeInFlowSession.saveSlots(_slots);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _pickImage(int index, ImageSource source) async {
    try {
      // NOTE: Do not set maxWidth / maxHeight / imageQuality here,
      // because image_picker compresses the file before returning,
      // which masks files that originally exceed 5MB.
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
      );

      if (pickedFile == null) {
        // User cancelled camera/picker
        return;
      }

      // Check file extension / format (Only JPG / JPEG / PNG allowed; explicitly reject WEBP etc.)
      final String pathLower = (pickedFile.path).toLowerCase();
      final String nameLower = (pickedFile.name).toLowerCase();
      final bool isJpg = pathLower.endsWith('.jpg') ||
          pathLower.endsWith('.jpeg') ||
          nameLower.endsWith('.jpg') ||
          nameLower.endsWith('.jpeg');
      final bool isPng =
          pathLower.endsWith('.png') || nameLower.endsWith('.png');

      if (!isJpg && !isPng) {
        if (!mounted) return;
        setState(() {
          _slots[index] = _slots[index].copyWith(
            status: ImageSlotStatus.error,
            localFilePath: null,
            fileName: pickedFile.name,
            errorMessage:
                'Only JPG, JPEG, and PNG formats are supported.',
          );
        });
        return;
      }

      // Check actual file size (limit: strictly 5MB)
      final fileLength = await pickedFile.length();
      const int maxSizeBytes = 5 * 1024 * 1024; // 5 MB
      if (fileLength > maxSizeBytes) {
        if (!mounted) return;
        final double mbSize = fileLength / (1024 * 1024);
        setState(() {
          _slots[index] = _slots[index].copyWith(
            status: ImageSlotStatus.error,
            localFilePath: null,
            fileName: pickedFile.name,
            errorMessage:
                'File size (${mbSize.toStringAsFixed(1)}MB) exceeds 5MB limit. Please upload an image under 5MB.',
          );
        });
        return;
      }

      // Start upload / AI verification animation with slot generation token
      final int currentToken = (_slotTokens[index] ?? 0) + 1;
      _slotTokens[index] = currentToken;

      setState(() {
        _slots[index] = _slots[index].copyWith(
          status: ImageSlotStatus.uploading,
          uploadProgress: 0.35,
          errorMessage: null,
          localFilePath: pickedFile.path,
          fileName: pickedFile.name,
        );
      });

      // Step 2: Run AI Phone Detection via Backend Model 1
      Map<String, dynamic> detectionResult = {};
      try {
        detectionResult = await TradeInService.detectPhone(pickedFile.path);
      } catch (e) {
        detectionResult = {
          'isPhone': false,
          'message': 'Phone verification failed. Please try again.',
        };
      }

      // If user navigated away or cancelled while inference was running, abort
      if (!mounted || _slotTokens[index] != currentToken) return;

      final bool isPhone = detectionResult['isPhone'] == true;

      if (!isPhone) {
        // NON-PHONE DETECTED OR VERIFICATION FAILED:
        // Use clean, low-level friendly message (no technical stack traces)
        String errPrompt = 'No smartphone detected in this image. Please ensure the phone is clearly visible without heavy obstructions and retake the photo.';

        if (detectionResult['message'] != null) {
          final String msg = detectionResult['message'].toString();
          if (msg.contains('Phone verification failed') ||
              msg.contains('failed') ||
              msg.contains('timed out') ||
              msg.contains('SocketException') ||
              msg.contains('TimeoutException')) {
            errPrompt = 'Phone verification failed. Please try again.';
          } else if (msg.isNotEmpty && msg != 'No smartphone detected in this image.') {
            errPrompt = msg;
          }
        }

        if (_slotTokens[index] != currentToken) return;
        setState(() {
          _slots[index] = _slots[index].copyWith(
            status: ImageSlotStatus.notPhoneDetected,
            localFilePath: pickedFile.path,
            fileName: pickedFile.name,
            uploadProgress: 0.0,
            errorMessage: errPrompt,
          );
        });
        return;
      }

      if (_slotTokens[index] != currentToken) return;
      // Progress animation
      setState(() {
        _slots[index] = _slots[index].copyWith(uploadProgress: 0.85);
      });

      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted || _slotTokens[index] != currentToken) return;

      setState(() {
        _slots[index] = _slots[index].copyWith(
          status: ImageSlotStatus.success,
          localFilePath: pickedFile.path,
          fileName: pickedFile.name,
          uploadProgress: 1.0,
          errorMessage: null,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _slots[index] = _slots[index].copyWith(
          status: ImageSlotStatus.error,
          errorMessage: 'Failed to access camera or gallery: ${e.toString()}',
        );
      });
    }
  }

  void _showInfoDialog(String title, String message) {
    showDialog(
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
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                message,
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.45),
              ),
              const SizedBox(height: 24),
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

  bool get _canContinue {
    // 1. Must NOT have any slot currently uploading or verifying (especially when 8th slot is in progress)
    final bool anyUploading = _slots.any((slot) => slot.status == ImageSlotStatus.uploading);
    if (anyUploading) return false;

    // 2. Must NOT have any slot in error or notPhoneDetected state
    final bool hasErrors = _slots.any(
      (slot) => slot.status == ImageSlotStatus.error || slot.status == ImageSlotStatus.notPhoneDetected,
    );
    if (hasErrors) return false;

    // 3. For optional slots (e.g. 8th "Any angles"), it must be either empty OR successfully verified
    final bool optionalValid = _slots
        .where((slot) => slot.isOptional)
        .every((slot) => slot.status == ImageSlotStatus.empty || slot.status == ImageSlotStatus.success);
    if (!optionalValid) return false;

    // 4. All 7 required (non-optional) slots must have status == success
    return _slots
        .where((slot) => !slot.isOptional)
        .every((slot) => slot.status == ImageSlotStatus.success);
  }

  void _onContinue() async {
    if (!_canContinue) return;

    // Reuse existing TradeInRequestID from current flow session if user already created one!
    final String? existingRequestId = TradeInFlowSession.currentTradeInRequestId;
    final String tradeInRequestID = existingRequestId ?? 'TR${DateTime.now().millisecondsSinceEpoch}';

    // Store in active session immediately
    TradeInFlowSession.setTradeInRequestId(tradeInRequestID);
    TradeInFlowSession.setDeviceId(widget.device.deviceID);

    // Collect local file paths for each imageView slot that are new or changed
    final Map<String, String> imagePathsToUpload = {};
    for (final slot in _slots) {
      if (slot.status == ImageSlotStatus.success &&
          slot.localFilePath != null &&
          slot.localFilePath!.isNotEmpty) {
        if (existingRequestId == null || TradeInFlowSession.hasImageChanged(slot.keyName, slot.localFilePath!)) {
          imagePathsToUpload[slot.keyName] = slot.localFilePath!;
        }
      }
    }

    // Save slots to in-memory session so if user comes back to Page 3, their selections are kept
    TradeInFlowSession.saveSlots(_slots);

    final List<String> removedViews = List.from(TradeInFlowSession.pendingRemovedImageViews);

    // Launch upload asynchronously in the background so user doesn't wait!
    final uploadFuture = Future<void>(() async {
      try {
        final res = await TradeInService.submitTradeInRequestWithImages(
          tradeInRequestID: existingRequestId,
          deviceID: widget.device.deviceID,
          brand: widget.device.brand,
          model: widget.device.model,
          modelCode: widget.device.modelCode,
          storageCapacity: widget.device.storageCapacity,
          colour: widget.device.colour,
          deviceAge: widget.device.deviceAge ?? '1 year(s)',
          imeiNum: widget.device.imeiNum,
          deviceCategory: widget.device.deviceCategory,
          userEmail: widget.email ?? widget.device.userEmail,
          imageFilePaths: imagePathsToUpload,
          removedImageViews: removedViews,
        );

        if (res['success'] == true) {
          final returnedId = res['tradeInRequestID'];
          if (returnedId != null) {
            TradeInFlowSession.setTradeInRequestId(returnedId);
          }
          // Mark successfully uploaded image paths and clear pending removed list
          for (final entry in imagePathsToUpload.entries) {
            TradeInFlowSession.markImageUploaded(entry.key, entry.value);
          }
          TradeInFlowSession.clearPendingRemovedImages();
        }
      } catch (e) {
        debugPrint('Background image upload notice: $e');
      }
    });

    // Save background future in session
    TradeInFlowSession.setBackgroundUploadFuture(uploadFuture);

    // Directly navigate to Page 4 (IMEI Validation Step Page) instantly without blocking!
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImeiValidationStepPage(
          device: widget.device,
          tradeInRequestID: tradeInRequestID,
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _cancelAndEmptyUploadingSlots();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FB),
        appBar: const ReByteAppBar(),
        drawer: ReByteDrawer(
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
          selectedIndex: 2,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back Button
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Color(0xFF0F172A),
                    size: 22,
                  ),
                  onPressed: () {
                    _cancelAndEmptyUploadingSlots();
                    Navigator.pop(context);
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(height: 16),

              // Title
              const Text(
                'Upload Device Images',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),

              // Subtitle
              const Text(
                'Please provide clear, well-lit photos of your device from the angles specified below.\nSupported formats: JPG, JPEG, PNG only (Max 5MB per image).',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),

              // Protection Notice Tip Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFDBFE), width: 1.0),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: Color(0xFF1D4ED8),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Tip: Please remove any protective accessories such as phone cases, covers, or screen protectors (if possible) for a more accurate device valuation.',
                        textAlign: TextAlign.justify,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1E40AF),
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2-Column Grid of Slots
              _buildSlotsGrid(),
              const SizedBox(height: 24),

              // Continue Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _canContinue ? _onContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003799),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    disabledForegroundColor: const Color(0xFF64748B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Continue',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: 2,
      ),
    ),
  );
}

  Widget _buildSlotsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: List.generate(_slots.length, (index) {
            final slot = _slots[index];
            final bool hasError = slot.status == ImageSlotStatus.error ||
                slot.status == ImageSlotStatus.notPhoneDetected;
            return SizedBox(
              width: cardWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 175,
                    child: _buildSlotCard(index),
                  ),
                  if (hasError && slot.errorMessage != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.0),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1.0),
                            child: Icon(Icons.error, size: 14, color: Color(0xFFDC2626)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              slot.errorMessage!,
                              textAlign: TextAlign.justify,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFB91C1C),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildSlotCard(int index) {
    final slot = _slots[index];

    switch (slot.status) {
      case ImageSlotStatus.success:
        return _buildSuccessCard(index, slot);
      case ImageSlotStatus.notPhoneDetected:
        return _buildNotPhoneDetectedCard(index, slot);
      case ImageSlotStatus.uploading:
        return _buildUploadingCard(index, slot);
      case ImageSlotStatus.error:
        return _buildErrorCard(index, slot);
      case ImageSlotStatus.empty:
        if (slot.isOptional) {
          return _buildOptionalCard(index, slot);
        }
        return _buildEmptyDashedCard(index, slot);
    }
  }

  // 1. Success Card (uploaded photo fills the entire block above the side label bar)
  Widget _buildSuccessCard(int index, ImageSlotItem slot) {
    return InkWell(
      onTap: () => _onSlotTap(index),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image area filling the block with checkmark badge
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (slot.localFilePath != null)
                    Image.file(
                      File(slot.localFilePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildFallbackPreview(),
                    )
                  else
                    _buildFallbackPreview(),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF10B981),
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom Label Bar (clean side label, no xxx.jpg overflow)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Text(
                slot.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackPreview() {
    return Container(
      color: const Color(0xFFF1F5F9),
      child: const Center(
        child: Icon(
          Icons.photo_outlined,
          color: Color(0xFF94A3B8),
          size: 32,
        ),
      ),
    );
  }

  // Non-Phone Image Card: Displays the uploaded image as normal, but highlighted in solid red with warning badge
  Widget _buildNotPhoneDetectedCard(int index, ImageSlotItem slot) {
    return InkWell(
      onTap: () => _onSlotTap(index),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFDC2626),
            width: 1.8,
            style: BorderStyle.solid,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFDC2626).withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image area filling the block with RED warning badge
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (slot.localFilePath != null)
                    Image.file(
                      File(slot.localFilePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildFallbackPreview(),
                    )
                  else
                    _buildFallbackPreview(),
                  // Semi-transparent subtle tint on image to indicate review needed
                  Container(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.20),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close_rounded, color: Colors.white, size: 13),
                          SizedBox(width: 3),
                          Text(
                            'Not a Phone',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom Label Bar in Red
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                border: Border(top: BorderSide(color: Color(0xFFFECACA), width: 1.0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFDC2626)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      slot.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  // 2. Uploading Card (blue border, circular progress spinner, percentage label, progress bar at bottom)
  Widget _buildUploadingCard(int index, ImageSlotItem slot) {
    final int percent = (slot.uploadProgress * 100).toInt();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3B82F6), width: 1.4),
      ),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    value: slot.uploadProgress,
                    strokeWidth: 2.6,
                    backgroundColor: const Color(0xFFDBEAFE),
                    color: const Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Uploading...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$percent%',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          // Progress track at bottom
          LinearProgressIndicator(
            value: slot.uploadProgress,
            minHeight: 3,
            backgroundColor: const Color(0xFFDBEAFE),
            color: const Color(0xFF2563EB),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            alignment: Alignment.centerLeft,
            child: Text(
              slot.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 3. Error / Invalid File Card (prominent red border, red alert background, instant prompt)
  Widget _buildErrorCard(int index, ImageSlotItem slot) {
    return InkWell(
      onTap: () => _onSlotTap(index),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFDC2626),
            width: 1.8,
            style: BorderStyle.solid,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFDC2626).withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEE2E2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_rounded,
                      color: Color(0xFFDC2626),
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Upload Error',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFCA5A5), width: 0.8),
                    ),
                    child: const Text(
                      'Tap to change photo',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                color: Color(0xFFFEE2E2),
                border: Border(top: BorderSide(color: Color(0xFFFECACA))),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.close_rounded, size: 14, color: Color(0xFFDC2626)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      slot.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  // 4. Empty Dashed Card (camera icon, Tap to upload, bottom label + info icon)
  Widget _buildEmptyDashedCard(int index, ImageSlotItem slot) {
    return InkWell(
      onTap: () => _onSlotTap(index),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFCBD5E1),
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_a_photo_outlined,
                      color: Color(0xFF0C5AD2),
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap to upload',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      slot.label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (slot.hasInfo)
                    GestureDetector(
                      onTap: () => _showInfoDialog(
                        slot.infoTitle ?? slot.label,
                        slot.infoMessage ??
                            'Please capture a clear, well-lit photo of the screen to inspect device condition.',
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xFFF59E0B),
                        size: 16,
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

  // 5. Optional Card ("+" icon, Add Optional Image, "Any Angles", "Optional" pill)
  Widget _buildOptionalCard(int index, ImageSlotItem slot) {
    return InkWell(
      onTap: () => _onSlotTap(index),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Color(0xFF64748B),
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add Optional Image',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    slot.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Optional',
                      style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
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
}
