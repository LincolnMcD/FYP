import 'package:flutter/material.dart';
import 'home_page.dart';
import 'edit_profile_page.dart';
import 'manage_address_page.dart';
import 'manage_payment_method_page.dart';
import 'services/session_service.dart';
import '../device_tradein_module/services/trade_in_flow_session.dart';
import '../product_purchase_module/order_details_page.dart';
import '../product_purchase_module/models/cart_item_model.dart';

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
          _buildMenuItem(
            Icons.location_on_outlined,
            'Delivery Address',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ManageAddressPage(email: email ?? 'default_user'),
                ),
              );
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            Icons.credit_card_outlined,
            'Payment Accounts',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ManagePaymentMethodPage(email: email ?? 'default_user'),
                ),
              );
            },
          ),
          _buildDivider(),
          _buildMenuItem(
            Icons.inventory_2_outlined,
            'My Orders',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OrderDetailsPage(
                    orderNumber: '#RB-9921',
                    amountPaid: 1648.00,
                    email: email ?? 'customer@rebyte.com',
                    name: name ?? 'Peter',
                    paidAt: DateTime(2026, 10, 24, 14, 23),
                    items: [
                      CartItemModel(
                        productID: 'sample_iphone14_pm',
                        description: 'iPhone 14 Pro Max 512GB - Good Condition',
                        sellingPrice: 799.00,
                        imageUrl: 'https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg',
                        brand: 'Apple',
                        model: 'iPhone 14 Pro Max',
                        storage: '512GB',
                        color: 'Phantom Black',
                        condition: 'Good',
                      ),
                      CartItemModel(
                        productID: 'sample_s23_ultra',
                        description: 'Samsung Galaxy S23 Ultra 512GB - Good Condition',
                        sellingPrice: 849.00,
                        imageUrl: 'https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg',
                        brand: 'Samsung',
                        model: 'Samsung Galaxy S23 Ultra',
                        storage: '512GB',
                        color: 'Phantom Black',
                        condition: 'Good',
                      ),
                    ],
                    paymentTitle: '**** **** **** 4242',
                  ),
                ),
              );
            },
          ),
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
                                    TradeInFlowSession.clear();
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
    final color = isLogout ? const Color(0xFFE11D48) : const Color(0xFF0F172A);
    final iconColor = isLogout ? const Color(0xFFE11D48) : const Color(0xFF0C5AD2);

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
