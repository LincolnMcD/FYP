import 'package:flutter/material.dart';
import 'home_page.dart';
import 'edit_profile_page.dart';
import 'services/session_service.dart';

class ProfilePage extends StatelessWidget {
  final String? name;
  final String? email;
  final VoidCallback? onProfileUpdated;

  const ProfilePage({super.key, this.name, this.email, this.onProfileUpdated});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildProfileHeader(context),
          const SizedBox(height: 16),
          _buildMenuSection(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // Light Blue Background at Top
          Container(
            height: 100,
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(top: 40, bottom: 24),
            child: Column(
              children: [
                // Avatar
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey.shade300,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Icon(Icons.person, size: 60, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 12),
                
                // Name
                Text(
                  name ?? 'ReByte User',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 24),
                
                // Edit Profile Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ElevatedButton.icon(
                    onPressed: () async {
                       if (email != null) {
                         await Navigator.push(context, MaterialPageRoute(builder: (context) => EditProfilePage(email: email!)));
                         if (context.mounted) {
                            onProfileUpdated?.call();
                         }
                       }
                    },
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0C5AD2),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildMenuItem(Icons.person_outline, 'Account Details'),
          _buildDivider(),
          _buildMenuItem(Icons.location_on_outlined, 'Delivery Address'),
          _buildDivider(),
          _buildMenuItem(Icons.credit_card_outlined, 'Payment Accounts'),
          _buildDivider(),
          _buildMenuItem(Icons.inventory_2_outlined, 'My Orders'),
          _buildDivider(),
          _buildMenuItem(Icons.autorenew_outlined, 'My Trade-In Request'),
          _buildDivider(),
          _buildMenuItem(Icons.calendar_today_outlined, 'My Rental'),
          _buildDivider(),
          _buildMenuItem(Icons.pending_actions_outlined, 'Pending Payment'),
          _buildDivider(),
          _buildMenuItem(Icons.history_outlined, 'Payment History'),
          _buildDivider(),
          _buildMenuItem(
            Icons.logout,
            'Logout',
            isLogout: true,
            onTap: () {
              showDialog(
                context: context,
                  builder: (context) => Dialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Confirm Logout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(Icons.close, size: 20, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('Are you sure you want to log out of your ReByte account?', style: TextStyle(fontSize: 13, color: Color(0xFF475569))),
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    side: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  child: const Text('CANCEL', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 13)),
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
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
                                  child: const Text('LOGOUT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, {bool isLogout = false, VoidCallback? onTap}) {
    final color = isLogout ? Colors.red.shade600 : const Color(0xFF0F172A);
    final iconColor = isLogout ? Colors.red.shade600 : const Color(0xFF0C5AD2);

    return InkWell(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: Colors.grey.shade200, indent: 20, endIndent: 20);
  }
}
