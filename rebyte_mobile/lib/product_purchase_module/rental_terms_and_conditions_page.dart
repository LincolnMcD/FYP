import 'package:flutter/material.dart';

class RentalTermsAndConditionsPage extends StatelessWidget {
  const RentalTermsAndConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/rebyte_logo.png',
              height: 32,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF0C5AD2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text('R', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'ReByte',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Badge & Title
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'RENTAL AGREEMENT',
                  style: TextStyle(
                    color: Color(0xFF0C5AD2),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Rental Terms & Conditions',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F254B),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Please review the terms and conditions governing the rental, usage, and return of equipment through the ReByte platform.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),

              _buildSectionCard(
                number: '1',
                title: 'Equipment Ownership & Title',
                content:
                    'All rented devices and accessories remain the exclusive property of ReByte or its authorized suppliers at all times. Renting a device does not confer any title, ownership, or equity in the equipment to the customer. Renter shall not sub-lease, assign, mortgage, pledge, or part with possession of the device.',
              ),
              const SizedBox(height: 16),

              _buildSectionCard(
                number: '2',
                title: 'Rental Period & Monthly Payments',
                content:
                    'The rental duration begins on the date of successful delivery or receipt of the device and continues for the agreed-upon duration. The first month rental fee together with the refundable security deposit is due upon checkout. Subsequent monthly fees will be charged on each recurrent cycle.',
              ),
              const SizedBox(height: 16),

              _buildSectionCard(
                number: '3',
                title: 'Security Deposit & Refund Policy',
                content:
                    'The refundable security deposit is held as security for the full and faithful performance of renter obligations. Upon expiration or authorized termination of the rental agreement, and following diagnostic inspection of the returned device, the deposit will be refunded in full within 5-7 business days, minus any deductions for outstanding fees or unauthorized damage.',
              ),
              const SizedBox(height: 16),

              _buildSectionCard(
                number: '4',
                title: 'Equipment Liability & Proper Care',
                content:
                    'The renter is responsible for maintaining the device in good working condition, ordinary wear and tear excepted. Renter agrees not to modify, jailbreak, root, or tamper with the operating system or hardware components of the device.',
              ),
              const SizedBox(height: 16),

              _buildSectionCard(
                number: '5',
                title: 'Loss, Theft & Liquid Damage',
                content:
                    'In the event of total loss, theft, severe physical breakage, or non-repairable liquid damage, the renter is liable for the replacement value of the device as assessed by ReByte, up to the full market value of the hardware at the inception of the rental.',
              ),
              const SizedBox(height: 16),

              _buildSectionCard(
                number: '6',
                title: 'Device Return Policy & Remote Security',
                content:
                    'Upon completion of the rental term, renter agrees to safely package and return the device with all supplied accessories. Renter must remove all personal accounts (such as Apple ID, Google Account, and passcodes) before returning. ReByte reserves the right to remotely restrict access to equipment that is overdue or subject to payment default until accounts are settled.',
              ),
              const SizedBox(height: 24),

              // Bottom Confirmation Note
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, color: Color(0xFF10B981), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'By checking the agreement box on checkout, you acknowledge that you have read, understood, and agreed to these terms.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String number,
    required String title,
    required String content,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF0C5AD2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            textAlign: TextAlign.justify,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF475569),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
