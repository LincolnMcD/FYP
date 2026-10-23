import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import 'models/address_model.dart';
import 'services/address_service.dart';
import 'services/session_service.dart';
import 'map_picker_page.dart';

class ManageAddressPage extends StatefulWidget {
  final String email;

  const ManageAddressPage({super.key, required this.email});

  @override
  State<ManageAddressPage> createState() => _ManageAddressPageState();
}

class _ManageAddressPageState extends State<ManageAddressPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<AddressModel> _addresses = [];
  bool _isLoading = true;
  String? _toastMessage;
  bool _isToastError = false;
  String? _userName;

  // 13 Malaysian States and 3 Federal Territories
  static const List<String> malaysianStates = [
    'Johor',
    'Kedah',
    'Kelantan',
    'Melaka',
    'Negeri Sembilan',
    'Pahang',
    'Penang',
    'Perak',
    'Perlis',
    'Sabah',
    'Sarawak',
    'Selangor',
    'Terengganu',
    'Wilayah Persekutuan Kuala Lumpur',
    'Wilayah Persekutuan Labuan',
    'Wilayah Persekutuan Putrajaya',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadAddresses();
  }

  Future<void> _loadUserInfo() async {
    try {
      final session = await SessionService.getSession();
      if (mounted && session.isNotEmpty) {
        setState(() {
          _userName = session['name'];
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAddresses() async {
    setState(() => _isLoading = true);
    final data = await AddressService.getAddresses(widget.email);
    if (mounted) {
      setState(() {
        _addresses = data;
        _isLoading = false;
      });
    }
  }

  void _showTopToast(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _toastMessage = message;
      _isToastError = isError;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _toastMessage == message) {
        setState(() => _toastMessage = null);
      }
    });
  }

  Future<void> _handleSetDefault(AddressModel address) async {
    final success = await AddressService.setDefaultAddress(widget.email, address.addressID);
    if (success) {
      _showTopToast('Default delivery address updated.');
    } else {
      _showTopToast('Failed to update default address.', isError: true);
    }
    await _loadAddresses();
  }

  Future<void> _handleDelete(AddressModel address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Address',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF0F254B)),
        ),
        content: Text(
          'Are you sure you want to delete "${address.addressType}" address (${address.addressLine})?',
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await AddressService.deleteAddress(widget.email, address.addressID);
      if (success) {
        _showTopToast('Address removed successfully.');
      } else {
        _showTopToast('Failed to remove address.', isError: true);
      }
      await _loadAddresses();
    }
  }

  void _openAddressDialog({AddressModel? address}) {
    final isEditing = address != null;

    // Determine initial type category
    String selectedCategory = 'Home';
    String initialCustomOther = '';
    if (address != null) {
      if (address.addressType.toLowerCase() == 'home') {
        selectedCategory = 'Home';
      } else if (address.addressType.toLowerCase() == 'office' || address.addressType.toLowerCase() == 'work') {
        selectedCategory = 'Office';
      } else {
        selectedCategory = 'Other';
        initialCustomOther = address.addressType;
      }
    }

    final otherTypeController = TextEditingController(text: initialCustomOther);
    final nameController = TextEditingController(text: address?.recipientName ?? '');
    
    // Format initial phone number (remove +60 or leading 0 so input begins with 1...)
    String rawPhone = address?.phoneNumber ?? '';
    if (rawPhone.startsWith('+60')) {
      rawPhone = rawPhone.substring(3);
    } else if (rawPhone.startsWith('60')) {
      rawPhone = rawPhone.substring(2);
    } else if (rawPhone.startsWith('0')) {
      rawPhone = rawPhone.substring(1);
    }
    final phoneController = TextEditingController(text: rawPhone);

    final addressLineController = TextEditingController(text: address?.addressLine ?? '');
    final postcodeController = TextEditingController(text: address?.postcode ?? '');
    final cityController = TextEditingController(text: address?.city ?? '');

    String? selectedState = address?.state;
    if (selectedState != null && !malaysianStates.contains(selectedState)) {
      selectedState = null;
    }

    double? selectedLat = address?.latitude;
    double? selectedLng = address?.longitude;

    // Default card rule: If first address, cannot be unticked
    final bool isFirstAddress = _addresses.isEmpty && !isEditing;
    bool isDefault = isEditing ? address.isDefault : (_addresses.isEmpty ? true : false);

    bool isSubmitting = false;
    String? nameError;
    String? phoneError;
    String? addressLineError;
    String? postcodeError;
    String? cityError;
    String? stateError;
    String? otherTypeError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            void validateAll() {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              final addr = addressLineController.text.trim();
              final post = postcodeController.text.trim();
              final city = cityController.text.trim();
              final other = otherTypeController.text.trim();

              // Recipient Name: Required, alphabetic characters only, limit 30 chars
              if (name.isEmpty) {
                nameError = 'Recipient name is required';
              } else if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(name)) {
                nameError = 'Only alphabetic characters allowed';
              } else if (name.length > 30) {
                nameError = 'Recipient name cannot exceed 30 characters';
              } else {
                nameError = null;
              }

              // Phone Number validation (same as register/modify profile page: +60 prefix, starts with 1, 011 -> 10 digits after 60, other 01x -> 9 digits after 60)
              if (phone.isEmpty) {
                phoneError = 'Phone number is required';
              } else if (!phone.startsWith('1')) {
                phoneError = 'Must start with 1';
              } else if (phone.startsWith('11') && phone.length != 10) {
                phoneError = 'Must be exactly 10 digits';
              } else if (phone.startsWith('1') && !phone.startsWith('11') && phone.length != 9) {
                phoneError = 'Must be exactly 9 digits';
              } else {
                phoneError = null;
              }

              // Address Line: Required, limit 65 chars
              if (addr.isEmpty) {
                addressLineError = 'Street address / unit number is required';
              } else if (addr.length > 65) {
                addressLineError = 'Address line cannot exceed 65 characters';
              } else {
                addressLineError = null;
              }

              postcodeError = post.isEmpty
                  ? 'Postcode is required'
                  : (post.length != 5 || int.tryParse(post) == null ? 'Must be 5-digit postcode' : null);

              // City: Required, limit 20 chars
              if (city.isEmpty) {
                cityError = 'City is required';
              } else if (city.length > 20) {
                cityError = 'City cannot exceed 20 characters';
              } else {
                cityError = null;
              }

              stateError = (selectedState == null || selectedState!.isEmpty) ? 'Please select a state' : null;

              if (selectedCategory == 'Other') {
                if (other.isEmpty) {
                  otherTypeError = 'Please specify address type';
                } else if (other.length > 20) {
                  otherTypeError = 'Limit not more than 20 characters';
                } else {
                  otherTypeError = null;
                }
              } else {
                otherTypeError = null;
              }
            }

            bool hasFormChanged() {
              if (!isEditing) return true;
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              final addr = addressLineController.text.trim();
              final post = postcodeController.text.trim();
              final city = cityController.text.trim();
              final currentType = selectedCategory == 'Other' ? otherTypeController.text.trim() : selectedCategory;

              final originalType = address.addressType;
              final originalName = address.recipientName;
              final originalAddr = address.addressLine;
              final originalPost = address.postcode;
              final originalCity = address.city;
              final originalState = address.state;
              final originalDefault = address.isDefault;
              final originalLat = address.latitude;
              final originalLng = address.longitude;

              if (name != originalName) return true;
              if (phone != rawPhone) return true;
              if (addr != originalAddr) return true;
              if (post != originalPost) return true;
              if (city != originalCity) return true;
              if (selectedState != originalState) return true;
              if (currentType != originalType) return true;
              if (isDefault != originalDefault) return true;
              if (selectedLat != originalLat || selectedLng != originalLng) return true;

              return false;
            }

            bool isFormValid() {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              final addr = addressLineController.text.trim();
              final post = postcodeController.text.trim();
              final city = cityController.text.trim();
              final other = otherTypeController.text.trim();

              if (name.isEmpty || !RegExp(r'^[a-zA-Z\s]+$').hasMatch(name) || name.length > 30) {
                return false;
              }
              if (phone.isEmpty || !phone.startsWith('1')) {
                return false;
              }
              if (phone.startsWith('11') && phone.length != 10) {
                return false;
              }
              if (phone.startsWith('1') && !phone.startsWith('11') && phone.length != 9) {
                return false;
              }
              if (addr.isEmpty || addr.length > 65) {
                return false;
              }
              if (post.isEmpty || post.length != 5 || int.tryParse(post) == null) {
                return false;
              }
              if (city.isEmpty || city.length > 20) {
                return false;
              }
              if (selectedState == null || selectedState!.isEmpty) {
                return false;
              }
              if (selectedCategory == 'Other' && (other.isEmpty || other.length > 20)) {
                return false;
              }

              // In edit mode: must have at least one modified field
              if (isEditing && !hasFormChanged()) {
                return false;
              }

              return true;
            }

            return SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(sheetContext).unfocus(),
                child: Container(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
                    left: 20,
                    right: 20,
                    top: 20,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isEditing ? 'Edit Address' : 'Add New Address',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F254B),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                              onPressed: () => Navigator.pop(sheetContext),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Address Type Selector (Home, Office, Other)
                        const Text(
                          'Address Type',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: ['Home', 'Office', 'Other'].map((type) {
                            final isSelected = selectedCategory == type;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: ChoiceChip(
                                label: Text(type),
                                selected: isSelected,
                                selectedColor: const Color(0xFF0C5AD2).withValues(alpha: 0.15),
                                labelStyle: TextStyle(
                                  color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF475569),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                                onSelected: (_) {
                                  setModalState(() {
                                    selectedCategory = type;
                                    otherTypeError = null;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),

                        // If "Other" selected, show input with 20 chars limit
                        if (selectedCategory == 'Other') ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: otherTypeController,
                            maxLength: 20,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(20),
                            ],
                            onChanged: (_) {
                              setModalState(() {
                                final text = otherTypeController.text.trim();
                                if (text.length > 20) {
                                  otherTypeError = 'Limit not more than 20 characters';
                                } else {
                                  otherTypeError = null;
                                }
                              });
                            },
                            decoration: InputDecoration(
                              counterText: '${otherTypeController.text.length}/20',
                              hintText: 'e.g. Warehouse, Parents (Max 20 chars)',
                              hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              errorText: otherTypeError,
                              errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),

                        // Recipient Name (Alphabet only, Limit 30 chars)
                        const Text(
                          'Recipient Name',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: nameController,
                          maxLength: 30,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                            LengthLimitingTextInputFormatter(30),
                          ],
                          onChanged: (_) {
                            setModalState(() {
                              final n = nameController.text.trim();
                              if (nameError != null) {
                                if (n.isEmpty) {
                                  nameError = 'Recipient name is required';
                                } else if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(n)) {
                                  nameError = 'Only alphabetic characters allowed';
                                } else if (n.length > 30) {
                                  nameError = 'Recipient name cannot exceed 30 characters';
                                } else {
                                  nameError = null;
                                }
                              }
                            });
                          },
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'e.g. Peter Tan',
                            hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            errorText: nameError,
                            errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Phone Number (+60 prefix, starts with 1, 011 -> 10 digits, other -> 9 digits)
                        const Text(
                          'Phone Number',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(10),
                                  bottomLeft: Radius.circular(10),
                                ),
                              ),
                              child: const Text(
                                '+60',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0C5AD2),
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: phoneController,
                                keyboardType: TextInputType.phone,
                                maxLength: 10,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                onChanged: (val) {
                                  setModalState(() {
                                    final p = val.trim();
                                    if (p.isEmpty) {
                                      phoneError = 'Phone number is required';
                                    } else if (!p.startsWith('1')) {
                                      phoneError = 'Must start with 1';
                                    } else if (p.startsWith('11') && p.length != 10) {
                                      phoneError = 'Must be exactly 10 digits';
                                    } else if (p.startsWith('1') && !p.startsWith('11') && p.length != 9) {
                                      phoneError = 'Must be exactly 9 digits';
                                    } else {
                                      phoneError = null;
                                    }
                                  });
                                },
                                decoration: InputDecoration(
                                  counterText: '',
                                  hintText: '123456789 / 1123456789',
                                  hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  errorText: phoneError,
                                  errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                                  border: const OutlineInputBorder(
                                    borderRadius: BorderRadius.only(
                                      topRight: Radius.circular(10),
                                      bottomRight: Radius.circular(10),
                                    ),
                                    borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  enabledBorder: const OutlineInputBorder(
                                    borderRadius: BorderRadius.only(
                                      topRight: Radius.circular(10),
                                      bottomRight: Radius.circular(10),
                                    ),
                                    borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Street Address / Unit Number (addressLine, limit 65 chars) + Map Pointing Button
                        // Address Details - Disabled with Gray Overlay (Populated from Map Selection Only)
                        Builder(
                          builder: (bCtx) {
                            Future<void> openMapPicker() async {
                              final parts = [
                                addressLineController.text.trim(),
                                postcodeController.text.trim(),
                                cityController.text.trim(),
                                selectedState ?? '',
                              ].where((s) => s.isNotEmpty).toList();
                              final inputtedAddress = parts.isNotEmpty ? parts.join(', ') : null;

                              final result = await Navigator.push<Map<String, dynamic>>(
                                sheetContext,
                                MaterialPageRoute(
                                  builder: (ctx) => MapPickerPage(
                                    initialLat: selectedLat,
                                    initialLng: selectedLng,
                                    initialAddress: inputtedAddress,
                                  ),
                                  settings: const RouteSettings(name: '/map_picker'),
                                ),
                              );

                              if (result != null) {
                                setModalState(() {
                                  final rawLine = result['addressLine']?.toString() ?? '';
                                  final rawPost = result['postcode']?.toString() ?? '';
                                  final rawCity = result['city']?.toString() ?? '';
                                  final rawState = result['state']?.toString() ?? '';

                                  addressLineController.text = rawLine.length > 65 ? rawLine.substring(0, 65) : rawLine;
                                  addressLineError = null;

                                  postcodeController.text = rawPost.length > 5 ? rawPost.substring(0, 5) : rawPost;
                                  postcodeError = null;

                                  cityController.text = rawCity.length > 20 ? rawCity.substring(0, 20) : rawCity;
                                  cityError = null;

                                  if (malaysianStates.contains(rawState)) {
                                    selectedState = rawState;
                                  } else {
                                    selectedState = rawState.isNotEmpty ? rawState : null;
                                  }
                                  stateError = null;

                                  if (result['lat'] != null) {
                                    selectedLat = (result['lat'] as num).toDouble();
                                  }
                                  if (result['lng'] != null) {
                                    selectedLng = (result['lng'] as num).toDouble();
                                  }
                                });
                              }

                              if (sheetContext.mounted) {
                                FocusScope.of(sheetContext).unfocus();
                              }
                              FocusManager.instance.primaryFocus?.unfocus();
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Delivery Address',
                                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                    ),
                                    InkWell(
                                      onTap: openMapPicker,
                                      borderRadius: BorderRadius.circular(6),
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        child: Row(
                                          children: [
                                            Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF0C5AD2)),
                                            SizedBox(width: 3),
                                            Text(
                                              'Point on Map',
                                              style: TextStyle(
                                                fontSize: 11.5,
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
                                const SizedBox(height: 8),

                                // Gray Overlay Card containing all disabled address inputs
                                InkWell(
                                  onTap: openMapPicker,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9), // Gray overlay background
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: (addressLineError != null || postcodeError != null || cityError != null || stateError != null)
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFFCBD5E1),
                                        width: 1.2,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Tap prompt helper
                                        Row(
                                          children: [
                                            Icon(
                                              addressLineController.text.trim().isEmpty ? Icons.touch_app_outlined : Icons.check_circle_outline,
                                              size: 15,
                                              color: addressLineController.text.trim().isEmpty ? const Color(0xFF0C5AD2) : const Color(0xFF10B981),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                addressLineController.text.trim().isEmpty
                                                    ? 'Click here or "Point on Map" to select delivery location'
                                                    : 'Location pointed on map (Tap to re-select)',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: addressLineController.text.trim().isEmpty ? const Color(0xFF0C5AD2) : const Color(0xFF059669),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        // Address Line (Street address, unit no.)
                                        const Text(
                                          'Address Line (Street address, unit no.)',
                                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                        ),
                                        const SizedBox(height: 4),
                                        TextField(
                                          controller: addressLineController,
                                          enabled: false,
                                          maxLines: 2,
                                          style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            hintText: 'Point on map to fill address line',
                                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                                            filled: true,
                                            fillColor: const Color(0xFFE2E8F0).withValues(alpha: 0.5),
                                            errorText: addressLineError,
                                            errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                                            disabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(8),
                                              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                            ),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          ),
                                        ),
                                        const SizedBox(height: 10),

                                        // Postcode & City Row
                                        Row(
                                          children: [
                                            Expanded(
                                              flex: 4,
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Postcode',
                                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  TextField(
                                                    controller: postcodeController,
                                                    enabled: false,
                                                    style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
                                                    decoration: InputDecoration(
                                                      isDense: true,
                                                      hintText: '—',
                                                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                                                      filled: true,
                                                      fillColor: const Color(0xFFE2E8F0).withValues(alpha: 0.5),
                                                      errorText: postcodeError,
                                                      errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                                                      disabledBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                                      ),
                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              flex: 6,
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'City',
                                                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  TextField(
                                                    controller: cityController,
                                                    enabled: false,
                                                    style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
                                                    decoration: InputDecoration(
                                                      isDense: true,
                                                      hintText: '—',
                                                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                                                      filled: true,
                                                      fillColor: const Color(0xFFE2E8F0).withValues(alpha: 0.5),
                                                      errorText: cityError,
                                                      errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                                                      disabledBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(8),
                                                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                                      ),
                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        // State Row
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'State',
                                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                            ),
                                            const SizedBox(height: 4),
                                            TextField(
                                              controller: TextEditingController(text: selectedState ?? ''),
                                              enabled: false,
                                              style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
                                              decoration: InputDecoration(
                                                isDense: true,
                                                hintText: '—',
                                                hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                                                filled: true,
                                                fillColor: const Color(0xFFE2E8F0).withValues(alpha: 0.5),
                                                errorText: stateError,
                                                errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                                                disabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),

                        // Set Default Checkbox (First address cannot be unticked)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: isDefault,
                          onChanged: isFirstAddress
                              ? null // First card cannot be unticked
                              : (val) => setModalState(() => isDefault = val ?? false),
                          title: const Text(
                            'Set as default delivery address',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          ),
                          subtitle: isFirstAddress
                              ? const Text(
                                  'Your first address is automatically set as default.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                )
                              : null,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const SizedBox(height: 16),

                        // Save Button (Disabled if any required input is missing or invalid)
                        Builder(
                          builder: (context) {
                            final canSubmit = !isSubmitting && isFormValid();
                            return SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: canSubmit
                                    ? () async {
                                        setModalState(() {
                                          validateAll();
                                        });

                                        if (nameError != null ||
                                            phoneError != null ||
                                            addressLineError != null ||
                                            postcodeError != null ||
                                            cityError != null ||
                                            stateError != null ||
                                            otherTypeError != null) {
                                          return;
                                        }

                                        setModalState(() => isSubmitting = true);

                                        final finalAddressType = selectedCategory == 'Other'
                                            ? otherTypeController.text.trim()
                                            : selectedCategory;

                                        final cleanPhone = phoneController.text.trim();
                                        final formattedPhone = cleanPhone.startsWith('+60') ? cleanPhone : '+60$cleanPhone';

                                        if (isEditing) {
                                          final updated = address.copyWith(
                                            addressLine: addressLineController.text.trim(),
                                            postcode: postcodeController.text.trim(),
                                            city: cityController.text.trim(),
                                            state: selectedState!,
                                            recipientName: nameController.text.trim(),
                                            phoneNumber: formattedPhone,
                                            addressType: finalAddressType,
                                            isDefault: isDefault,
                                            latitude: selectedLat,
                                            longitude: selectedLng,
                                          );

                                          final res = await AddressService.updateAddress(widget.email, updated);
                                          if (res['success'] != true) {
                                            setModalState(() {
                                              isSubmitting = false;
                                              _showTopToast(res['error'] ?? 'Failed to update address', isError: true);
                                            });
                                            return;
                                          }
                                          if (sheetContext.mounted) {
                                            Navigator.pop(sheetContext);
                                          }
                                          _showTopToast('Address updated successfully.');
                                        } else {
                                          final newAddr = AddressModel(
                                            id: '',
                                            addressID: '',
                                            addressLine: addressLineController.text.trim(),
                                            postcode: postcodeController.text.trim(),
                                            city: cityController.text.trim(),
                                            state: selectedState!,
                                            recipientName: nameController.text.trim(),
                                            phoneNumber: formattedPhone,
                                            addressType: finalAddressType,
                                            isDefault: isDefault,
                                            latitude: selectedLat,
                                            longitude: selectedLng,
                                          );

                                          final res = await AddressService.addAddress(widget.email, newAddr);
                                          if (res['success'] != true) {
                                            setModalState(() {
                                              isSubmitting = false;
                                              _showTopToast(res['error'] ?? 'Failed to add address', isError: true);
                                            });
                                            return;
                                          }
                                          if (sheetContext.mounted) {
                                            Navigator.pop(sheetContext);
                                          }
                                          _showTopToast('New address saved.');
                                        }

                                        await _loadAddresses();
                                      }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0C5AD2),
                                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Text(
                                        isEditing ? 'Save Changes' : 'Add Address',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: ReByteAppBar(
        scaffoldKey: _scaffoldKey,
      ),
      drawer: ReByteDrawer(
        isLoggedIn: true,
        email: widget.email,
        name: _userName,
        selectedIndex: 4,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Back Arrow
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                          onPressed: () => Navigator.pop(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(height: 14),

                        // Title Bar with + Button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Manage Address',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F254B),
                                letterSpacing: -0.3,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, size: 26, color: Color(0xFF0F254B)),
                              onPressed: () => _openAddressDialog(),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Address Cards List
                        if (_isLoading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(40.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else ...[
                          ..._addresses.map((addr) => _buildAddressCard(addr)),
                          const SizedBox(height: 6),
                          _buildAddAddressCard(),
                          const SizedBox(height: 28),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Top Floating Toast Banner
            if (_toastMessage != null)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: Dismissible(
                  key: UniqueKey(),
                  direction: DismissDirection.horizontal,
                  onDismissed: (_) => setState(() => _toastMessage = null),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: _isToastError ? const Color(0xFFE11D48) : Colors.green.shade600,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isToastError ? Icons.error_outline : Icons.check_circle_outline,
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _toastMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: -1,
      ),
    );
  }

  Widget _buildAddressCard(AddressModel addr) {
    IconData typeIcon = Icons.home_outlined;
    final typeLower = addr.addressType.toLowerCase();
    if (typeLower == 'office' || typeLower == 'work') {
      typeIcon = Icons.business_center_outlined;
    } else if (typeLower != 'home') {
      typeIcon = Icons.location_on_outlined;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF0C5AD2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row with Type Icon Badge + Details + Default badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type Icon Container (matches _buildCardBrandLogo style)
              Container(
                width: 52,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  typeIcon,
                  size: 22,
                  color: const Color(0xFF0C5AD2),
                ),
              ),
              const SizedBox(width: 14),

              // Address details occupying full width
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: Type title and Default badge aligned to right
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            addr.addressType,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        if (addr.isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C5AD2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline, size: 13, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'Default',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${addr.recipientName} • ${addr.phoneNumber}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${addr.addressLine}, ${addr.postcode} ${addr.city}, ${addr.state}',
                      textAlign: TextAlign.justify,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF475569),
                        height: 1.4,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Bottom Action: Edit + Set Default + Trash (Matches manage payment account layout)
          Row(
            children: [
              // Edit button
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: () => _openAddressDialog(address: addr),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F254B),
                      ),
                    ),
                  ),
                ),
              ),

              // Set Default Button (when not default)
              if (!addr.isDefault) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      onPressed: () => _handleSetDefault(addr),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEEF2FF),
                        foregroundColor: const Color(0xFF0C5AD2),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text(
                        'Set Default',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0C5AD2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(width: 10),

              // Trash button (exact match with payment account trash)
              Container(
                width: 54,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE11D48), size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _handleDelete(addr),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddAddressCard() {
    return InkWell(
      onTap: () => _openAddressDialog(),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFCBD5E1),
            width: 1.2,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFEEF2FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_location_alt_outlined,
                size: 28,
                color: Color(0xFF0C5AD2),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Add New Address',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F254B),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Save another delivery\nlocation to your account.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF64748B),
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
