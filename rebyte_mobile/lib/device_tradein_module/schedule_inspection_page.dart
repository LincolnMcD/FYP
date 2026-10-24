import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../account_management_module/models/address_model.dart';
import '../../account_management_module/services/address_service.dart';
import '../../account_management_module/services/session_service.dart';
import '../../account_management_module/home_page.dart';
import '../../product_purchase_module/select_address_page.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import 'models/device_model.dart';
import 'my_trade_in_requests_page.dart';
import 'services/trade_in_service.dart';
import 'services/trade_in_flow_session.dart';

class ScheduleInspectionPage extends StatefulWidget {
  final String tradeInRequestID;
  final String method; // 'On-Site Inspection' or 'Device Shipment'
  final DeviceModel? device;
  final String estimatedValue;
  final String? email;
  final String? name;
  final bool isLoggedIn;
  final bool fromMyTradeInRequests;
  final String? initialAddressID;
  final String? initialAddressLine;
  final String? initialDate;
  final String? initialSlot;

  const ScheduleInspectionPage({
    super.key,
    required this.tradeInRequestID,
    required this.method,
    this.device,
    this.estimatedValue = 'RM 1,050 - RM 1,520',
    this.email,
    this.name,
    this.isLoggedIn = true,
    this.fromMyTradeInRequests = false,
    this.initialAddressID,
    this.initialAddressLine,
    this.initialDate,
    this.initialSlot,
  });

  @override
  State<ScheduleInspectionPage> createState() => _ScheduleInspectionPageState();
}

class _ScheduleInspectionPageState extends State<ScheduleInspectionPage> {
  late DateTime _currentMonth;
  late DateTime _selectedDate;
  String? _selectedSlot;
  bool _isBooking = false;

  // Toast state
  String? _toastMessage;
  bool _isToastError = false;

  void _showToast(String message, [bool isError = false]) {
    if (!mounted) return;
    setState(() {
      _toastMessage = message;
      _isToastError = isError;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _toastMessage == message) {
        setState(() => _toastMessage = null);
      }
    });
  }

  // Address details
  AddressModel? _selectedAddress;
  String? _selectedAddressID;
  String _recipientName = 'Peter';
  String _addressLine = '12, Jalan SS 15/4, SS 15, 47500 Subang Jaya, Selangor, Malaysia';
  String _phoneNumber = '+60123456789';

  Future<String> _resolveEffectiveEmail() async {
    String email = widget.email?.trim() ?? '';
    if (email.isEmpty || email == 'customer@rebyte.com') {
      try {
        final session = await SessionService.getSession();
        final sEmail = session['email']?.trim();
        if (sEmail != null && sEmail.isNotEmpty) {
          email = sEmail;
        } else if (TradeInFlowSession.currentUserEmail != null &&
            TradeInFlowSession.currentUserEmail!.trim().isNotEmpty) {
          email = TradeInFlowSession.currentUserEmail!.trim();
        } else {
          final fbEmail = FirebaseAuth.instance.currentUser?.email?.trim();
          if (fbEmail != null && fbEmail.isNotEmpty) {
            email = fbEmail;
          }
        }
      } catch (_) {}
    }
    if (email.isEmpty || email == 'customer@rebyte.com') {
      email = 'lolincoln021@gmail.com';
    }
    return email;
  }

  // Real-time slot availability (slashed/disabled if all eligible staff have tasks)
  Set<String> _disabledSlots = {};
  bool _isLoadingSlots = false;

  // Fully booked dates for the current calendar month
  Set<String> _fullyBookedDates = {};
  bool _isLoadingMonth = false;

  bool get _isOnSiteInspection => widget.method == 'On-Site Inspection';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default to first available date (tomorrow / 24 hours advance)
    _selectedDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

    if (widget.initialDate != null && widget.initialDate!.isNotEmpty) {
      final parsed = DateTime.tryParse(widget.initialDate!);
      if (parsed != null) {
        _selectedDate = DateTime(parsed.year, parsed.month, parsed.day);
      }
    }
    _currentMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);

    if (widget.name != null && widget.name!.trim().isNotEmpty) {
      _recipientName = widget.name!.trim();
    }

    if (widget.initialAddressID != null && widget.initialAddressID!.isNotEmpty) {
      _selectedAddressID = widget.initialAddressID;
    }
    if (widget.initialAddressLine != null && widget.initialAddressLine!.isNotEmpty) {
      _addressLine = widget.initialAddressLine!;
    }

    _loadUserAddress();

    // Focus on initial or first available slot option
    if (widget.initialSlot != null && widget.initialSlot!.isNotEmpty) {
      _selectedSlot = widget.initialSlot;
    } else {
      final slots = _getAvailableSlots();
      if (slots.isNotEmpty) {
        _selectedSlot = slots.first;
      }
    }

    _fetchMonthAvailability();
  }

  Future<void> _fetchMonthAvailability() async {
    setState(() => _isLoadingMonth = true);
    final monthStr = DateFormat('yyyy-MM').format(_currentMonth);
    try {
      final res = await TradeInService.getMonthAvailability(
        method: widget.method,
        month: monthStr,
      );
      if (mounted) {
        setState(() {
          final disabled = List<String>.from(res['disabledDates'] ?? []);
          _fullyBookedDates = disabled.toSet();
          _isLoadingMonth = false;

          // If current selected date is fully booked, auto-select first available date (unless editing existing date)
          final curDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
          final firstAvail = res['firstAvailableDate'] as String?;
          final isEditingSameDate = widget.fromMyTradeInRequests && widget.initialDate == curDateStr;
          if (!isEditingSameDate && _fullyBookedDates.contains(curDateStr) && firstAvail != null && firstAvail.isNotEmpty) {
            final parsed = DateTime.tryParse(firstAvail);
            if (parsed != null) {
              _selectedDate = parsed;
              _selectedSlot = null;
            }
          }
        });
        _fetchSlotAvailability();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMonth = false);
        _fetchSlotAvailability();
      }
    }
  }

  Future<void> _fetchSlotAvailability() async {
    setState(() => _isLoadingSlots = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    try {
      final res = await TradeInService.getAvailableSlots(
        method: widget.method,
        date: dateStr,
      );
      if (mounted) {
        setState(() {
          final disabled = List<String>.from(res['disabledSlots'] ?? []);
          _disabledSlots = disabled.toSet();
          _isLoadingSlots = false;

          final allSlots = _getAvailableSlots();
          final available = allSlots.where((s) => !_disabledSlots.contains(s)).toList();

          // Focus on initial or first available slot option
          final isEditingSameDateAndSlot = widget.fromMyTradeInRequests &&
              dateStr == widget.initialDate &&
              _selectedSlot == widget.initialSlot;

          if (_selectedSlot == null || (!available.contains(_selectedSlot) && !isEditingSameDateAndSlot)) {
            _selectedSlot = available.isNotEmpty ? available.first : null;
          }

          if (available.isEmpty) {
            _showToast('No eligible staff available on this date. Please select another date.', true);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingSlots = false);
      }
    }
  }

  Future<void> _loadUserAddress() async {
    final effectiveEmail = await _resolveEffectiveEmail();

    String? targetAddressID = widget.initialAddressID ?? _selectedAddressID;
    String? targetAddressLine = widget.initialAddressLine;

    // If editing/from my trade in requests and targetAddressID is still null, fetch request details
    if ((targetAddressID == null || targetAddressID.isEmpty) &&
        widget.tradeInRequestID.isNotEmpty &&
        widget.fromMyTradeInRequests) {
      try {
        final reqDetails = await TradeInService.getTradeInRequestDetails(widget.tradeInRequestID);
        if (reqDetails != null) {
          if (reqDetails['addressID'] != null && reqDetails['addressID'].toString().isNotEmpty) {
            targetAddressID = reqDetails['addressID'].toString();
          }
          final loc = (reqDetails['appointmentLocation'] ?? reqDetails['inspectionAddress'] ?? reqDetails['address'])?.toString();
          if (loc != null && loc.isNotEmpty) {
            targetAddressLine = loc;
          }
        }
      } catch (_) {}
    }

    final list = await AddressService.getAddresses(effectiveEmail);
    if (!mounted) return;

    if (list.isNotEmpty) {
      setState(() {
        AddressModel? chosenAddr;

        // 1. Try matching by addressID from booking record
        if (targetAddressID != null && targetAddressID.isNotEmpty) {
          try {
            chosenAddr = list.firstWhere(
              (a) => a.addressID == targetAddressID || a.id == targetAddressID,
            );
          } catch (_) {}
        }

        // 2. Try matching by address line text from booking record
        if (chosenAddr == null && targetAddressLine != null && targetAddressLine.trim().isNotEmpty) {
          final targetLower = targetAddressLine.trim().toLowerCase();
          try {
            chosenAddr = list.firstWhere(
              (a) => a.fullAddress.trim().toLowerCase() == targetLower ||
                     a.fullAddress.toLowerCase().contains(targetLower) ||
                     targetLower.contains(a.fullAddress.toLowerCase()),
            );
          } catch (_) {}
        }

        // 3. If NOT editing an existing booking, fall back to default address
        if (chosenAddr == null && !widget.fromMyTradeInRequests && (targetAddressID == null || targetAddressID.isEmpty)) {
          try {
            chosenAddr = list.firstWhere((a) => a.isDefault, orElse: () => list.first);
          } catch (_) {}
        }

        if (chosenAddr != null) {
          _selectedAddress = chosenAddr;
          _selectedAddressID = chosenAddr.addressID.isNotEmpty ? chosenAddr.addressID : chosenAddr.id;
          _recipientName = chosenAddr.recipientName.isNotEmpty ? chosenAddr.recipientName : _recipientName;
          _phoneNumber = chosenAddr.phoneNumber.isNotEmpty ? chosenAddr.phoneNumber : _phoneNumber;
          _addressLine = chosenAddr.fullAddress;
        } else if (targetAddressLine != null && targetAddressLine.isNotEmpty) {
          _selectedAddressID = targetAddressID;
          _addressLine = targetAddressLine;
        } else {
          final defaultAddr = list.firstWhere((a) => a.isDefault, orElse: () => list.first);
          _selectedAddress = defaultAddr;
          _selectedAddressID = defaultAddr.addressID.isNotEmpty ? defaultAddr.addressID : defaultAddr.id;
          _recipientName = defaultAddr.recipientName.isNotEmpty ? defaultAddr.recipientName : _recipientName;
          _phoneNumber = defaultAddr.phoneNumber.isNotEmpty ? defaultAddr.phoneNumber : _phoneNumber;
          _addressLine = defaultAddr.fullAddress;
        }
      });
    } else if (targetAddressLine != null && targetAddressLine.isNotEmpty) {
      setState(() {
        _selectedAddressID = targetAddressID;
        _addressLine = targetAddressLine!;
      });
    }
  }

  Future<void> _changeAddress() async {
    final effectiveEmail = await _resolveEffectiveEmail();
    if (!mounted) return;
    final result = await Navigator.push<AddressModel>(
      context,
      MaterialPageRoute(
        builder: (context) => SelectAddressPage(
          email: effectiveEmail,
          currentlySelected: _selectedAddress,
        ),
      ),
    );


    if (result != null && mounted) {
      setState(() {
        _selectedAddress = result;
        _selectedAddressID = result.addressID.isNotEmpty ? result.addressID : result.id;
        _recipientName = result.recipientName;
        _phoneNumber = result.phoneNumber;
        _addressLine = result.fullAddress;
      });
    }
  }

  List<String> _getAvailableSlots() {
    if (_isOnSiteInspection) {
      return const [
        '09:30 AM',
        '11:00 AM',
        '01:00 PM',
        '01:30 PM',
        '02:30 PM',
        '03:00 PM',
      ];
    } else {
      return const [
        '09:30 AM',
        '10:00 AM',
        '10:30 AM',
        '11:00 AM',
        '11:30 AM',
        '01:00 PM',
        '01:30 PM',
        '02:00 PM',
        '02:30 PM',
        '03:00 PM',
        '03:30 PM',
        '04:00 PM',
      ];
    }
  }

  bool _isSlotDisabled(String slot) {
    return _disabledSlots.contains(slot);
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
    _fetchMonthAvailability();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
    _fetchMonthAvailability();
  }


  Future<void> _onContinueBooking() async {
    if (_selectedSlot == null) {
      _showToast('Please select an available time slot.', true);
      return;
    }

    setState(() => _isBooking = true);

    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final displayDate = DateFormat('MMM d, yyyy').format(_selectedDate);

    // Call backend API to persist appointment details and trigger task assignment
    final res = await TradeInService.bookAppointment(
      tradeInRequestID: widget.tradeInRequestID,
      method: widget.method,
      appointmentDate: formattedDate,
      appointmentTime: _selectedSlot!,
      addressID: _selectedAddressID,
      address: {
        'addressID': _selectedAddressID,
        'recipientName': _recipientName,
        'phoneNumber': _phoneNumber,
        'addressLine': _addressLine,
      },
    );

    if (!mounted) return;
    setState(() => _isBooking = false);

    if (res['success'] != true) {
      _showToast(
        res['message'] ?? 'No eligible staff available for this slot. Please choose another slot.',
        true,
      );
      return;
    }

    // Show Booking Confirmation Dialog matching ReByte style
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 40),
              ),
              const SizedBox(height: 20),
              const Text(
                'Booking Confirmed!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your ${widget.method.toLowerCase()} has been scheduled for $displayDate at $_selectedSlot.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.45),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 18, color: Color(0xFF0C5AD2)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _addressLine,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    final effectiveEmail = (widget.email != null && widget.email!.trim().isNotEmpty)
                        ? widget.email!.trim()
                        : (TradeInFlowSession.currentUserEmail ?? 'customer@rebyte.com');

                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MyTradeInRequestsPage(
                          email: effectiveEmail,
                          name: widget.name,
                          isLoggedIn: widget.isLoggedIn,
                        ),
                      ),
                      (route) => route.isFirst,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Back to Trade-In Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HomePage(
                        isLoggedIn: widget.isLoggedIn,
                        email: widget.email,
                        name: widget.name,
                      ),
                    ),
                    (route) => false,
                  );
                },
                child: const Text('Return to Home', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceTitle = widget.device?.model.isNotEmpty == true
        ? widget.device!.model
        : 'iPhone 13 Pro';
    final deviceSpecs = [
      if (widget.device?.storageCapacity.isNotEmpty == true) widget.device!.storageCapacity else '256GB',
      if (widget.device?.colour.isNotEmpty == true) widget.device!.colour else 'Graphite',
      'Unlocked',
    ].join(' • ');

    final slots = _getAvailableSlots();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: const ReByteAppBar(),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top back button row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Subtitle under back button
                        Text(
                          _isOnSiteInspection
                              ? 'Schedule a certified technician to inspect your device at your location.'
                              : 'Schedule a courier to collect your device at your location.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Card 1: Device Summary Card
                        _buildDeviceCard(deviceTitle, deviceSpecs),

                        const SizedBox(height: 14),

                        // Card 2: Address Card
                        _buildAddressCard(),

                        const SizedBox(height: 14),

                        // Card 3: Date & Time Card
                        _buildDateTimeCard(slots),

                        const SizedBox(height: 24),

                        // Continue Booking Button
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isBooking ? null : _onContinueBooking,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0C5AD2),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isBooking
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                                  )
                                : const Text(
                                    'Continue Booking',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 28),
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
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _isToastError ? const Color(0xFFE11D48) : const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isToastError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _toastMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _toastMessage = null),
                          child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: 2,
      ),
    );
  }

  Widget _buildDeviceCard(String title, String specs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Device image container
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/phones/iphone13.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.phone_iphone_rounded, color: Color(0xFF64748B), size: 36),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Specs and value
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  specs,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),

                // Trade-in Value Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_offer, size: 12, color: Color(0xFF0C5AD2)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Trade-In Value:\nEst. ${widget.estimatedValue.replaceAll(RegExp(r'^RM\s*'), 'RM')}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0C5AD2),
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
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
          borderRadius: BorderRadius.circular(18),
          onTap: _changeAddress,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isOnSiteInspection
                              ? Icons.location_on_outlined
                              : Icons.local_shipping_outlined,
                          color: const Color(0xFF0C5AD2),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isOnSiteInspection ? 'Inspection Address' : 'Collection Address',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0C5AD2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 12),

                if (_selectedAddress != null) ...[
                  Text(
                    _selectedAddress!.recipientName.isNotEmpty
                        ? _selectedAddress!.recipientName
                        : 'Recipient',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedAddress!.fullAddress,
                    textAlign: TextAlign.justify,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                  if (_selectedAddress!.phoneNumber.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _selectedAddress!.phoneNumber,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ] else ...[
                  Text(
                    _recipientName.isNotEmpty ? _recipientName : 'Recipient',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _addressLine,
                    textAlign: TextAlign.justify,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                  if (_phoneNumber.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _phoneNumber,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimeCard(List<String> slots) {
    final monthTitle = DateFormat('MMMM yyyy').format(_currentMonth);
    final selectedDayLabel = DateFormat('MMM d').format(_selectedDate);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, color: Color(0xFF64748B), size: 18),
              const SizedBox(width: 8),
              const Text(
                'Select Date & Time',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Notice banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF2563EB), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isOnSiteInspection
                        ? 'Inspections require a minimum 24-hour advance booking to assign a technician.'
                        : 'Collections require a minimum 24-hour advance booking to assign a courier.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1E3A8A),
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Calendar Navigation Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 24, color: Color(0xFF334155)),
                onPressed: _previousMonth,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    monthTitle,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (_isLoadingMonth) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0C5AD2)),
                    ),
                  ],
                ],
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 24, color: Color(0xFF334155)),
                onPressed: _nextMonth,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Weekdays header S M T W T F S
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const [
              _WeekdayText('S'),
              _WeekdayText('M'),
              _WeekdayText('T'),
              _WeekdayText('W'),
              _WeekdayText('T'),
              _WeekdayText('F'),
              _WeekdayText('S'),
            ],
          ),
          const SizedBox(height: 8),

          // Days Grid
          _buildMonthCalendarGrid(),

          const Divider(height: 32, color: Color(0xFFF1F5F9)),

          // Available Slots Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available Slots for $selectedDayLabel',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              if (_isLoadingSlots)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0C5AD2)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 3 slots per row grid (fits exactly 3 slots per row for collection & inspection)
          Column(
            children: [
              for (int i = 0; i < slots.length; i += 3)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(child: _buildSlotChip(slots[i])),
                      const SizedBox(width: 10),
                      if (i + 1 < slots.length)
                        Expanded(child: _buildSlotChip(slots[i + 1]))
                      else
                        const Expanded(child: SizedBox()),
                      const SizedBox(width: 10),
                      if (i + 2 < slots.length)
                        Expanded(child: _buildSlotChip(slots[i + 2]))
                      else
                        const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCalendarGrid() {
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    // weekday 1 (Mon) to 7 (Sun). If Sunday, weekday % 7 = 0
    final startingOffset = firstDayOfMonth.weekday % 7;

    final now = DateTime.now();
    final minBookDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

    final totalSlots = startingOffset + daysInMonth;
    final rowCount = (totalSlots / 7).ceil();

    return Column(
      children: List.generate(rowCount, (rowIdx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (colIdx) {
              final dayIndex = rowIdx * 7 + colIdx - startingOffset + 1;
              if (dayIndex < 1 || dayIndex > daysInMonth) {
                return const SizedBox(width: 36, height: 36);
              }

              final date = DateTime(_currentMonth.year, _currentMonth.month, dayIndex);
              final dateStr = DateFormat('yyyy-MM-dd').format(date);
              final isPastOrWithin24h = date.isBefore(minBookDate);
              final isFullyBooked = _fullyBookedDates.contains(dateStr);
              final isDisabled = isPastOrWithin24h || isFullyBooked;
              final isSelected = date.year == _selectedDate.year &&
                  date.month == _selectedDate.month &&
                  date.day == _selectedDate.day;

              return GestureDetector(
                onTap: () {
                  if (isPastOrWithin24h) {
                    _showToast('Please select a date at least 24 hours in advance.', true);
                  } else if (isFullyBooked) {
                    _showToast('No eligible staff available on this date. Please select another date.', true);
                  } else {
                    setState(() {
                      _selectedDate = date;
                      _selectedSlot = null;
                    });
                    _fetchSlotAvailability();
                  }
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? const Color(0xFF0C5AD2) : Colors.transparent,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$dayIndex',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      decoration: isFullyBooked && !isPastOrWithin24h ? TextDecoration.lineThrough : null,
                      decorationColor: const Color(0xFF94A3B8),
                      color: isSelected
                          ? Colors.white
                          : isDisabled
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF1E293B),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildSlotChip(String slot) {
    final isSelected = _selectedSlot == slot;
    final isDisabled = _isSlotDisabled(slot);

    return GestureDetector(
      onTap: () {
        if (isDisabled) {
          _showToast('No eligible staff available for this slot. Please choose another slot.', true);
        } else {
          setState(() => _selectedSlot = slot);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDisabled ? const Color(0xFFF8FAFC) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF0C5AD2)
                : isDisabled
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFFCBD5E1),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            slot,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isDisabled
                  ? const Color(0xFF94A3B8)
                  : isSelected
                      ? const Color(0xFF0C5AD2)
                      : const Color(0xFF1E293B),
              decoration: isDisabled ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekdayText extends StatelessWidget {
  final String label;
  const _WeekdayText(this.label);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }
}
