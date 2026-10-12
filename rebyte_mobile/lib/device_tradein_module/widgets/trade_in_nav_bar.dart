import 'package:flutter/material.dart';
import '../../account_management_module/home_page.dart';
import '../../account_management_module/welcome_page.dart';
import '../../account_management_module/services/session_service.dart';

class TradeInBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int)? onItemTapped;

  const TradeInBottomNavBar({
    super.key,
    this.selectedIndex = 2, // Trade-In is index 2
    this.onItemTapped,
  });

  void _handleNavigation(BuildContext context, int index) async {
    if (onItemTapped != null) {
      onItemTapped!(index);
      return;
    }

    if (index == selectedIndex) return;

    final session = await SessionService.getSession();
    final bool isLoggedIn = session.isNotEmpty;
    final String? email = session['email'];
    final String? name = session['name'];

    if (!context.mounted) return;

    if (index == 0) {
      // Navigate to Home
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            isLoggedIn: isLoggedIn,
            email: email,
            name: name,
          ),
        ),
        (route) => false,
      );
      return;
    }

    if (index != 0 && !isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
      return;
    }

    if (index == 4) {
      // Account
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            isLoggedIn: isLoggedIn,
            email: email,
            name: name,
          ),
        ),
        (route) => false,
      );
    } else {
      // Navigate to HomePage with respective tab
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            isLoggedIn: isLoggedIn,
            email: email,
            name: name,
          ),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(context, index: 0, icon: Icons.home_rounded, label: 'Home'),
            _buildNavItem(context, index: 1, icon: Icons.shopping_bag_outlined, label: 'Shop'),
            _buildActivePillItem(context, index: 2, icon: Icons.swap_horiz_rounded, label: 'Trade-In'),
            _buildNavItem(context, index: 3, icon: Icons.calendar_month_outlined, label: 'Rentals'),
            _buildNavItem(context, index: 4, icon: Icons.person_outline_rounded, label: 'Account'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, {required int index, required IconData icon, required String label}) {
    final bool isSelected = index == selectedIndex;
    final Color color = isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF64748B);

    return InkWell(
      onTap: () => _handleNavigation(context, index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivePillItem(BuildContext context, {required int index, required IconData icon, required String label}) {
    final bool isSelected = index == selectedIndex;

    return InkWell(
      onTap: () => _handleNavigation(context, index),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFDBEAFE) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}
