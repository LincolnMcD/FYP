import 'package:flutter/material.dart';
import '../widgets/rebyte_app_bar.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import 'models/device_model.dart';
import 'schedule_inspection_page.dart';

class InspectionMethodPage extends StatefulWidget {
  final String tradeInRequestID;
  final DeviceModel? device;
  final String estimatedValue;
  final String? email;
  final String? name;
  final bool isLoggedIn;
  final bool fromMyTradeInRequests;

  const InspectionMethodPage({
    super.key,
    required this.tradeInRequestID,
    this.device,
    this.estimatedValue = 'RM 1,050 - RM 1,520',
    this.email,
    this.name,
    this.isLoggedIn = true,
    this.fromMyTradeInRequests = false,
  });

  @override
  State<InspectionMethodPage> createState() => _InspectionMethodPageState();
}

class _InspectionMethodPageState extends State<InspectionMethodPage> {
  // 'on_site' = On-Site Inspection (2 hours/slot)
  // 'shipment' = Device Shipment / Collection (30 mins/slot)
  String _selectedMethod = 'on_site';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: const ReByteAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            // Sub-header with back button
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
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Inspection Method',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Choose how you would like your device to be evaluated by our certified technicians.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Option 1: On-Site Inspection
                    _buildMethodCard(
                      id: 'on_site',
                      icon: Icons.business_center_outlined,
                      title: 'On-Site Inspection',
                      description:
                          'A certified ReByte technician will visit your location to inspect and appraise the device securely.',
                      badgeText: 'Fastest resolution',
                      badgeIcon: Icons.access_time_rounded,
                      badgeBg: const Color(0xFFEFF6FF),
                      badgeTextColor: const Color(0xFF2563EB),
                    ),

                    const SizedBox(height: 16),

                    // Option 2: Device Shipment / Collection
                    _buildMethodCard(
                      id: 'shipment',
                      icon: Icons.local_shipping_outlined,
                      title: 'Device Shipment',
                      description:
                          'We provide a prepaid shipping label. Securely package and mail your device to our facility.',
                      badgeText: 'Free shipping kit',
                      badgeIcon: Icons.inventory_2_outlined,
                      badgeBg: const Color(0xFFF1F5F9),
                      badgeTextColor: const Color(0xFF475569),
                    ),

                    const SizedBox(height: 36),

                    // Continue Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ScheduleInspectionPage(
                                tradeInRequestID: widget.tradeInRequestID,
                                method: _selectedMethod == 'on_site'
                                    ? 'On-Site Inspection'
                                    : 'Device Shipment',
                                device: widget.device,
                                estimatedValue: widget.estimatedValue,
                                email: widget.email,
                                name: widget.name,
                                isLoggedIn: widget.isLoggedIn,
                                fromMyTradeInRequests: widget.fromMyTradeInRequests,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0C5AD2),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
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

  Widget _buildMethodCard({
    required String id,
    required IconData icon,
    required String title,
    required String description,
    required String badgeText,
    required IconData badgeIcon,
    required Color badgeBg,
    required Color badgeTextColor,
  }) {
    final isSelected = _selectedMethod == id;

    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0C5AD2).withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color(0x05000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left icon in rounded square
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF0C5AD2), size: 24),
            ),
            const SizedBox(width: 16),

            // Content
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
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Pill Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(badgeIcon, size: 13, color: badgeTextColor),
                        const SizedBox(width: 4),
                        Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: badgeTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Radio button
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFCBD5E1),
                  width: isSelected ? 6.5 : 2.0,
                ),
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
