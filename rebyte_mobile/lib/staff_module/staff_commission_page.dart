import 'package:flutter/material.dart';

class StaffCommissionPage extends StatelessWidget {
  const StaffCommissionPage({super.key});

  final commissionHistory = const [
    { 'id': 'TRD-9821', 'date': 'Oct\\n24,\\n2023', 'device': 'iPhone\\n13 Pro\\nMax\\n(256GB)', 'earned': 'RM\\n150.00', 'rawEarned': 'RM 150.00' },
    { 'id': 'TRD-9818', 'date': 'Oct\\n23,\\n2023', 'device': 'Samsung\\nGalaxy\\nS22 Ultra', 'earned': 'RM\\n145.00', 'rawEarned': 'RM 145.00' },
    { 'id': 'TRD-8995', 'date': 'Oct\\n21,\\n2023', 'device': 'iPhone 12\\nPro Max', 'earned': 'RM\\n210.00', 'rawEarned': 'RM 210.00' },
    { 'id': 'TRD-8980', 'date': 'Oct\\n19,\\n2023', 'device': 'iPhone 12\\nPro Max', 'earned': 'RM\\n95.00', 'rawEarned': 'RM 95.00' },
    { 'id': 'TRD-8972', 'date': 'Oct\\n18,\\n2023', 'device': 'iPhone\\n12\\n(128GB)', 'earned': 'RM\\n80.00', 'rawEarned': 'RM 80.00' },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
         backgroundColor: Colors.white,
         elevation: 0,
         leading: IconButton(
           icon: const Icon(Icons.arrow_back, color: Color(0xFF0C5AD2)),
           onPressed: () => Navigator.pop(context),
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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  children: [
                    _buildDashboardCard(
                      title: 'TOTAL EARNED',
                      amount: 'RM 12,450',
                      iconData: Icons.account_balance_wallet,
                      iconColor: const Color(0xFF0C5AD2),
                      blobColor: const Color(0xFFF0F4FA),
                      subWidget: Row(
                        children: [
                          const Icon(Icons.trending_up, color: Color(0xFF22C55E), size: 14),
                          const SizedBox(width: 4),
                          const Text('+12% vs last year', style: TextStyle(color: Color(0xFF22C55E), fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDashboardCard(
                      title: 'THIS MONTH',
                      amount: 'RM 2,800',
                      iconData: Icons.calendar_month,
                      iconColor: const Color(0xFF0F766E),
                      blobColor: const Color(0xFFF0F4FA),
                      subWidget: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.grey.shade600, size: 14),
                          const SizedBox(width: 4),
                          Text('Projected: RM 3,200', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDashboardCard(
                      title: 'AVG. PER SUCCESSFUL TRADE-IN',
                      amount: 'RM 120',
                      iconData: Icons.bar_chart_rounded,
                      iconColor: const Color(0xFFB45309),
                      blobColor: const Color(0xFFFAF5ED),
                      subWidget: Text('Based on 24 trades this month', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              // Commission History Container
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Commission History',
                              style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                            GestureDetector(
                              onTap: () {},
                              child: Row(
                                children: [
                                  const Text('View All', style: TextStyle(color: Color(0xFF0C5AD2), fontSize: 13, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_forward_rounded, color: Color(0xFF0C5AD2), size: 16),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      
                      // Table Labels Segment
                      Container(
                        color: const Color(0xFFF3F6FF),
                        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                        child: Row(
                          children: [
                            const Expanded(flex: 2, child: Text('TASK ID', style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w900))),
                            const Expanded(flex: 2, child: Text('DATE', style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w900))),
                            const Expanded(flex: 3, child: Text('DEVICE', style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w900))),
                            const Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: Text('EARNED', style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w900)))),
                          ],
                        ),
                      ),
                      
                      // Table Data
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: commissionHistory.length,
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (context, index) {
                          final item = commissionHistory[index];
                          // Format texts properly handling explicit multiline mockups
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // TASK ID Box
                                Expanded(
                                  flex: 2, 
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE8F0FE),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        item['id']!.replaceFirst('-', '-\\n'), 
                                        style: const TextStyle(color: Color(0xFF0C5AD2), fontSize: 12, fontWeight: FontWeight.w900, height: 1.4),
                                      ),
                                    ),
                                  )
                                ),
                                
                                // Date
                                Expanded(
                                  flex: 2,
                                  child: Text(item['date']!, style: const TextStyle(color: Color(0xFF475569), fontSize: 12, height: 1.4, fontWeight: FontWeight.w500)),
                                ),
                                
                                // Device
                                Expanded(
                                  flex: 3,
                                  child: Text(item['device']!, style: const TextStyle(color: Color(0xFF475569), fontSize: 12, height: 1.4, fontWeight: FontWeight.w500)),
                                ),
                                
                                // Earned
                                Expanded(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text('RM', style: TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.w900, height: 1.4)),
                                        Text(item['rawEarned']!.replaceAll('RM ', ''), style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.w900, height: 1.4)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardCard({
    required String title,
    required String amount,
    required IconData iconData,
    required Color iconColor,
    required Color blobColor,
    required Widget subWidget,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: blobColor,
                  shape: BoxShape.circle,
                ),
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
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: iconColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(iconData, color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    amount,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  subWidget,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
