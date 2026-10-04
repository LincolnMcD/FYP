import 'package:flutter/material.dart';
import 'welcome_page.dart';
import 'profile_page.dart';
import 'services/session_service.dart';

class HomePage extends StatefulWidget {
  final bool isLoggedIn;
  final String? email;
  final String? name;
  final String? toastMessage;
  const HomePage({super.key, this.isLoggedIn = false, this.email, this.name, this.toastMessage});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  late bool _isLoggedIn = widget.isLoggedIn;
  late String? _email = widget.email;
  late String? _name = widget.name;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String? _toastMessage;
  bool _isToastError = false;

  @override
  void initState() {
    super.initState();
    if (widget.toastMessage != null) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         _showTopToast(widget.toastMessage!, false);
       });
    }
  }

  void _refreshProfileSession() async {
    final session = await SessionService.getSession();
    if (session.isNotEmpty && mounted) {
       setState(() {
          _email = session['email'];
          _name = session['name'];
       });
    }
  }

  void _showTopToast(String message, bool isError) {
    setState(() {
      _toastMessage = message;
      _isToastError = isError;
    });
    
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _toastMessage = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8F9FB), // light grayish-blue background
      drawer: _buildDrawer(),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchBar(),
                    const SizedBox(height: 16),
                    _buildBanner(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Quick Actions'),
                    const SizedBox(height: 12),
                    _buildQuickActions(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Active Activity'),
                    const SizedBox(height: 12),
                    _buildActiveActivity(),
                    const SizedBox(height: 24),
                    _buildSectionHeaderWithViewAll('Recommended Certified Smartphones'),
                    const SizedBox(height: 12),
                    _buildRecommendedSmartphones(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Recently Viewed Smartphones'),
                    const SizedBox(height: 12),
                    _buildRecentlyViewedSmartphones(),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Why Choose ReByte?'),
                    const SizedBox(height: 12),
                    _buildWhyChooseUs(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              const Center(child: Text('Shop Page - Under Construction')),
              const Center(child: Text('Trade-In Page - Under Construction')),
              const Center(child: Text('Rentals - Under Construction')),
              ProfilePage(
                name: _name, 
                email: _email,
                onProfileUpdated: () => _refreshProfileSession(),
              ),
            ],
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
                      color: _isToastError ? Colors.red.shade600 : Colors.green.shade600,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        Icon(_isToastError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_toastMessage!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBarWithShadow(),
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
                child: _isLoggedIn ? _buildLoggedInDrawerHeader() : _buildLoggedOutDrawerHeader(),
              ),
            ),
            Divider(color: Colors.grey.shade200, height: 1),
            Expanded(
              child: ClipRect(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildDrawerItem(Icons.home, 'Home', isSelected: _selectedIndex == 0, onTap: () {
                    Navigator.pop(context);
                    setState(() => _selectedIndex = 0);
                  }),
                  _buildDrawerItem(Icons.store_outlined, 'Shop', isSelected: _selectedIndex == 1, onTap: () {
                    Navigator.pop(context);
                    setState(() => _selectedIndex = 1);
                  }),
                    _buildDrawerItem(Icons.autorenew, 'Trade-In', isSelected: _selectedIndex == 2, onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = 2);
                    }),
                    _buildDrawerItem(Icons.calendar_month_outlined, 'Rentals', isSelected: _selectedIndex == 3, onTap: () {
                      Navigator.pop(context);
                      setState(() => _selectedIndex = 3);
                    }),
                  _buildDrawerItem(Icons.compare_arrows, 'Compare Devices'),
                  if (_isLoggedIn) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                      child: Text('ACTIVITY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 0.5)),
                    ),
                    _buildDrawerItem(Icons.inventory_2_outlined, 'My Orders'),
                    _buildDrawerItem(Icons.shopping_bag_outlined, 'My Cart'),
                    _buildDrawerItem(Icons.notifications_none, 'Notifications', badge: '3'),
                  ],
                ],
              ),
            ),
          ),
          Divider(color: Colors.grey.shade200, height: 1),
            _buildDrawerItem(Icons.help_outline, 'Help Desk'),
            if (_isLoggedIn)
              _buildDrawerItem(Icons.logout, 'Logout', iconColor: const Color(0xFF475569), onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Confirm Logout'),
                    content: const Text('Are you sure you want to log out?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomePage(isLoggedIn: false, toastMessage: 'Logout successful')), (route) => false),
                        child: const Text('Logout', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedOutDrawerHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome to ReByte!',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 8),
        const Text(
          'Please log in to manage your account and orders.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context); // Close drawer
            Navigator.push(context, MaterialPageRoute(builder: (context) => const WelcomePage()));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0C5AD2),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
            minimumSize: const Size(double.infinity, 40),
          ),
          child: const Text('Log In / Register', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildLoggedInDrawerHeader() {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        setState(() => _selectedIndex = 4);
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
                  _name ?? 'ReByte User',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 2),
                Text(
                  _email ?? 'user@rebyte.com',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
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

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.black87),
        onPressed: () {
          _scaffoldKey.currentState?.openDrawer();
        },
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/rebyte_logo.png', height: 36),
          const SizedBox(width: 8),
          const Text(
            'ReByte',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
      actions: [
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none, color: Colors.black87),
              onPressed: () {},
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search for devices, brands, or models...',
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0C5AD2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Buy, Trade-In,\nRent\nSmartphones',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Upgrade your mobile experience sustainably. Get premium certified smartphones, turn old phones into cash, or rent the latest model when you need it.',
            style: TextStyle(
              color: Colors.white.withValues(alpha:0.9),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0C5AD2),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Get Started',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E293B),
      ),
    );
  }

  Widget _buildSectionHeaderWithViewAll(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ),
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('View All >', style: TextStyle(fontSize: 12, color: Color(0xFF0C5AD2))),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return LayoutBuilder(builder: (context, constraints) {
      double itemWidth = (constraints.maxWidth - 32) / 3;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _buildActionItem('Shop\nSmartphones', Icons.shopping_bag_outlined, const Color(0xFFE0E7FF), itemWidth),
          _buildActionItem('Trade-In\nPhone', Icons.autorenew, const Color(0xFFFFF7ED), itemWidth),
          _buildActionItem('Rent\nSmartphone', Icons.calendar_month_outlined, const Color(0xFFE0E7FF), itemWidth),
          _buildActionItem('Pay Rental', Icons.receipt_long_outlined, const Color(0xFFE0E7FF), itemWidth),
          _buildActionItem('Compare\nPhones', Icons.compare_arrows, const Color(0xFFF3E8FF), itemWidth),
        ],
      );
    });
  }

  Widget _buildActionItem(String text, IconData icon, Color bgColor, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.blue.shade700, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveActivity() {
    return Column(
      children: [
        _buildTradeInActivityCard(),
        const SizedBox(height: 12),
        _buildRentalActivityCard(),
      ],
    );
  }

  Widget _buildTradeInActivityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.autorenew, color: Color(0xFF0C5AD2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('iPhone 13', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const Text('Pro Trade-In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('Order #TRD-8321', style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.access_time, size: 12, color: Colors.orange),
                    SizedBox(width: 4),
                    Text('Inspecting', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTradeInTimeline(),
        ],
      ),
    );
  }

  Widget _buildTradeInTimeline() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildTimelineStep('Quote', true, false),
        _buildTimelineLine(true),
        _buildTimelineStep('Shipped', true, false),
        _buildTimelineLine(true),
        _buildTimelineStep('Inspecting', false, true),
        _buildTimelineLine(false),
        _buildTimelineStep('Payment', false, false),
      ],
    );
  }

  Widget _buildTimelineStep(String label, bool isCompleted, bool isCurrent) {
    return Column(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: isCompleted ? Colors.green : (isCurrent ? Colors.orange.shade100 : Colors.transparent),
            shape: BoxShape.circle,
            border: Border.all(
              color: isCompleted ? Colors.green : (isCurrent ? Colors.orange : Colors.grey.shade300),
              width: 1.5,
            ),
          ),
          child: isCompleted
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : (isCurrent
                  ? const Icon(Icons.circle, size: 8, color: Colors.orange)
                  : null),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isCompleted || isCurrent ? FontWeight.bold : FontWeight.normal,
            color: isCompleted || isCurrent ? Colors.black87 : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineLine(bool isCompleted) {
    return Expanded(
      child: Container(
        height: 2,
        color: isCompleted ? Colors.green : Colors.grey.shade200,
        margin: const EdgeInsets.only(bottom: 14),
      ),
    );
  }

  Widget _buildRentalActivityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.smartphone, color: Color(0xFF0C5AD2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Samsung Galaxy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const Text('S24, 512GB', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('Due: Nov 15, 2026', style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Active', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Time Remaining', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  SizedBox(height: 2),
                  Text('14 Days', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ],
              ),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      minimumSize: Size.zero,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    child: const Text('Extend', style: TextStyle(fontSize: 11, color: Colors.black87)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      minimumSize: Size.zero,
                      backgroundColor: const Color(0xFF0C5AD2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      elevation: 0,
                    ),
                    child: const Text('Return', style: TextStyle(fontSize: 11, color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendedSmartphones() {
    return Row(
      children: [
        Expanded(
          child: _buildPhoneCard(
            brand: 'Apple',
            model: 'iPhone 14, 128GB',
            price: 'RM599.00',
            tag: 'PERFECT',
            tagColor: const Color(0xFFE0E7FF),
            tagTextColor: const Color(0xFF0C5AD2),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildPhoneCard(
            brand: 'Samsung',
            model: 'Galaxy S23, 256GB',
            price: 'RM499.00',
            tag: 'EXCELLENT',
            tagColor: const Color(0xFFE0E7FF),
            tagTextColor: const Color(0xFF0C5AD2),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentlyViewedSmartphones() {
    return Row(
      children: [
        Expanded(
          child: _buildPhoneCard(
            brand: 'Samsung',
            model: 'Galaxy S22, 128GB',
            price: 'RM349.00',
            tag: null,
            tagColor: Colors.transparent,
            tagTextColor: Colors.transparent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildPhoneCard(
            brand: 'Apple',
            model: 'iPhone 12, 64GB',
            price: 'RM299.00',
            tag: null,
            tagColor: Colors.transparent,
            tagTextColor: Colors.transparent,
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneCard({
    required String brand,
    required String model,
    required String price,
    required String? tag,
    required Color tagColor,
    required Color tagTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tag != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: tagColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  color: tagTextColor,
                  fontSize: 7,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            )
          else
            const SizedBox(height: 14), // Placeholder for tag
          const SizedBox(height: 8),
          Center(
            child: Container(
              height: 80,
              width: double.infinity,
              color: Colors.grey.shade100, // Placeholder for image
              child: Icon(Icons.phone_iphone, size: 40, color: Colors.grey.shade400),
            ),
          ),
          const SizedBox(height: 12),
          Text(brand, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(model, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(price, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, size: 14, color: Color(0xFF0C5AD2)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWhyChooseUs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildFeatureItem(
            icon: Icons.verified_user_outlined,
            title: 'Verified Condition',
            desc: 'Every device is rigorously tested and certified.',
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          _buildFeatureItem(
            icon: Icons.price_check,
            title: 'Transparent Pricing',
            desc: 'No hidden fees, what you see is what you pay.',
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          _buildFeatureItem(
            icon: Icons.shield_outlined,
            title: 'Secure Payment',
            desc: 'Your transactions are fully protected and encrypted.',
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({required IconData icon, required String title, required String desc}) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE0E7FF),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF0C5AD2), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(desc, style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBarWithShadow() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) {
        if (index == 4 && !_isLoggedIn) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const WelcomePage()));
          return;
        }
        setState(() => _selectedIndex = index);
      },
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFF0C5AD2),
      unselectedItemColor: Colors.grey.shade500,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
      unselectedLabelStyle: const TextStyle(fontSize: 10),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: 'Shop'),
        BottomNavigationBarItem(icon: Icon(Icons.autorenew), label: 'Trade-In'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Rentals'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Account'),
      ],
    );
  }
}
