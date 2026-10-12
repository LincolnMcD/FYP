import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'models/device_model.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import '../widgets/rebyte_app_bar.dart';

enum ImageSlotStatus {
  empty,
  uploading,
  success,
  error,
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
  bool _isProceeding = false;


  @override
  void initState() {
    super.initState();
    _slots = [
      const ImageSlotItem(
        keyName: 'front',
        label: 'Front',
      ),
      const ImageSlotItem(
        keyName: 'back',
        label: 'Back',
      ),
      const ImageSlotItem(
        keyName: 'left_side',
        label: 'Left Side',
      ),
      const ImageSlotItem(
        keyName: 'right_side',
        label: 'Right Side',
      ),
      const ImageSlotItem(
        keyName: 'screen_open',
        label: 'Screen (Open)',
        hasInfo: true,
        infoTitle: 'Screen (Display On)',
        infoMessage:
            'Please turn the display ON to show that the screen functions properly without dead pixels, tinting, or screen burn-in.',
      ),
      const ImageSlotItem(
        keyName: 'screen_closed',
        label: 'Screen (Closed)',
        hasInfo: true,
        infoTitle: 'Screen (Display Off)',
        infoMessage:
            'Please turn the display OFF (black screen) under good lighting to inspect for any surface hairline scratches, cracks, or chips on the glass.',
      ),
      const ImageSlotItem(
        keyName: 'camera_area',
        label: 'Camera Area',
      ),
      const ImageSlotItem(
        keyName: 'any_angles',
        label: 'Any Angles',
        isOptional: true,
      ),
    ];
  }

  void _onSlotTap(int index) {
    final slot = _slots[index];

    // If already uploading, ignore tap
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
                'Select JPG or PNG (Maximum 5MB). Ensure good lighting without flash reflections.',
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
                subtitle: const Text('Pick existing image from storage', style: TextStyle(fontSize: 12)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(index, ImageSource.gallery);
                },
              ),
              if (slot.status == ImageSlotStatus.success) ...[
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
                  title: const Text('Remove Photo', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFDC2626), fontSize: 14)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() {
                      _slots[index] = _slots[index].copyWith(
                        status: ImageSlotStatus.empty,
                        localFilePath: null,
                        previewBase64: null,
                        fileName: null,
                        uploadProgress: 0.0,
                        errorMessage: null,
                      );
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

  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _pickImage(int index, ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        // User cancelled camera/picker
        return;
      }

      // Check file size (limit 5MB)
      final fileLength = await pickedFile.length();
      if (fileLength > 5 * 1024 * 1024) {
        if (!mounted) return;
        setState(() {
          _slots[index] = _slots[index].copyWith(
            status: ImageSlotStatus.error,
            errorMessage: 'File exceeds 5MB limit.',
          );
        });
        return;
      }

      // Start upload animation
      setState(() {
        _slots[index] = _slots[index].copyWith(
          status: ImageSlotStatus.uploading,
          uploadProgress: 0.30,
          errorMessage: null,
        );
      });

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() {
        _slots[index] = _slots[index].copyWith(uploadProgress: 0.75);
      });

      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;

      setState(() {
        _slots[index] = _slots[index].copyWith(
          status: ImageSlotStatus.success,
          localFilePath: pickedFile.path,
          fileName: pickedFile.name,
          uploadProgress: 1.0,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _slots[index] = _slots[index].copyWith(
          status: ImageSlotStatus.error,
          errorMessage: 'Failed to access camera or gallery.',
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
    // Check required slots: all non-optional slots must have status == success
    return _slots
        .where((slot) => !slot.isOptional)
        .every((slot) => slot.status == ImageSlotStatus.success);
  }

  void _onContinue() async {
    if (!_canContinue) return;

    setState(() => _isProceeding = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _isProceeding = false);

    // Show completion dialog or route to Step 3 condition inspection
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'Images Uploaded',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.device.brand} ${widget.device.model} photos have been saved. Ready for Step 3 (Condition Questionnaire).',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('PROCEED', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                onPressed: () => Navigator.pop(context),
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
                'Please provide clear, well-lit photos of your device from the angles specified below to ensure an accurate trade-in valuation.\nSupported formats: JPG, PNG (Max 5MB each).',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),

              // 2-Column Grid of Slots
              _buildSlotsGrid(),
              const SizedBox(height: 24),

              // Continue Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _canContinue && !_isProceeding ? _onContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003799),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    disabledForegroundColor: const Color(0xFF64748B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isProceeding)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                        )
                      else ...[
                        const Text(
                          'Continue',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 18),
                      ],
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
    );
  }

  Widget _buildSlotsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(_slots.length, (index) {
            return SizedBox(
              width: cardWidth,
              height: 175,
              child: _buildSlotCard(index),
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

  // 3. Error / Invalid File Card (dashed red border, red icon, retry helper text)
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
            width: 1.4,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEE2E2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFDC2626),
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Invalid File',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'Must be JPG or PNG under 5MB. Tap to retry.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9.5, color: Color(0xFF7F1D1D)),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              alignment: Alignment.centerLeft,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFFECACA))),
              ),
              child: Text(
                slot.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFDC2626),
                ),
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
