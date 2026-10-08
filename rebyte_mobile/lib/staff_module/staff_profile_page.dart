import 'package:flutter/material.dart';
import 'staff_edit_profile_page.dart';

class StaffProfilePage extends StatelessWidget {
  final String? name;
  final String? email;
  final VoidCallback onLogout;
  final VoidCallback? onProfileUpdated;

  const StaffProfilePage({
    super.key,
    required this.name,
    required this.email,
    required this.onLogout,
    this.onProfileUpdated,
  });

  Widget _buildListTile(IconData icon, String title, {Color? color, VoidCallback? onTap}) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          leading: Icon(icon, color: color ?? const Color(0xFF0C5AD2), size: 28),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color ?? const Color(0xFF0F172A),
            ),
          ),
          trailing: color == null ? const Icon(Icons.chevron_right, color: Colors.grey) : null,
          onTap: onTap ?? () {},
        ),
        if (title != 'Logout') Divider(color: Colors.grey.shade100, height: 1, indent: 24, endIndent: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = name ?? 'Staff Member';

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header section
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Top Banner Background
              Container(
                height: 140,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFE0E7FF), Color(0xFFEEF2FF)], // Soft blue gradients
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              // Overlapping Avatar
              Positioned(
                bottom: -50,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey.shade300,
                    child: Icon(Icons.person, size: 60, color: Colors.grey.shade500),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 60),

          // Profile Text
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            email ?? '',
            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 20),

          const SizedBox(height: 24),

          // Edit Profile Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: email == null ? null : () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => StaffEditProfilePage(email: email!)));
                  onProfileUpdated?.call();
                },
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5AD2),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Action List
          Container(
            color: Colors.white,
            child: Column(
              children: [
                _buildListTile(Icons.manage_accounts_outlined, 'Account Details'),
                _buildListTile(Icons.calendar_month_outlined, 'My Schedule'),
                _buildListTile(Icons.assignment_outlined, 'My Tasks'),
                _buildListTile(Icons.history, 'Guidance Library'),
                const SizedBox(height: 8),
                _buildListTile(
                  Icons.logout,
                  'Logout',
                  color: const Color(0xFFE11D48),
                  onTap: onLogout,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
