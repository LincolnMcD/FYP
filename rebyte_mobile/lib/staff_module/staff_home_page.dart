import 'package:flutter/material.dart';
import 'staff_profile_page.dart';
import '../account_management_module/services/session_service.dart';
import '../account_management_module/home_page.dart';
import 'staff_commission_page.dart';

class StaffHomePage extends StatefulWidget {
  final String? toastMessage;
  const StaffHomePage({super.key, this.toastMessage});

  @override
  State<StaffHomePage> createState() => _StaffHomePageState();
}

class _StaffHomePageState extends State<StaffHomePage> {
  int _selectedIndex = 0;
  String? _name;
  String? _email;
  String? _toastMessage;
  final bool _isToastError = false;
  
  @override
  void initState() {
    super.initState();
    _toastMessage = widget.toastMessage;
    _loadSession();
  }

  Future<void> _loadSession() async {
    final session = await SessionService.getSession();
    if (session.isNotEmpty) {
      if (mounted) {
        setState(() {
          _email = session['email'];
          _name = session['name'];
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildDrawer(),
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Color(0xFF0C5AD2)),
            onPressed: () { Scaffold.of(context).openDrawer(); },
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/rebyte_logo.png', height: 28),
            const SizedBox(width: 8),
            const Text(
              'ReByte',
              style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 24),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedIndex = 3;
                });
              },
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey.shade300,
                child: Icon(
                  Icons.person,
                  color: Colors.grey.shade600,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _selectedIndex == 3 ? StaffProfilePage(name: _name, email: _email, onLogout: _showLogoutDialog) : SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Header
              Padding(
                padding: const EdgeInsets.only(left: 20.0, top: 16.0, right: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${_name != null ? _name!.split(" ")[0] : "Sarah"}!',
                      style: const TextStyle(color: Color(0xFF0C5AD2), fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Here is your overview for today, October 24th.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // KPI Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    Expanded(child: _buildKpiCard('ACTIVE', '2', Icons.hourglass_top_rounded, const Color(0xFF3B82F6), const Color(0xFFEFF6FF))),
                    const SizedBox(width: 12),
                    Expanded(child: _buildKpiCard('PENDING', '5', Icons.more_horiz_rounded, const Color(0xFFF59E0B), const Color(0xFFFFFBEB))),
                    const SizedBox(width: 12),
                    Expanded(child: _buildKpiCard('DONE', '12', Icons.check_circle_outline_rounded, const Color(0xFF10B981), const Color(0xFFECFDF5))),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action Required
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0),
                child: Text('Action Required', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF003799), Color(0xFF0C5AD2)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: const Color(0xFF0C5AD2).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -30,
                        top: -30,
                        child: Container(
                          width: 120, height: 120,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.05)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                                  child: const Icon(Icons.phone_iphone_rounded, color: Color(0xFF0C5AD2), size: 28),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(color: const Color(0xFF2DD4BF), borderRadius: BorderRadius.circular(30)),
                                            child: const Text('IN PROGRESS', style: TextStyle(color: Color(0xFF134E4A), fontSize: 9, fontWeight: FontWeight.w900)),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('ID: RB-8832', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      const Text('iPhone 14 Pro Max - 256GB', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_outlined, color: Colors.white70, size: 14),
                                          const SizedBox(width: 4),
                                          const Text('Station 3', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {},
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF97316),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text('Continue Inspection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.arrow_forward_rounded, size: 18),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              // Today's Schedule
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Today's Schedule", style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 15)),
                    Text('View All', style: TextStyle(color: const Color(0xFF0C5AD2).withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 125,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _buildScheduleCard('10:00 AM', 'In 45 mins', 'UPCOMING', const Color(0xFFFEF3C7), const Color(0xFFD97706), 'iPhone 13 Pro Inspection', 'Michael C.'),
                    const SizedBox(width: 12),
                    _buildScheduleCard('11:30 AM', 'Walk-in', null, null, null, 'Samsung S22 Ultra Review', 'Sarah T.'),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              // QUICK ACTIONS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade200, width: 1.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('QUICK ACTIONS', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildQuickActionBtn(Icons.add_circle_outline_rounded, 'New\nInspect', true),
                          _buildQuickActionBtn(Icons.calendar_month_outlined, 'View\nSchedule', false),
                          _buildQuickActionBtn(Icons.event_busy_outlined, 'Request\nLeave', false),
                          _buildQuickActionBtn(Icons.support_agent_rounded, 'Inspection\nHelp', false),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              // Financial & Leave Metrics
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const StaffCommissionPage()));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade200, width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.payments_outlined, color: Color(0xFF10B981), size: 24),
                              const SizedBox(height: 12),
                              const Text('Est. Commission', style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              const Text('RM 1,250', style: TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: const LinearProgressIndicator(
                                  value: 0.75,
                                  backgroundColor: Color(0xFFF1F5F9),
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                                  minHeight: 6,
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade200, width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.beach_access_rounded, color: Color(0xFF0C5AD2), size: 24),
                            const SizedBox(height: 12),
                            const Text('Leave Balance', style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            const Text('3 Days', style: TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 12),
                            const Text('Resets Jan 1st', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
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
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        Icon(_isToastError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_toastMessage!, textAlign: TextAlign.justify, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          selectedItemColor: const Color(0xFF0C5AD2),
          unselectedItemColor: const Color(0xFF64748B),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded, size: 24), label: 'Dashboard'),
            const BottomNavigationBarItem(icon: Icon(Icons.calendar_today_rounded, size: 24), label: 'Schedule'),
            const BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined, size: 24), label: 'Tasks'),
            const BottomNavigationBarItem(icon: Icon(Icons.person_outline, size: 24), label: 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String count, IconData icon, Color primary, Color background) {
    return Container(
      padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12, right: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: background, shape: BoxShape.circle),
                child: Icon(icon, color: primary, size: 14),
              ),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(color: Color(0xFF475569), fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Text(count, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(String time, String subtitle, String? badge, Color? badgeBg, Color? badgeText, String title, String client) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), shape: BoxShape.circle),
                    child: const Icon(Icons.access_time_rounded, color: Color(0xFF64748B), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(time, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w900)),
                      Text(subtitle, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(20)),
                  child: Text(badge, style: TextStyle(color: badgeText, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const Spacer(),
          Text(title, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 12, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text('Client: $client', style: const TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionBtn(IconData icon, String label, bool isActive) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF0C5AD2) : const Color(0xFFEEF2FF),
            shape: BoxShape.circle,
            boxShadow: isActive ? [BoxShadow(color: const Color(0xFF0C5AD2).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))] : [],
          ),
          child: Icon(icon, color: isActive ? Colors.white : const Color(0xFF0C5AD2), size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF1E293B), fontSize: 10, fontWeight: FontWeight.bold, height: 1.2),
        ),
      ],
    );
  }
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFFF8F9FB),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              color: const Color(0xFFF8F9FB),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
                child: _buildLoggedInDrawerHeader(),
              ),
            ),
            Divider(color: Colors.grey.shade200, height: 1),
            Expanded(
              child: ClipRect(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildDrawerItem(Icons.grid_view_rounded, 'Dashboard', isSelected: _selectedIndex == 0, onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = 0);
                    }),
                    _buildDrawerItem(Icons.calendar_today_rounded, 'Schedule', isSelected: _selectedIndex == 1, onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = 1);
                    }),
                    _buildDrawerItem(Icons.assignment_outlined, 'Tasks', isSelected: _selectedIndex == 2, onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = 2);
                    }),
                    _buildDrawerItem(Icons.person_outline, 'Profile', isSelected: _selectedIndex == 3, onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = 3);
                    }),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                      child: Text('ACTIVITY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5)),
                    ),
                    _buildDrawerItem(Icons.inventory_2_outlined, 'My Trade-Ins'),
                    _buildDrawerItem(Icons.notifications_none, 'Notifications', badge: '3'),
                  ],
                ),
              ),
            ),
            Divider(color: Colors.grey.shade200, height: 1),
            _buildDrawerItem(Icons.help_outline, 'Help Desk'),
            _buildDrawerItem(Icons.logout, 'Logout', iconColor: const Color(0xFF475569), onTap: _showLogoutDialog),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedInDrawerHeader() {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        setState(() => _selectedIndex = 3);
      },
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha:0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.person, size: 32, color: Colors.grey.shade400),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name ?? 'ReByte Staff',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 2),
                Text(
                  _email ?? 'staff@rebyte.com',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Confirm Logout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      size: 20,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              const Text(
                'Are you sure you want to log out of your ReByte Staff account?',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                ),
              ),

              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      child: const Text(
                        'CANCEL',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await SessionService.clearSession();

                        if (context.mounted) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const HomePage(
                                isLoggedIn: false,
                                toastMessage: 'Logout successful',
                              ),
                            ),
                                (route) => false,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE11D48),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'LOGOUT',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildDrawerItem(IconData icon, String title, {bool isSelected = false, String? badge, Color? iconColor, void Function()? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? Colors.white : (iconColor ?? const Color(0xFF475569)), size: 20),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF1E293B),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: badge != null
            ? Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFC53030), // Red color for badge
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badge,
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              )
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        tileColor: isSelected ? const Color(0xFF0C5AD2) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        onTap: onTap ?? () {},
      ),
    );
  }
}
