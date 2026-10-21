import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/address_model.dart';
import '../services/address_service.dart';
import '../map_picker_page.dart';

class AddAddressDialog {
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

  /// Shows the Add / Edit Address bottom sheet form
  static Future<AddressModel?> show({
    required BuildContext context,
    required String email,
    AddressModel? address,
    bool isFirstAddress = false,
  }) async {
    final isEditing = address != null;

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

    bool isDefault = isEditing ? address.isDefault : (isFirstAddress ? true : false);
    bool isSubmitting = false;

    String? nameError;
    String? phoneError;
    String? addressLineError;
    String? postcodeError;
    String? cityError;
    String? stateError;
    String? otherTypeError;
    String? globalError;

    return await showModalBottomSheet<AddressModel>(
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

              if (name.isEmpty) {
                nameError = 'Recipient name is required';
              } else if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(name)) {
                nameError = 'Only alphabetic characters allowed';
              } else if (name.length > 30) {
                nameError = 'Recipient name cannot exceed 30 characters';
              } else {
                nameError = null;
              }

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
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F254B),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 20),
                              onPressed: () => Navigator.pop(sheetContext),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        if (globalError != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              globalError!,
                              style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

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

                        // Recipient Name
                        const Text(
                          'Recipient Name',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: nameController,
                          maxLength: 30,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(30),
                            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                          ],
                          onChanged: (_) {
                            setModalState(() {
                              if (nameError != null) {
                                final n = nameController.text.trim();
                                nameError = n.isEmpty ? 'Recipient name is required' : (n.length > 30 ? 'Recipient name cannot exceed 30 characters' : null);
                              }
                            });
                          },
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'e.g. John Doe',
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

                        // Phone Number (+60 Prefix container + Instant validation)
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

                        // Default Checkbox
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: isDefault,
                          onChanged: isFirstAddress
                              ? null
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

                        // Save Button
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

                                        setModalState(() {
                                          isSubmitting = true;
                                          globalError = null;
                                        });

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

                                          final res = await AddressService.updateAddress(email, updated);
                                          if (res['success'] != true) {
                                            setModalState(() {
                                              isSubmitting = false;
                                              globalError = res['error'] ?? 'Failed to update address';
                                            });
                                            return;
                                          }
                                          if (sheetContext.mounted) {
                                            Navigator.pop(sheetContext, updated);
                                          }
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

                                          final res = await AddressService.addAddress(email, newAddr);
                                          if (res['success'] != true) {
                                            setModalState(() {
                                              isSubmitting = false;
                                              globalError = res['error'] ?? 'Failed to add address';
                                            });
                                            return;
                                          }
                                          final savedAddr = res['data'] != null && res['data'] is Map<String, dynamic>
                                              ? AddressModel.fromJson(res['data'])
                                              : newAddr;
                                          if (sheetContext.mounted) {
                                            Navigator.pop(sheetContext, savedAddr);
                                          }
                                        }
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
}
