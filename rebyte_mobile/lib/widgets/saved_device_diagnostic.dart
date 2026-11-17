import 'package:flutter/material.dart';

class SavedDeviceDiagnostic extends StatelessWidget {
  final Map<String, dynamic> result;
  const SavedDeviceDiagnostic({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final score = (result['diagnosticScore'] as num?)?.round();
    final color = score == null ? const Color(0xFF64748B)
        : score >= 80 ? const Color(0xFF16A34A)
        : score >= 60 ? const Color(0xFFD97706) : const Color(0xFFE11D48);
    final label = score == null ? 'Score unavailable'
        : score >= 90 ? 'Excellent Condition' : score >= 75 ? 'Good Condition'
        : score >= 50 ? 'Fair Condition' : 'Needs Attention';
    const components = [
      ('Touchscreen', 'touchScreenMark', Icons.touch_app_rounded),
      ('Display', 'displayMark', Icons.phone_android_rounded),
      ('Camera', 'cameraMark', Icons.camera_alt_outlined),
      ('Microphone', 'microphoneMark', Icons.mic_none_outlined),
      ('Speaker', 'speakerMark', Icons.volume_up_outlined),
      ('Sensors', 'sensorMark', Icons.sensors_outlined),
      ('Connectivity', 'connectivityMark', Icons.wifi_outlined),
      ('GPS', 'gpsMark', Icons.location_on_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(children: [
            const Text('Overall Health', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F254B))),
            const SizedBox(height: 12),
            Text(score?.toString() ?? '—', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: Color(0xFF0F254B))),
            const Text('/ 100', style: TextStyle(color: Color(0xFF94A3B8))),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        const Text('Component Results', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F254B))),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
          child: Column(children: [
            for (final (index, component) in components.indexed)
              if (result[component.$2] is num)
                _buildComponentRow(
                  icon: component.$3, title: component.$1,
                  subtitle: 'Saved test result',
                  score: (result[component.$2] as num).round(),
                  isSkipped: false, showDivider: index < components.length - 1,
                ),
          ]),
        ),
      ],
    );
  }

  Widget _buildComponentRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required int score,
    required bool isSkipped,
    required bool showDivider,
  }) {
    Color badgeBg;
    Color badgeText;
    if (isSkipped) {
      badgeBg = const Color(0xFFFEF3C7);
      badgeText = const Color(0xFFD97706);
    } else if (score >= 80) {
      badgeBg = const Color(0xFFDCFCE7);
      badgeText = const Color(0xFF16A34A);
    } else if (score >= 50) {
      badgeBg = const Color(0xFFFEF3C7);
      badgeText = const Color(0xFFD97706);
    } else {
      badgeBg = const Color(0xFFFFE4E6);
      badgeText = const Color(0xFFE11D48);
    }

    final String badgeLabel = isSkipped ? 'Skipped' : '$score/100';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF0C5AD2), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isSkipped && score >= 80) ...[
                      Icon(Icons.check_circle_rounded, size: 13, color: badgeText),
                      const SizedBox(width: 4),
                    ] else if (!isSkipped && score < 50) ...[
                      Icon(Icons.cancel_rounded, size: 13, color: badgeText),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      badgeLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: badgeText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
      ],
    );
  }
}
