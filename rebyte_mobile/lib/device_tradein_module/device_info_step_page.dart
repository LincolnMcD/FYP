import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/phone_brands_data.dart';
import 'services/trade_in_service.dart';
import 'services/trade_in_flow_session.dart';
import 'models/device_model.dart';
import 'widgets/searchable_selection_sheet.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import 'upload_device_images_page.dart';
import '../widgets/rebyte_app_bar.dart';
import '../account_management_module/services/session_service.dart';

class DeviceInfoStepPage extends StatefulWidget {
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final DeviceModel? device;

  const DeviceInfoStepPage({
    super.key,
    this.isLoggedIn = false,
    this.email,
    this.name,
    this.device,
  });

  @override
  State<DeviceInfoStepPage> createState() => _DeviceInfoStepPageState();
}

class _DeviceInfoStepPageState extends State<DeviceInfoStepPage> {
  String? _selectedBrand;
  String? _selectedModel;
  String? _selectedModelCode;
  String? _selectedStorage; // No default selection
  String? _selectedColour;
  Color? _selectedColourSwatch;
  final TextEditingController _deviceAgeController = TextEditingController();
  final FocusNode _deviceAgeFocusNode = FocusNode();

  List<String> _loadedBrands = List.from(PhoneBrandsData.wellKnownPhoneBrands);
  final Map<String, List<String>> _loadedModels = {};

  @override
  void initState() {
    super.initState();
    TradeInFlowSession.currentStep = 2;
    _deviceAgeController.addListener(_onFieldChanged);

    // If user navigated back from Page 3/4 or passed a device or resumed a pending session, populate values!
    final activeDevice = widget.device ?? TradeInFlowSession.currentDevice;
    if (activeDevice != null) {
      if (TradeInFlowSession.currentDevice == null) {
        TradeInFlowSession.setCurrentDevice(activeDevice);
      }
      _selectedBrand = activeDevice.brand.isNotEmpty ? activeDevice.brand : null;
      _selectedModel = activeDevice.model.isNotEmpty ? activeDevice.model : null;
      _selectedModelCode = activeDevice.modelCode;
      _selectedStorage = activeDevice.storageCapacity.isNotEmpty ? activeDevice.storageCapacity : null;
      _selectedColour = activeDevice.colour.isNotEmpty ? activeDevice.colour : null;
      if (_selectedColour != null) {
        for (var c in PhoneBrandsData.popularColors) {
          if (c.name.toLowerCase() == _selectedColour!.toLowerCase()) {
            _selectedColourSwatch = c.color;
            break;
          }
        }
      }
      if (activeDevice.deviceAge != null && activeDevice.deviceAge!.isNotEmpty) {
        final digits = activeDevice.deviceAge!.replaceAll(RegExp(r'\D'), '');
        _deviceAgeController.text = digits.isNotEmpty ? digits : '0';
      }
      if (_selectedBrand != null) {
        _preloadModelsForBrand(_selectedBrand!);
      }
    }

    _fetchBrandsFromLibrary();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _fetchBrandsFromLibrary() async {
    final brands = await TradeInService.getBrands();
    if (mounted && brands.isNotEmpty) {
      setState(() {
        _loadedBrands = brands;
      });
    }
  }

  Future<void> _preloadModelsForBrand(String brand) async {
    if (_loadedModels.containsKey(brand.toLowerCase())) return;
    final models = await TradeInService.getModelsForBrand(brand);
    if (mounted && models.isNotEmpty) {
      setState(() {
        _loadedModels[brand.toLowerCase()] = models;
      });
    }
  }

  @override
  void dispose() {
    _deviceAgeController.removeListener(_onFieldChanged);
    _deviceAgeController.dispose();
    _deviceAgeFocusNode.dispose();
    super.dispose();
  }

  void _onBrandTapped() async {
    final chosenBrand = await SearchableSelectionSheet.show(
      context: context,
      title: 'Select Brand',
      searchHint: 'Search mobile brand...',
      items: _loadedBrands,
      allowCustomWriteIn: false,
      asyncItemsLoader: _loadedBrands.isEmpty
          ? () async {
              final brands = await TradeInService.getBrands();
              if (mounted) setState(() => _loadedBrands = brands);
              return brands;
            }
          : null,
      selectedItem: _selectedBrand,
    );

    if (chosenBrand != null && chosenBrand != _selectedBrand) {
      setState(() {
        _selectedBrand = chosenBrand;
        if (chosenBrand == 'Other') {
          _selectedModel = 'Other';
          _selectedModelCode = 'OTHER';
        } else {
          _selectedModel = null;
          _selectedModelCode = null;
          _preloadModelsForBrand(chosenBrand);
        }
      });
    }
  }

  void _onModelTapped() async {
    if (_selectedBrand == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a brand first'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF0F172A),
        ),
      );
      return;
    }

    if (_selectedBrand == 'Other') {
      // Model is auto-filled as Other; no need to show dropdown
      return;
    }

    final brandKey = _selectedBrand!.toLowerCase();
    final cachedForBrand = _loadedModels[brandKey] ?? [];
    final filteredCached = cachedForBrand
        .where((m) => !m.toLowerCase().startsWith('other'))
        .toList();

    final chosenModel = await SearchableSelectionSheet.show(
      context: context,
      title: 'Select $_selectedBrand Model',
      searchHint: 'Search $_selectedBrand model...',
      items: filteredCached,
      allowCustomWriteIn: false,
      asyncItemsLoader: filteredCached.isEmpty
          ? () async {
              final models = await TradeInService.getModelsForBrand(_selectedBrand!);
              final filtered = models
                  .where((m) => !m.toLowerCase().startsWith('other'))
                  .toList();
              if (mounted) {
                setState(() => _loadedModels[brandKey] = filtered);
              }
              return filtered;
            }
          : null,
      selectedItem: _selectedModel,
    );

    if (chosenModel != null) {
      setState(() {
        _selectedModel = chosenModel;
        _selectedModelCode = TradeInService.getModelCode(_selectedBrand!, chosenModel);
      });
    }
  }

  void _onColourTapped() async {
    final colorMap = <String, Color>{};
    for (var c in PhoneBrandsData.popularColors) {
      colorMap[c.name] = c.color;
    }

    final colorNames = PhoneBrandsData.popularColors.map((e) => e.name).toList();

    final chosenColour = await SearchableSelectionSheet.show(
      context: context,
      title: 'Select Colour',
      searchHint: 'Search colour...',
      items: colorNames,
      selectedItem: _selectedColour,
      itemColors: colorMap,
      allowCustomWriteIn: false,
    );

    if (chosenColour != null) {
      setState(() {
        _selectedColour = chosenColour;
        _selectedColourSwatch = colorMap[chosenColour] ?? const Color(0xFF64748B);
      });
    }
  }

  bool _isSubmitting = false;

  void _onContinue() async {
    if (_isSubmitting) return;

    final rawAgeText = _deviceAgeController.text.trim();
    final int? ageNum = int.tryParse(rawAgeText);

    if (ageNum == null) return;

    // Limit device age from 0 to 10 years
    if (ageNum > 10) {
      _showOldDeviceDialog();
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final String formattedAge = ageNum == 0 ? '< 1 year' : '$ageNum year(s)';

    // Get active user email from session or widget
    String? currentUserEmail = widget.email;
    try {
      final session = await SessionService.getSession();
      if (session.isNotEmpty) {
        currentUserEmail = session['email'] ?? currentUserEmail;
      }
    } catch (_) {}

    // Reuse existing deviceID from active session if present so we update the same device
    final String devId = TradeInFlowSession.currentDeviceId ??
        TradeInFlowSession.currentDevice?.deviceID ??
        'DEV-${DateTime.now().millisecondsSinceEpoch}';

    final deviceToPass = DeviceModel(
      deviceID: devId,
      deviceCategory: 'smartphone',
      brand: _selectedBrand!,
      model: _selectedModel!,
      modelCode: _selectedModelCode,
      storageCapacity: _selectedStorage!,
      colour: _selectedColour!,
      status: 'pending',
      deviceAge: formattedAge,
      userEmail: currentUserEmail,
    );

    // Save into active session
    TradeInFlowSession.setCurrentDevice(deviceToPass);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UploadDeviceImagesPage(
          device: deviceToPass,
          isLoggedIn: widget.isLoggedIn,
          email: currentUserEmail,
          name: widget.name,
        ),
      ),
    );
  }

  void _showOldDeviceDialog() {
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
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Trade-In Unavailable',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'The device is old, unable to trade in.\n\nDevices older than 10 years are not eligible for trade-in evaluation.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
    final bool isBrandOther = _selectedBrand == 'Other';
    final bool isModelEnabled = _selectedBrand != null && !isBrandOther;
    final bool isFormComplete = _selectedBrand != null &&
        _selectedModel != null &&
        _selectedStorage != null &&
        _selectedColour != null &&
        _deviceAgeController.text.trim().isNotEmpty;

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
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
            // Top back button row
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
            const SizedBox(height: 12),

            // Title
            const Text(
              'Tell us about your device',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            const Text(
              'Enter the specifications to get an accurate\nestimate.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // Main White Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF1F5F9)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand Field
                  _buildFieldLabel('Brand'),
                  const SizedBox(height: 8),
                  _buildDropdownTrigger(
                    title: _selectedBrand ?? 'Select Brand',
                    isSelected: _selectedBrand != null,
                    isEnabled: true,
                    onTap: _onBrandTapped,
                  ),
                  const SizedBox(height: 20),

                  // Model Field (disabled until brand selected, auto-filled if Other)
                  _buildFieldLabel('Model'),
                  const SizedBox(height: 8),
                  _buildDropdownTrigger(
                    title: isBrandOther
                        ? 'Other'
                        : (isModelEnabled
                            ? (_selectedModel ?? 'Select Model')
                            : 'Select Brand First'),
                    isSelected: _selectedModel != null,
                    isEnabled: isModelEnabled,
                    onTap: isModelEnabled ? _onModelTapped : () {},
                  ),
                  const SizedBox(height: 8),

                  // Eligibility Notice Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 1.5),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Only listed brands and models are eligible for trade-in on this platform.',
                            textAlign: TextAlign.justify,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Storage Capacity Field
                  _buildFieldLabel('Storage Capacity'),
                  const SizedBox(height: 10),
                  _buildStorageGrid(),
                  const SizedBox(height: 20),

                  // Colour Field
                  _buildFieldLabel('Colour'),
                  const SizedBox(height: 8),
                  _buildDropdownTrigger(
                    title: _selectedColour ?? 'Select Colour',
                    isSelected: _selectedColour != null,
                    isEnabled: true,
                    leadingWidget: _selectedColourSwatch != null
                        ? Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: _selectedColourSwatch,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey.shade400, width: 1),
                            ),
                          )
                        : null,
                    onTap: _onColourTapped,
                  ),
                  const SizedBox(height: 20),

                  // Device Age Field
                  _buildFieldLabel('Device Age (Approximate)'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      controller: _deviceAgeController,
                      focusNode: _deviceAgeFocusNode,
                      autofocus: false,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                      decoration: const InputDecoration(
                        hintText: 'e.g. 1',
                        suffixText: 'year(s)',
                        suffixStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                        hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '0 = Less than 1 year',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Divider
                  Divider(color: Colors.grey.shade200, height: 1),
                  const SizedBox(height: 20),

                  // Continue -> Button (Top)
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: (isFormComplete && !_isSubmitting) ? _onContinue : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C5AD2),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Continue',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isFormComplete ? Colors.white : const Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                  color: isFormComplete ? Colors.white : const Color(0xFF94A3B8),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Cancel Button (Bottom)
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Cancel',
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
            const SizedBox(height: 20),

            // Footer note: Your data is secure and encrypted
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'Your data is secure and encrypted.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
    ),
    bottomNavigationBar: const ReByteBottomNavBar(
      selectedIndex: 2,
    ),
  );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF0F172A),
      ),
    );
  }

  Widget _buildDropdownTrigger({
    required String title,
    required bool isSelected,
    required bool isEnabled,
    Widget? leadingWidget,
    required VoidCallback onTap,
  }) {
    final Color bgColor = isEnabled ? Colors.white : const Color(0xFFF8FAFC);
    final Color textColor = isEnabled
        ? (isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B))
        : const Color(0xFF94A3B8);
    final Color borderColor = isEnabled
        ? (isSelected ? const Color(0xFFCBD5E1) : const Color(0xFFE2E8F0))
        : const Color(0xFFE2E8F0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Row(
          children: [
            ?leadingWidget,
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: textColor,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: isEnabled ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageGrid() {
    final capacities = PhoneBrandsData.storageCapacities;
    // Row 1: 64 GB, 128 GB, 256 GB
    // Row 2: 512 GB, 1 TB, 2 TB
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildStorageChip(capacities[0])),
            const SizedBox(width: 8),
            Expanded(child: _buildStorageChip(capacities[1])),
            const SizedBox(width: 8),
            Expanded(child: _buildStorageChip(capacities[2])),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildStorageChip(capacities[3])),
            const SizedBox(width: 8),
            Expanded(child: _buildStorageChip(capacities[4])),
            const SizedBox(width: 8),
            Expanded(child: _buildStorageChip(capacities[5])),
          ],
        ),
      ],
    );
  }

  Widget _buildStorageChip(String capacity) {
    final bool isSelected = _selectedStorage == capacity;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedStorage = capacity;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1.2,
          ),
        ),
        child: Text(
          capacity,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF1E293B),
          ),
        ),
      ),
    );
  }
}
