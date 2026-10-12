import 'package:flutter/material.dart';
import '../account_management_module/home_page.dart';
import '../account_management_module/welcome_page.dart';
import '../account_management_module/services/session_service.dart';
import '../device_tradein_module/trade_in_landing_page.dart';

class ReByteBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int)? onItemTapped;

  const ReByteBottomNavBar({
    super.key,
    this.selectedIndex = 0,
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
      // Home
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            isLoggedIn: isLoggedIn,
            email: email,
            name: name,
            initialIndex: 0,
          ),
        ),
        (route) => false,
      );
      return;
    }

    if (!isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const WelcomePage()),
      );
      return;
    }

    if (index == 2) {
      // Trade-In Page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TradeInLandingPage(
            isLoggedIn: isLoggedIn,
            email: email,
            name: name,
          ),
        ),
      );
      return;
    }

    // Tabs inside HomePage (1: Shop, 3: Rentals, 4: Account)
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => HomePage(
          isLoggedIn: isLoggedIn,
          email: email,
          name: name,
          initialIndex: index,
        ),
      ),
      (route) => false,
    );
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
      child: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (index) => _handleNavigation(context, index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF0C5AD2),
        unselectedItemColor: Colors.grey.shade500,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        elevation: 0,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: 'Shop'),
          BottomNavigationBarItem(icon: Icon(Icons.autorenew), label: 'Trade-In'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Rentals'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }
}
