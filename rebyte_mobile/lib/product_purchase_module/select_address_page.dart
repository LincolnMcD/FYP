import 'package:flutter/material.dart';
import '../../account_management_module/models/address_model.dart';
import '../../account_management_module/services/address_service.dart';
import '../../account_management_module/widgets/add_address_dialog.dart';

class SelectAddressPage extends StatefulWidget {
  final String email;
  final AddressModel? currentlySelected;

  const SelectAddressPage({
    super.key,
    required this.email,
    this.currentlySelected,
  });

  @override
  State<SelectAddressPage> createState() => _SelectAddressPageState();
}

class _SelectAddressPageState extends State<SelectAddressPage> {
  List<AddressModel> _addresses = [];
  bool _isLoading = true;
  String? _selectedAddressId;

  @override
  void initState() {
    super.initState();
    _selectedAddressId = widget.currentlySelected?.addressID;
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    setState(() => _isLoading = true);
    final list = await AddressService.getAddresses(widget.email);
    if (mounted) {
      setState(() {
        _addresses = list;
        _isLoading = false;
        if (_selectedAddressId == null && _addresses.isNotEmpty) {
          final def = _addresses.firstWhere((a) => a.isDefault, orElse: () => _addresses.first);
          _selectedAddressId = def.addressID;
        }
      });
    }
  }

  void _selectAddress(AddressModel address) {
    setState(() {
      _selectedAddressId = address.addressID;
    });
    Navigator.pop(context, address);
  }

  Future<void> _navigateToAddNewAddress() async {
    // Show add address form bottom sheet directly instead of navigating to manage page
    final added = await AddAddressDialog.show(
      context: context,
      email: widget.email,
      isFirstAddress: _addresses.isEmpty,
    );
    if (added != null && mounted) {
      await _loadAddresses();
      // Match the newly added address from the refreshed list by addressID or phone/addressLine
      final newlyAdded = _addresses.firstWhere(
        (a) =>
            (added.addressID.isNotEmpty && a.addressID == added.addressID) ||
            (a.addressLine == added.addressLine && a.postcode == added.postcode),
        orElse: () => _addresses.isNotEmpty ? _addresses.first : added,
      );
      // Immediately select the new address and return it to the checkout page
      _selectAddress(newlyAdded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/rebyte_logo.png', height: 32),
            const SizedBox(width: 8),
            const Text(
              'ReByte',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Address',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F254B),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 20),

                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40.0),
                      child: CircularProgressIndicator(color: Color(0xFF0C5AD2)),
                    ),
                  )
                else if (_addresses.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: const Text(
                      'No addresses found. Please add a new delivery address below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                  )
                else
                  ..._addresses.map((addr) => _buildAddressItem(addr)),

                const SizedBox(height: 16),

                // Add New Address Button (dashed / outlined styled as design)
                InkWell(
                  onTap: _navigateToAddNewAddress,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFCBD5E1),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.add_location_alt_outlined, size: 20, color: Color(0xFF334155)),
                        SizedBox(width: 8),
                        Text(
                          'Add New Address',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressItem(AddressModel addr) {
    final isSelected = _selectedAddressId == addr.addressID;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
          width: isSelected ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectAddress(addr),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Radio indicator
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF94A3B8),
                      width: isSelected ? 6.5 : 2.0,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Address info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            addr.recipientName.isNotEmpty ? addr.recipientName : 'Address',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (addr.isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0C5AD2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.check, size: 10, color: Colors.white),
                                  SizedBox(width: 3),
                                  Text(
                                    'Default',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        addr.fullAddress,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                          height: 1.4,
                        ),
                      ),
                      if (addr.phoneNumber.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined, size: 14, color: Color(0xFF64748B)),
                            const SizedBox(width: 4),
                            Text(
                              addr.phoneNumber,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
