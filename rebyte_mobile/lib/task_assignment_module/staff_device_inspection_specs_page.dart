import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../device_tradein_module/data/phone_brands_data.dart';
import '../device_tradein_module/services/trade_in_service.dart';
import '../device_tradein_module/models/device_model.dart';
import '../device_tradein_module/widgets/searchable_selection_sheet.dart';
import 'widgets/staff_app_bar_and_drawer.dart';
import 'staff_upload_device_images_page.dart';

class StaffDeviceInspectionSpecsPage extends StatefulWidget {
  final Map<String, dynamic> task;
  final VoidCallback? onTaskUpdated;

  const StaffDeviceInspectionSpecsPage({
    super.key,
    required this.task,
    this.onTaskUpdated,
  });

  @override
  State<StaffDeviceInspectionSpecsPage> createState() =>
      _StaffDeviceInspectionSpecsPageState();
}

class _StaffDeviceInspectionSpecsPageState
    extends State<StaffDeviceInspectionSpecsPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _selectedBrand;
  String? _selectedModel;
  String? _selectedModelCode;
  String? _selectedStorage;
  String? _selectedColour;
  Color? _selectedColourSwatch;

  final TextEditingController _ramController = TextEditingController();
  final FocusNode _ramFocusNode = FocusNode();

  final TextEditingController _deviceAgeController = TextEditingController();
  final FocusNode _deviceAgeFocusNode = FocusNode();
  bool _isSubmitting = false;

  List<String> _loadedBrands = List.from(PhoneBrandsData.wellKnownPhoneBrands);
  final Map<String, List<String>> _loadedModels = {};

  @override
  void initState() {
    super.initState();
    _ramController.addListener(_onFieldChanged);
    _deviceAgeController.addListener(_onFieldChanged);

    _prefillFromTask();
    _fetchDeviceDetailsFromFirebase();
    _fetchBrandsFromLibrary();
  }

  void _prefillFromTask() {
    final task = widget.task;
    final taskDevice = task['device'] is Map ? (task['device'] as Map) : null;
    final taskItems = (task['items'] is List && (task['items'] as List).isNotEmpty && task['items'][0] is Map)
        ? (task['items'][0] as Map)
        : null;

    // 1. Storage
    final rawStorage = task['storage']?.toString() ??
        task['storageCapacity']?.toString() ??
        taskDevice?['storageCapacity']?.toString() ??
        taskDevice?['storage']?.toString() ??
        taskItems?['storage']?.toString() ??
        '256GB';
    _selectedStorage = _normalizeStorage(rawStorage);

    // 2. Model & Brand
    final rawDeviceModel = task['deviceModel']?.toString() ??
        task['modelName']?.toString() ??
        task['deviceName']?.toString() ??
        taskDevice?['model']?.toString() ??
        taskDevice?['name']?.toString() ??
        task['device']?.toString() ??
        task['model']?.toString() ??
        'iPhone 13 Pro';

    String cleanedModel = rawDeviceModel;
    if (_selectedStorage != null &&
        cleanedModel.toLowerCase().contains('(${_selectedStorage!.toLowerCase()})')) {
      cleanedModel = cleanedModel
          .replaceAll(
              RegExp('\\(${RegExp.escape(_selectedStorage!)}\\)', caseSensitive: false), '')
          .trim();
    } else {
      cleanedModel = cleanedModel
          .replaceAll(RegExp(r'\s*\(\d+\s*(?:GB|TB)\)', caseSensitive: false), '')
          .trim();
    }

    String brandGuess = task['brand']?.toString() ??
        taskDevice?['brand']?.toString() ??
        taskItems?['brand']?.toString() ??
        '';
    if (brandGuess.isEmpty) {
      final firstWord = cleanedModel.split(' ').first;
      if (cleanedModel.toLowerCase().startsWith('iphone')) {
        brandGuess = 'Apple';
      } else if (firstWord.isNotEmpty &&
          PhoneBrandsData.wellKnownPhoneBrands
              .any((b) => b.toLowerCase() == firstWord.toLowerCase())) {
        brandGuess = PhoneBrandsData.wellKnownPhoneBrands.firstWhere(
            (b) => b.toLowerCase() == firstWord.toLowerCase());
      } else {
        brandGuess = 'Apple';
      }
    }
    _selectedBrand = brandGuess;
    _selectedModel = cleanedModel;
    _selectedModelCode = task['modelCode']?.toString() ?? taskDevice?['modelCode']?.toString();

    // 3. Colour
    final rawColor = task['color']?.toString() ??
        task['colour']?.toString() ??
        taskDevice?['colour']?.toString() ??
        taskDevice?['color']?.toString() ??
        taskItems?['color']?.toString() ??
        'Graphite';
    _selectedColour = rawColor;
    for (var c in PhoneBrandsData.popularColors) {
      if (c.name.toLowerCase() == rawColor.toLowerCase()) {
        _selectedColourSwatch = c.color;
        break;
      }
    }

    // 4. Device Age (from Firebase device record in task, or task device/items)
    final rawAge = task['deviceAge']?.toString() ??
        taskDevice?['deviceAge']?.toString() ??
        taskItems?['deviceAge']?.toString() ??
        task['age']?.toString() ??
        '1';
    final ageDigits = rawAge.replaceAll(RegExp(r'\D'), '');
    _deviceAgeController.text = ageDigits.isNotEmpty ? ageDigits : '1';


    // 5. RAM (restricted to integer)
    final rawRam = task['ram']?.toString() ??
        taskDevice?['ram']?.toString() ??
        taskItems?['ram']?.toString() ??
        '';
    final ramDigits = rawRam.replaceAll(RegExp(r'\D'), '');
    if (ramDigits.isNotEmpty) {
      _ramController.text = ramDigits;
    }

    if (_selectedBrand != null) {
      _preloadModelsForBrand(_selectedBrand!);
    }
  }

  /// Asynchronously fetch the authoritative device record from Firebase to ensure deviceAge and specs are 100% accurate
  Future<void> _fetchDeviceDetailsFromFirebase() async {
    final task = widget.task;
    final deviceId = task['deviceID']?.toString() ?? '';
    final tradeInId = task['tradeInID']?.toString() ??
        task['tradeInRequestID']?.toString() ??
        task['orderID']?.toString() ??
        task['taskID']?.toString() ??
        '';

    Map<String, dynamic>? devRecord;
    if (deviceId.isNotEmpty) {
      devRecord = await TradeInService.getDeviceById(deviceId);
    }
    if (devRecord == null && tradeInId.isNotEmpty) {
      final reqDetails = await TradeInService.getTradeInRequestDetails(tradeInId);
      if (reqDetails != null && reqDetails['device'] is Map) {
        devRecord = Map<String, dynamic>.from(reqDetails['device'] as Map);
      }
    }

    if (devRecord != null && mounted) {
      final fbAge = devRecord['deviceAge']?.toString() ?? '';
      if (fbAge.isNotEmpty) {
        final ageDigits = fbAge.replaceAll(RegExp(r'\D'), '');
        if (ageDigits.isNotEmpty) {
          setState(() {
            _deviceAgeController.text = ageDigits;
          });
        }
      }

      final fbRam = devRecord['ram']?.toString() ?? '';
      if (fbRam.isNotEmpty && _ramController.text.isEmpty) {
        final ramDigits = fbRam.replaceAll(RegExp(r'\D'), '');
        if (ramDigits.isNotEmpty) {
          setState(() {
            _ramController.text = ramDigits;
          });
        }
      }

      final fbBrand = devRecord['brand']?.toString() ?? '';
      if (fbBrand.isNotEmpty && (_selectedBrand == null || _selectedBrand == 'Apple')) {
        setState(() {
          _selectedBrand = fbBrand;
          _preloadModelsForBrand(fbBrand);
        });
      }

      final fbModel = devRecord['model']?.toString() ?? '';
      if (fbModel.isNotEmpty) {
        setState(() {
          _selectedModel = fbModel;
        });
      }

      final fbStorage = devRecord['storageCapacity']?.toString() ?? devRecord['storage']?.toString() ?? '';
      if (fbStorage.isNotEmpty) {
        setState(() {
          _selectedStorage = _normalizeStorage(fbStorage);
        });
      }

      final fbColour = devRecord['colour']?.toString() ?? devRecord['color']?.toString() ?? '';
      if (fbColour.isNotEmpty && (_selectedColour == null || _selectedColour == 'Graphite')) {
        Color? swatch;
        for (var c in PhoneBrandsData.popularColors) {
          if (c.name.toLowerCase() == fbColour.toLowerCase()) {
            swatch = c.color;
            break;
          }
        }
        setState(() {
          _selectedColour = fbColour;
          _selectedColourSwatch = swatch;
        });
      }
    }
  }

  String _normalizeStorage(String raw) {
    final clean = raw.replaceAll(' ', '').toUpperCase();
    for (final cap in PhoneBrandsData.storageCapacities) {
      if (cap.replaceAll(' ', '').toUpperCase() == clean) {
        return cap;
      }
    }
    return '256 GB';
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
    _ramController.removeListener(_onFieldChanged);
    _deviceAgeController.removeListener(_onFieldChanged);
    _ramController.dispose();
    _ramFocusNode.dispose();
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

  void _onContinue() async {
    final rawAgeText = _deviceAgeController.text.trim();
    final int? ageNum = int.tryParse(rawAgeText);
    if (ageNum == null) {
      StaffToast.show(context, 'Please enter a valid device age in years', isError: true);
      return;
    }

    final rawRamText = _ramController.text.trim();
    final int? ramNum = int.tryParse(rawRamText);
    if (ramNum == null || ramNum <= 0) {
      StaffToast.show(context, 'Please enter a valid RAM capacity in GB (integer only)', isError: true);
      return;
    }

    final String formattedAge = ageNum == 0 ? '< 1 year' : '$ageNum year(s)';
    final String ramFormatted = '${ramNum}GB';

    final task = widget.task;
    String deviceId = task['deviceID']?.toString() ??
        (task['device'] is Map ? task['device']['deviceID']?.toString() : null) ??
        '';

    if (deviceId.isEmpty) {
      final tradeInId = task['tradeInRequestID']?.toString() ??
          task['tradeInID']?.toString() ??
          task['orderID']?.toString() ??
          '';
      if (tradeInId.isNotEmpty) {
        final reqDetails = await TradeInService.getTradeInRequestDetails(tradeInId);
        if (reqDetails != null) {
          deviceId = reqDetails['deviceID']?.toString() ??
              (reqDetails['device'] is Map ? reqDetails['device']['deviceID']?.toString() : null) ??
              '';
        }
      }
    }

    setState(() => _isSubmitting = true);

    // Linkage to Firebase: Page 2 - Update data of linked device record and add ram attribute
    if (deviceId.isNotEmpty) {
      try {
        final updateRes = await TradeInService.updateDeviceRecord(
          deviceID: deviceId,
          brand: _selectedBrand ?? 'Apple',
          model: _selectedModel ?? 'iPhone 13 Pro',
          modelCode: _selectedModelCode,
          storageCapacity: _selectedStorage ?? '256GB',
          colour: _selectedColour ?? 'Graphite',
          deviceAge: formattedAge,
          ram: ramFormatted,
        );
        if (updateRes['success'] != true && mounted) {
          StaffToast.show(context, updateRes['message'] ?? 'Failed to update device record', isError: true);
          setState(() => _isSubmitting = false);
          return;
        }
      } catch (e) {
        if (mounted) {
          StaffToast.show(context, 'Error updating device record: $e', isError: true);
          setState(() => _isSubmitting = false);
          return;
        }
      }
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    final imei = task['imei']?.toString() ??
        task['imeiNum']?.toString() ??
        '';

    // Update in-memory task device info
    task['deviceID'] = deviceId;
    task['ram'] = ramFormatted;
    task['storage'] = _selectedStorage;
    task['brand'] = _selectedBrand;
    task['deviceModel'] = _selectedModel;
    task['color'] = _selectedColour;
    task['deviceAge'] = formattedAge;

    final devModel = DeviceModel(
      deviceID: deviceId,
      brand: _selectedBrand ?? 'Apple',
      model: _selectedModel ?? 'iPhone 13 Pro',
      modelCode: _selectedModelCode,
      storageCapacity: _selectedStorage ?? '256GB',
      colour: _selectedColour ?? 'Graphite',
      imeiNum: imei,
      status: 'inspecting',
      deviceAge: formattedAge,
      ram: ramFormatted,
    );

    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: 'StaffUploadDeviceImagesPage'),
        builder: (_) => StaffUploadDeviceImagesPage(
          task: task,
          device: devModel,
          onTaskUpdated: widget.onTaskUpdated,
        ),
      ),
    );

    if (res != null && mounted) {
      widget.onTaskUpdated?.call();
      Navigator.pop(context, res);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isBrandOther = _selectedBrand == 'Other';
    final bool isModelEnabled = _selectedBrand != null && !isBrandOther;
    final bool isFormComplete = _selectedBrand != null &&
        _selectedModel != null &&
        _selectedStorage != null &&
        _selectedColour != null &&
        _ramController.text.trim().isNotEmpty &&
        _deviceAgeController.text.trim().isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: StaffAppBar(scaffoldKey: _scaffoldKey),
      drawer: const StaffDrawer(selectedIndex: 2),
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

                      // Model Field
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
                      const SizedBox(height: 20),

                      // Storage Capacity Field
                      _buildFieldLabel('Storage Capacity'),
                      const SizedBox(height: 10),
                      _buildStorageGrid(),
                      const SizedBox(height: 20),

                      // RAM Field (Strict Integer Input)
                      _buildFieldLabel('RAM'),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: TextField(
                          controller: _ramController,
                          focusNode: _ramFocusNode,
                          autofocus: false,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'e.g. 8',
                            suffixText: 'GB',
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
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'e.g. 1',
                            suffixText: 'year(s)',
                            suffixStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                            hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
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

                      // Continue -> Button
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

                      // Cancel Button
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2, // Tasks tab
        onTap: (index) {
          if (index != 2) {
            Navigator.pop(context);
          }
        },
        selectedItemColor: const Color(0xFF0C5AD2),
        unselectedItemColor: const Color(0xFF64748B),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded, size: 24), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today_rounded, size: 24), label: 'Schedule'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined, size: 24), label: 'Tasks'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline, size: 24), label: 'Profile'),
        ],
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
            if (leadingWidget != null) leadingWidget,
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
