import 'dart:async';
import 'package:flutter/material.dart';
import '../../staff_module/staff_home_page.dart';
import '../../account_management_module/services/session_service.dart';
import '../../account_management_module/welcome_page.dart';

class StaffAppBar extends StatelessWidget implements PreferredSizeWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onProfilePressed;

  const StaffAppBar({
    super.key,
    this.scaffoldKey,
    this.onMenuPressed,
    this.onProfilePressed,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFF0C5AD2)),
          onPressed: () {
            if (onMenuPressed != null) {
              onMenuPressed!();
            } else if (scaffoldKey?.currentState != null) {
              scaffoldKey!.currentState!.openDrawer();
            } else {
              Scaffold.of(ctx).openDrawer();
            }
          },
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/rebyte_logo.png', height: 28),
          const SizedBox(width: 8),
          const Text(
            'ReByte',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: GestureDetector(
            onTap: () {
              if (onProfilePressed != null) {
                onProfilePressed!();
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StaffHomePage(initialIndex: 3),
                  ),
                );
              }
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
    );
  }
}

class StaffDrawer extends StatefulWidget {
  final int selectedIndex;

  const StaffDrawer({
    super.key,
    this.selectedIndex = 2,
  });

  @override
  State<StaffDrawer> createState() => _StaffDrawerState();
}

class _StaffDrawerState extends State<StaffDrawer> {
  String? _name;
  String? _email;
  String? _position;

  @override
  void initState() {
    super.initState();
    _loadStaffInfo();
  }

  Future<void> _loadStaffInfo() async {
    final session = await SessionService.getSession();
    if (mounted) {
      setState(() {
        _name = session['name'] ?? session['fullName'] ?? 'ReByte Staff';
        _email = session['email'] ?? 'staff@rebyte.com';
        _position = session['position'] ?? session['role'] ?? 'Inspector';
      });
    }
  }

  void _navigateToIndex(int index) {
    Navigator.pop(context); // Close drawer
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => StaffHomePage(initialIndex: index),
      ),
      (route) => false,
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out of staff portal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () async {
              Navigator.pop(ctx);
              await SessionService.clearSession();
              if (mounted && context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomePage()),
                  (route) => false,
                );
              }
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Staff User Header
            Container(
              color: const Color(0xFFF8F9FB),
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
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
                          color: Colors.black.withValues(alpha: 0.05),
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _email ?? 'staff@rebyte.com',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        if (_position != null && _position!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            _position == 'Both' ? 'Inspector & Collector' : _position!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0C5AD2),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.grey.shade200, height: 1),

            // Navigation Links
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerItem(
                    Icons.grid_view_rounded,
                    'Dashboard',
                    isSelected: widget.selectedIndex == 0,
                    onTap: () => _navigateToIndex(0),
                  ),
                  _buildDrawerItem(
                    Icons.calendar_today_rounded,
                    'Schedule',
                    isSelected: widget.selectedIndex == 1,
                    onTap: () => _navigateToIndex(1),
                  ),
                  _buildDrawerItem(
                    Icons.assignment_outlined,
                    'Tasks',
                    isSelected: widget.selectedIndex == 2,
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
                  _buildDrawerItem(
                    Icons.person_outline,
                    'Profile',
                    isSelected: widget.selectedIndex == 3,
                    onTap: () => _navigateToIndex(3),
                  ),
                ],
              ),
            ),
            Divider(color: Colors.grey.shade200, height: 1),
            _buildDrawerItem(
              Icons.logout,
              'Logout',
              iconColor: const Color(0xFFEF4444),
              onTap: _showLogoutDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
    IconData icon,
    String title, {
    bool isSelected = false,
    Color? iconColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? (isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF64748B)),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF0F172A),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 14,
        ),
      ),
      selected: isSelected,
      selectedTileColor: const Color(0xFFEFF6FF),
      onTap: onTap,
    );
  }
}

class StaffBottomNavBar extends StatelessWidget {
  final int currentIndex;

  const StaffBottomNavBar({
    super.key,
    this.currentIndex = 2,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) {
        if (index == currentIndex) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => StaffHomePage(initialIndex: index),
          ),
          (route) => false,
        );
      },
      selectedItemColor: const Color(0xFF0C5AD2),
      unselectedItemColor: const Color(0xFF64748B),
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded, size: 24), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today_rounded, size: 24), label: 'Schedule'),
        BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined, size: 24), label: 'Tasks'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline, size: 24), label: 'Profile'),
      ],
    );
  }
}

class StaffToast {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(BuildContext context, String message, {bool isError = false}) {
    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + kToolbarHeight + 8,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    _currentEntry = entry;

    _dismissTimer = Timer(const Duration(milliseconds: 3200), () {
      if (_currentEntry == entry) {
        entry.remove();
        _currentEntry = null;
      }
    });
  }
}

/// In-memory cache for retaining inspection uploads across page navigation
class StaffInspectionSession {
  static String? currentTaskId;
  static final Map<String, String> savedImagePaths = {};
  static final Map<String, String> savedImageNames = {};
  static String? savedOwnershipPhotoPath;
  static String? savedOwnershipPhotoName;
  static bool isOwnershipVerified = false;

  static void ensureTask(String? taskId) {
    if (taskId != null && taskId.isNotEmpty && currentTaskId != taskId) {
      clear();
      currentTaskId = taskId;
    }
  }

  static void clear() {
    currentTaskId = null;
    savedImagePaths.clear();
    savedImageNames.clear();
    savedOwnershipPhotoPath = null;
    savedOwnershipPhotoName = null;
    isOwnershipVerified = false;
  }
}

