import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../account_management_module/home_page.dart';
import '../account_management_module/welcome_page.dart';
import '../account_management_module/services/session_service.dart';
import '../device_tradein_module/services/trade_in_flow_session.dart';
import '../decision_assistance_module/diagnostic_suite_page.dart';
import '../product_purchase_module/cart_page.dart';
import '../product_purchase_module/notification_page.dart';
import '../product_purchase_module/my_orders_page.dart';
import '../device_tradein_module/my_trade_in_requests_page.dart';
import '../rental_managment_module/my_rentals_page.dart';

class ReByteAppBar extends StatelessWidget implements PreferredSizeWidget {
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onNotificationPressed;
  final VoidCallback? onCartPressed;
  final int cartItemCount;
  final bool showNotificationDot;

  final bool isShopPage;

  const ReByteAppBar({
    super.key,
    this.scaffoldKey,
    this.onMenuPressed,
    this.onNotificationPressed,
    this.onCartPressed,
    this.cartItemCount = 0,
    this.showNotificationDot = true,
    this.isShopPage = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.black87),
        onPressed: () {
          if (onMenuPressed != null) {
            onMenuPressed!();
          } else if (scaffoldKey?.currentState != null) {
            scaffoldKey!.currentState!.openDrawer();
          } else {
            Scaffold.of(context).openDrawer();
          }
        },
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/rebyte_logo.png',
            height: 36,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF0C5AD2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text('R', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
              ),
            ),
          ),
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
        if (isShopPage)
          // Shopping cart icon ONLY on shop page
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined, color: Colors.black87),
            onPressed: () async {
              if (onCartPressed != null) {
                onCartPressed!();
              } else {
                final session = await SessionService.getSession();
                if (context.mounted) {
                  if (session.isEmpty) {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const WelcomePage()));
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CartPage(
                          isLoggedIn: true,
                          email: session['email'],
                          name: session['name'],
                        ),
                      ),
                    );
                  }
                }
              }
            },
          )
        else
          // Bell Notification icon on all other pages
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.black87),
                onPressed: () async {
                  if (onNotificationPressed != null) {
                    onNotificationPressed!();
                  } else {
                    final session = await SessionService.getSession();
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NotificationPage(
                            isLoggedIn: session.isNotEmpty,
                            email: session['email'],
                            name: session['name'],
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
              if (showNotificationDot)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF97316),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class ReByteDrawer extends StatefulWidget {
  final bool isLoggedIn;
  final String? name;
  final String? email;
  final int selectedIndex;
  final bool isMyOrdersSelected;
  final bool isRentalsSelected;
  final bool isTradeInRequestsSelected;
  final void Function(int index)? onSelectTab;

  const ReByteDrawer({
    super.key,
    this.isLoggedIn = false,
    this.name,
    this.email,
    this.selectedIndex = -1,
    this.isMyOrdersSelected = false,
    this.isRentalsSelected = false,
    this.isTradeInRequestsSelected = false,
    this.onSelectTab,
  });

  @override
  State<ReByteDrawer> createState() => _ReByteDrawerState();
}

class _ReByteDrawerState extends State<ReByteDrawer> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _navigateToTab(BuildContext context, int targetIndex) {
    Navigator.pop(context); // Close drawer
    // If navigating to another tab or to Trade-In landing page, clear flow session
    TradeInFlowSession.clear();
    if (widget.onSelectTab != null) {
      widget.onSelectTab!(targetIndex);
    } else {
      if (targetIndex != 0 && !widget.isLoggedIn) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const WelcomePage()));
        return;
      }
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => HomePage(
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
          ),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSelectedIndex = (widget.isMyOrdersSelected || widget.isRentalsSelected || widget.isTradeInRequestsSelected)
        ? -1
        : widget.selectedIndex;
    return Drawer(
      backgroundColor: const Color(0xFFF8F9FB),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              color: const Color(0xFFF8F9FB),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20),
                child: widget.isLoggedIn ? _buildLoggedInDrawerHeader(context) : _buildLoggedOutDrawerHeader(context),
              ),
            ),
            Divider(color: Colors.grey.shade200, height: 1),
            Expanded(
              child: Material(
                color: const Color(0xFFF8F9FB),
                child: ClipRect(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      // Triggers rebuild of items so they can recalculate visibility inside viewport
                      if (notification is ScrollUpdateNotification || notification is OverscrollNotification) {
                        setState(() {});
                      }
                      return false;
                    },
                    child: ListView(
                      controller: _scrollController,
                      padding: EdgeInsets.zero,
                      children: [
                      _buildDrawerItem(
                        Icons.home,
                        'Home',
                        isSelected: effectiveSelectedIndex == 0,
                        onTap: () => _navigateToTab(context, 0),
                      ),
                      _buildDrawerItem(
                        Icons.store_outlined,
                        'Shop',
                        isSelected: effectiveSelectedIndex == 1,
                        onTap: () => _navigateToTab(context, 1),
                      ),
                      _buildDrawerItem(
                        Icons.autorenew,
                        'Trade-In',
                        isSelected: effectiveSelectedIndex == 2,
                        onTap: () {
                          Navigator.pop(context);
                          _navigateToTab(context, 2);
                        },
                      ),
                      _buildDrawerItem(
                        Icons.calendar_month_outlined,
                        'Rentals',
                        isSelected: effectiveSelectedIndex == 3,
                        onTap: () => _navigateToTab(context, 3),
                      ),
                      _buildDrawerItem(
                        Icons.compare_arrows,
                        'Compare Devices',
                        onTap: () => _navigateToTab(context, 1),
                      ),
                      _buildDrawerItem(
                        Icons.phonelink_setup_rounded,
                        'Test My Device',
                        isSelected: effectiveSelectedIndex == 5,
                        onTap: () {
                          Navigator.pop(context);
                          if (!widget.isLoggedIn) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const WelcomePage()),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DiagnosticSuitePage(
                                isLoggedIn: widget.isLoggedIn,
                                email: widget.email,
                                name: widget.name,
                              ),
                            ),
                          );
                        },
                      ),
                      if (widget.isLoggedIn) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                          child: Text(
                            'ACTIVITY',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        _buildDrawerItem(
                          Icons.inventory_2_outlined,
                          'My Orders',
                          isSelected: widget.isMyOrdersSelected,
                          onTap: () {
                            Navigator.pop(context);
                            if (widget.isMyOrdersSelected) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MyOrdersPage(
                                  email: widget.email ?? 'customer@rebyte.com',
                                  name: widget.name,
                                ),
                              ),
                            );
                          },
                        ),
                        _buildDrawerItem(
                          Icons.calendar_month_outlined,
                          'My Rentals',
                          isSelected: widget.isRentalsSelected,
                          onTap: () {
                            Navigator.pop(context);
                            if (widget.isRentalsSelected) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MyRentalsPage(
                                  email: widget.email ?? 'customer@rebyte.com',
                                  name: widget.name,
                                ),
                              ),
                            );
                          },
                        ),
                        _buildDrawerItem(
                          Icons.autorenew_outlined,
                          'My Trade-In Requests',
                          isSelected: widget.isTradeInRequestsSelected,
                          onTap: () {
                            Navigator.pop(context);
                            if (widget.isTradeInRequestsSelected) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MyTradeInRequestsPage(
                                  email: widget.email ?? 'customer@rebyte.com',
                                  name: widget.name,
                                  isLoggedIn: widget.isLoggedIn,
                                ),
                              ),
                            );
                          },
                        ),
                        _buildDrawerItem(
                          Icons.shopping_bag_outlined,
                          'My Cart',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CartPage(
                                  isLoggedIn: widget.isLoggedIn,
                                  email: widget.email,
                                  name: widget.name,
                                ),
                              ),
                            );
                          },
                        ),
                        _buildDrawerItem(
                          Icons.notifications_none,
                          'Notifications',
                          badge: '3',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => NotificationPage(
                                  isLoggedIn: widget.isLoggedIn,
                                  email: widget.email,
                                  name: widget.name,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Material(
              elevation: 8,
              shadowColor: Colors.black26,
              color: const Color(0xFFF8F9FB),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(color: Colors.grey.shade200, height: 1),
                  _buildDrawerItem(Icons.help_outline, 'Help Desk'),
                  if (widget.isLoggedIn)
                    _buildDrawerItem(
                      Icons.logout,
                      'Logout',
                      iconColor: const Color(0xFF475569),
                      onTap: () {
                        _showLogoutDialog(context);
                      },
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedOutDrawerHeader(BuildContext context) {
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
            Navigator.pop(context);
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

  Widget _buildLoggedInDrawerHeader(BuildContext context) {
    return InkWell(
      onTap: () {
        _navigateToTab(context, 4);
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
                  widget.name ?? 'ReByte User',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.email ?? 'user@rebyte.com',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    IconData icon,
    String title, {
    bool isSelected = false,
    String? badge,
    Color? iconColor,
    void Function()? onTap,
  }) {
    return _DrawerItemTile(
      icon: icon,
      title: title,
      isSelected: isSelected,
      badge: badge,
      iconColor: iconColor,
      onTap: onTap,
    );
  }

  void _showLogoutDialog(BuildContext context) {
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
  }
}

class _DrawerItemTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool isSelected;
  final String? badge;
  final Color? iconColor;
  final VoidCallback? onTap;

  const _DrawerItemTile({
    required this.icon,
    required this.title,
    this.isSelected = false,
    this.badge,
    this.iconColor,
    this.onTap,
  });

  @override
  State<_DrawerItemTile> createState() => _DrawerItemTileState();
}

class _DrawerItemTileState extends State<_DrawerItemTile> {
  bool _isVisibleInViewport = true;

  @override
  void initState() {
    super.initState();
    if (widget.isSelected) {
      // Check visibility after the first layout pass
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    }
  }

  @override
  void didUpdateWidget(covariant _DrawerItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    }
  }

  void _checkVisibility() {
    if (!mounted || !widget.isSelected) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final viewport = RenderAbstractViewport.of(renderObject);
    if (viewport is! RenderBox) return;
    final viewportBox = viewport as RenderBox;
    if (!viewportBox.hasSize) return;

    // Compare the tile's actual position with the visible ListView viewport.
    // Reveal offsets are target scroll positions, not the tile's screen bounds.
    final itemTop = viewportBox
        .globalToLocal(renderObject.localToGlobal(Offset.zero))
        .dy;
    final itemBottom = itemTop + renderObject.size.height;
    final isVisible = itemBottom > 0 && itemTop < viewportBox.size.height;

    if (_isVisibleInViewport != isVisible) {
      setState(() {
        _isVisibleInViewport = isVisible;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    }
    final showHighlight = widget.isSelected && _isVisibleInViewport;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: ListTile(
        leading: Icon(
          widget.icon,
          color: showHighlight ? Colors.white : (widget.iconColor ?? const Color(0xFF475569)),
          size: 20,
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: showHighlight ? Colors.white : const Color(0xFF1E293B),
            fontSize: 13,
            fontWeight: showHighlight ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: widget.badge != null
            ? Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFC53030),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  widget.badge!,
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              )
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        tileColor: showHighlight ? const Color(0xFF0C5AD2) : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        onTap: widget.onTap ?? () {},
      ),
    );
  }
}
