import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../account_management_module/models/address_model.dart';
import '../../account_management_module/services/address_service.dart';
import '../../account_management_module/home_page.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import 'models/device_model.dart';
import 'my_trade_in_requests_page.dart';
import 'services/trade_in_service.dart';

class ScheduleInspectionPage extends StatefulWidget {
  final String tradeInRequestID;
  final String method; // 'On-Site Inspection' or 'Device Shipment'
  final DeviceModel? device;
  final String estimatedValue;
  final String? email;
  final String? name;
  final bool isLoggedIn;
  final bool fromMyTradeInRequests;

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
  });

  @override
  State<ScheduleInspectionPage> createState() => _ScheduleInspectionPageState();
}

class _ScheduleInspectionPageState extends State<ScheduleInspectionPage> {
  late DateTime _currentMonth;
  late DateTime _selectedDate;
  String? _selectedSlot;
  bool _isBooking = false;

  // Address details
  String _recipientName = 'Peter';
  String _addressLine = '12, Jalan SS 15/4, SS 15, 47500 Subang Jaya, Selangor, Malaysia';
  String _phoneNumber = '+60123456789';
  List<AddressModel> _savedAddresses = [];

  bool get _isOnSiteInspection => widget.method == 'On-Site Inspection';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default to minimum 24 hours advance (e.g. tomorrow or +2 days)
    _selectedDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 2));
    _currentMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);

    if (widget.name != null && widget.name!.trim().isNotEmpty) {
      _recipientName = widget.name!.trim();
    }
    _loadUserAddress();

    // Default pre-selected slot
    final slots = _getAvailableSlots();
    if (slots.isNotEmpty) {
      _selectedSlot = slots.length > 1 ? slots[1] : slots.first;
    }
  }

  Future<void> _loadUserAddress() async {
    if (widget.email != null && widget.email!.isNotEmpty) {
      final list = await AddressService.getAddresses(widget.email!);
      if (mounted && list.isNotEmpty) {
        setState(() {
          _savedAddresses = list;
          final defaultAddr = list.firstWhere((a) => a.isDefault, orElse: () => list.first);
          _recipientName = defaultAddr.recipientName.isNotEmpty ? defaultAddr.recipientName : _recipientName;
          _phoneNumber = defaultAddr.phoneNumber.isNotEmpty ? defaultAddr.phoneNumber : _phoneNumber;
          _addressLine = '${defaultAddr.addressLine}, ${defaultAddr.postcode} ${defaultAddr.city}, ${defaultAddr.state}, Malaysia';
        });
      }
    }
  }

  /// Rules specified by User:
  /// - collection(delivery) half hour a slot
  /// - inspection 1 hour 30 min (1.5 hours) a slot
  /// - working hour is 9am start time, first slot start time need half hour later -> 9:30 AM
  /// - working hour is 5pm end time, end slot end time need half hour earlier -> 4:30 PM (16:30)
  List<String> _getAvailableSlots() {
    if (_isOnSiteInspection) {
      // 1 hr 30 min per slot, between 09:30 and 16:30:
      // 09:30 AM (ends 11:00 AM)
      // 11:00 AM (ends 12:30 PM)
      // 01:00 PM (ends 02:30 PM)
      // 01:30 PM (ends 03:00 PM)
      // 02:30 PM (ends 04:00 PM)
      // 03:00 PM (ends 04:30 PM)
      return const [
        '09:30 AM',
        '11:00 AM',
        '01:00 PM',
        '01:30 PM',
        '02:30 PM',
        '03:00 PM',
      ];
    } else {
      // Collection / Device Shipment: half hour (30 min) a slot, between 09:30 and 16:30
      // Excluding lunch hour (12:00 PM - 01:00 PM): 12 slots, perfectly fitting 4 rows of 3 slots
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
    // No mock slashed slots; all valid scheduled slots are open
    return false;
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  void _showEditAddressModal() {
    final nameCtrl = TextEditingController(text: _recipientName);
    final phoneCtrl = TextEditingController(text: _phoneNumber);
    final addrCtrl = TextEditingController(text: _addressLine);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isOnSiteInspection ? 'Edit Inspection Address' : 'Edit Collection Address',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_savedAddresses.isNotEmpty) ...[
                const Text('Choose from saved addresses:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                const SizedBox(height: 8),
                ...List.generate(_savedAddresses.length, (idx) {
                  final a = _savedAddresses[idx];
                  final formatted = '${a.addressLine}, ${a.postcode} ${a.city}, ${a.state}';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, color: Color(0xFF0C5AD2)),
                    title: Text(a.recipientName.isNotEmpty ? a.recipientName : 'Address ${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(formatted, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    onTap: () {
                      setState(() {
                        _recipientName = a.recipientName;
                        _phoneNumber = a.phoneNumber;
                        _addressLine = formatted;
                      });
                      Navigator.pop(ctx);
                    },
                  );
                }),
                const Divider(height: 24),
              ],
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Recipient Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addrCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Address Details', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isNotEmpty && addrCtrl.text.trim().isNotEmpty) {
                      setState(() {
                        _recipientName = nameCtrl.text.trim();
                        _phoneNumber = phoneCtrl.text.trim();
                        _addressLine = addrCtrl.text.trim();
                      });
                    }
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save Address', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onContinueBooking() async {
    if (_selectedSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an available time slot.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isBooking = true);

    final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final displayDate = DateFormat('MMM d, yyyy').format(_selectedDate);

    // Call backend API to persist appointment details
    await TradeInService.bookAppointment(
      tradeInRequestID: widget.tradeInRequestID,
      method: widget.method,
      appointmentDate: formattedDate,
      appointmentTime: _selectedSlot!,
      address: {
        'recipientName': _recipientName,
        'phoneNumber': _phoneNumber,
        'addressLine': _addressLine,
      },
    );

    if (!mounted) return;
    setState(() => _isBooking = false);

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
                    // Navigate to trade-in requests or home
                    if (widget.fromMyTradeInRequests) {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    } else {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MyTradeInRequestsPage(
                            email: widget.email ?? '',
                            name: widget.name,
                            isLoggedIn: widget.isLoggedIn,
                          ),
                        ),
                        (route) => route.isFirst,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('View Trade-In Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
        child: Column(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: Color(0xFF64748B), size: 20),
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
              GestureDetector(
                onTap: _showEditAddressModal,
                child: const Text(
                  'Edit',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0C5AD2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Inner Grey Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recipientName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _addressLine,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.phone_outlined, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(
                      _phoneNumber,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
              Text(
                monthTitle,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
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
          Text(
            'Available Slots for $selectedDayLabel',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
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
              final isPastOrWithin24h = date.isBefore(minBookDate);
              final isSelected = date.year == _selectedDate.year &&
                  date.month == _selectedDate.month &&
                  date.day == _selectedDate.day;

              return GestureDetector(
                onTap: isPastOrWithin24h
                    ? null
                    : () {
                        setState(() {
                          _selectedDate = date;
                          // If current slot is disabled on the newly selected day, reset selection
                          if (_selectedSlot != null && _isSlotDisabled(_selectedSlot!)) {
                            final valid = _getAvailableSlots().where((s) => !_isSlotDisabled(s)).toList();
                            _selectedSlot = valid.isNotEmpty ? valid.first : null;
                          }
                        });
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
                      color: isSelected
                          ? Colors.white
                          : isPastOrWithin24h
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
      onTap: isDisabled ? null : () => setState(() => _selectedSlot = slot),
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
