import 'package:flutter/material.dart';

class CompareDevicesComingSoonPage extends StatelessWidget {
  final VoidCallback onBack;

  const CompareDevicesComingSoonPage({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(color: Color(0xFFE0E7FF), shape: BoxShape.circle),
                child: const Icon(Icons.compare_arrows_rounded, size: 38, color: Color(0xFF0C4AA3)),
              ),
              const SizedBox(height: 20),
              const Text(
                'Compare Devices',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Device comparison is coming soon. ReByte will let you compare smartphone features side by side here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
