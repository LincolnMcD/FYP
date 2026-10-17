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

                        // Address Line with GPS Point on Map
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Address Line (Street address, unit no.)',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                            ),
                            InkWell(
                              onTap: () async {
                                final result = await Navigator.push<Map<String, dynamic>>(
                                  sheetContext,
                                  MaterialPageRoute(
                                    builder: (ctx) => const MapPickerPage(),
                                    settings: const RouteSettings(name: '/map_picker'),
                                  ),
                                );

                                if (result != null) {
                                  setModalState(() {
                                    if (result['addressLine'] != null && result['addressLine'].toString().isNotEmpty) {
                                      final rawLine = result['addressLine'].toString();
                                      addressLineController.text = rawLine.length > 65 ? rawLine.substring(0, 65) : rawLine;
                                      addressLineError = null;
                                    }
                                    if (result['postcode'] != null && result['postcode'].toString().isNotEmpty) {
                                      final rawPost = result['postcode'].toString();
                                      postcodeController.text = rawPost.length > 5 ? rawPost.substring(0, 5) : rawPost;
                                      postcodeError = null;
                                    }
                                    if (result['city'] != null && result['city'].toString().isNotEmpty) {
                                      final rawCity = result['city'].toString();
                                      cityController.text = rawCity.length > 20 ? rawCity.substring(0, 20) : rawCity;
                                      cityError = null;
                                    }
                                    if (result['state'] != null && result['state'].toString().isNotEmpty) {
                                      final matched = result['state'].toString();
                                      if (malaysianStates.contains(matched)) {
                                        selectedState = matched;
                                        stateError = null;
                                      }
                                    }
                                  });
                                }

                                if (sheetContext.mounted) {
                                  FocusScope.of(sheetContext).unfocus();
                                }
                                FocusManager.instance.primaryFocus?.unfocus();
                              },
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
                        const SizedBox(height: 6),
                        TextField(
                          controller: addressLineController,
                          maxLength: 65,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(65),
                          ],
                          onChanged: (_) {
                            setModalState(() {
                              if (addressLineError != null) {
                                final a = addressLineController.text.trim();
                                addressLineError = a.isEmpty ? 'Street address is required' : (a.length > 65 ? 'Address line cannot exceed 65 characters' : null);
                              }
                            });
                          },
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'e.g. No 12, Jalan SS 15/4, Subang Jaya',
                            hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            errorText: addressLineError,
                            errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Postcode & City Row
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Postcode',
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: postcodeController,
                                    keyboardType: TextInputType.number,
                                    maxLength: 5,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(5),
                                    ],
                                    onChanged: (_) {
                                      setModalState(() {
                                        if (postcodeError != null) {
                                          final p = postcodeController.text.trim();
                                          postcodeError = p.isEmpty ? 'Postcode is required' : (p.length != 5 ? 'Must be 5 digits' : null);
                                        }
                                      });
                                    },
                                    decoration: InputDecoration(
                                      counterText: '',
                                      hintText: '47500',
                                      hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      errorText: postcodeError,
                                      errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'City',
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                  ),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: cityController,
                                    maxLength: 20,
                                    inputFormatters: [
                                      LengthLimitingTextInputFormatter(20),
                                    ],
                                    onChanged: (_) {
                                      setModalState(() {
                                        if (cityError != null) {
                                          final c = cityController.text.trim();
                                          cityError = c.isEmpty ? 'City is required' : (c.length > 20 ? 'City cannot exceed 20 characters' : null);
                                        }
                                      });
                                    },
                                    decoration: InputDecoration(
                                      counterText: '',
                                      hintText: 'e.g. Subang Jaya',
                                      hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5),
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      errorText: cityError,
                                      errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // State Dropdown
                        const Text(
                          'State',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: selectedState,
                          isExpanded: true,
                          menuMaxHeight: 260,
                          hint: const Text('Select State', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5)),
                          items: malaysianStates.map((st) {
                            return DropdownMenuItem<String>(
                              value: st,
                              child: Text(st, style: const TextStyle(fontSize: 13.5, color: Color(0xFF0F172A))),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setModalState(() {
                              selectedState = val;
                              stateError = null;
                            });
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            errorText: stateError,
                            errorStyle: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
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
