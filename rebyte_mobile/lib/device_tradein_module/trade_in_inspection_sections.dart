import 'dart:io';

import 'package:flutter/material.dart';

import '../widgets/inspection_photo_gallery.dart';

class TradeInInspectionSections extends StatelessWidget {
  final Map<String, dynamic>? evaluation;
  final List<String> localPhotos;

  const TradeInInspectionSections({
    super.key,
    required this.evaluation,
    this.localPhotos = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildExternalScoreCard(context),
        const SizedBox(height: 16),
        _buildInspectionPhotosCard(localPhotos),
      ],
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return const Color(0xFFDC2626); // Red
      case 'major':
        return const Color(0xFFEA580C); // Orange-Red
      case 'minor':
        return const Color(0xFFD97706); // Amber / Orange
      case 'low':
        return const Color(0xFF0284C7); // Sky Blue
      case 'none':
      default:
        return const Color(0xFF10B981); // Emerald Green
    }
  }

  Widget _buildExternalScoreCard(BuildContext context) {
    // 3 Part Summary Mark: Screen, Back, Frame damage coverage % in 2 decimals
    final Map<String, dynamic>? parts = evaluation?['parts'] is Map<String, dynamic>
        ? evaluation!['parts'] as Map<String, dynamic>
        : null;

    final screenData = parts?['screen'] ?? evaluation?['screen'];
    final backData = parts?['back'] ?? evaluation?['back'];
    final frameData = parts?['frame'] ?? evaluation?['frame'];

    double getDmgCoverage(dynamic part) {
      if (part is Map) {
        final cov = part['dmgCoverage'] ?? part['coverage'];
        if (cov is num) return cov.toDouble();
        if (cov != null) return double.tryParse(cov.toString()) ?? 0.0;
      }
      return 0.0;
    }

    final double screenCov = getDmgCoverage(screenData);
    final double backCov = getDmgCoverage(backData);
    final double frameCov = getDmgCoverage(frameData);

    // Overall cosmetic health score: 100 - avg(coverage * 100)
    final double avgDmgPct = ((screenCov + backCov + frameCov) / 3.0) * 100.0;
    final int overallExternalScore = (100 - avgDmgPct).clamp(0, 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.tune_rounded, size: 18, color: Color(0xFF64748B)),
              SizedBox(width: 8),
              Text(
                'External Condition Score',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Overall External Mark /100
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$overallExternalScore',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '/100',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '3-Part Summary',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0C5AD2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3 Part Summary cards
          Row(
            children: [
              Expanded(
                child: _buildPartSummaryItem(
                  context,
                  partKey: 'screen',
                  title: 'Screen',
                  icon: Icons.phone_android_rounded,
                  dmgCoverage: screenCov,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPartSummaryItem(
                  context,
                  partKey: 'back',
                  title: 'Back',
                  icon: Icons.flip_to_back_rounded,
                  dmgCoverage: backCov,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPartSummaryItem(
                  context,
                  partKey: 'frame',
                  title: 'Frame',
                  icon: Icons.crop_portrait_rounded,
                  dmgCoverage: frameCov,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPartSummaryItem(BuildContext context, {
    required String partKey,
    required String title,
    required IconData icon,
    required double dmgCoverage,
  }) {
    final double dmgPct = (dmgCoverage * 100.0).clamp(0.0, 100.0);
    final String pctText = '${dmgPct.toStringAsFixed(2)}%';
    final bool hasDamage = dmgPct > 0.05;

    final Color statusColor = hasDamage ? (dmgPct > 5.0 ? const Color(0xFFDC2626) : const Color(0xFFD97706)) : const Color(0xFF10B981);
    final Color bgColor = hasDamage ? (dmgPct > 5.0 ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB)) : const Color(0xFFF0FDF4);

    return InkWell(
      onTap: () => _showPartDefectsDialog(context, partKey: partKey, partTitle: title),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: statusColor),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pctText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: statusColor,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  hasDamage ? 'Damage Cov.' : 'Intact',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: statusColor.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 8,
                  color: statusColor.withValues(alpha: 0.6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPartDefectsDialog(BuildContext context, {
    required String partKey,
    required String partTitle,
  }) {
    // Collect defect types for this specific part
    final List<Map<String, dynamic>> defectConfig;
    if (partKey == 'screen') {
      defectConfig = [
        {'key': 'screenCrack', 'title': 'Crack', 'icon': Icons.bolt_rounded},
        {'key': 'screenDiscolouration', 'title': 'Discolouration', 'icon': Icons.palette_outlined},
        {'key': 'screenScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
      ];
    } else if (partKey == 'back') {
      defectConfig = [
        {'key': 'backCrack', 'title': 'Crack', 'icon': Icons.bolt_rounded},
        {'key': 'backScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
      ];
    } else {
      // frame
      defectConfig = [
        {'key': 'frameScratch', 'title': 'Scratch', 'icon': Icons.show_chart_rounded},
        {'key': 'frameDent', 'title': 'Dent', 'icon': Icons.radio_button_checked_rounded},
      ];
    }

    // Extract real data for each defect type from classes or root
    final Map<String, dynamic>? classes = evaluation?['classes'] is Map<String, dynamic>
        ? evaluation!['classes'] as Map<String, dynamic>
        : null;

    final List<Map<String, dynamic>> pages = defectConfig.map((cfg) {
      final key = cfg['key'] as String;
      final dynamic raw = classes?[key] ?? evaluation?[key];

      int count = 0;
      double? area;
      double? coverage;
      String severity = 'None';

      if (raw is Map) {
        if (raw['count'] is num) count = (raw['count'] as num).toInt();
        if (raw['area'] is num) area = (raw['area'] as num).toDouble();
        if (raw['coverage'] is num) coverage = (raw['coverage'] as num).toDouble();
        if (raw['severity'] != null && raw['severity'].toString().isNotEmpty) {
          severity = raw['severity'].toString();
        }
      }

      final bool isCrack = (cfg['title'] == 'Crack') || key.toLowerCase().contains('crack');

      return {
        'title': '$partTitle ${cfg['title']}',
        'defectType': cfg['title'] as String,
        'icon': cfg['icon'] as IconData,
        'isCrack': isCrack,
        'count': count,
        'area': area,
        'coverage': coverage,
        'severity': count > 0 ? severity : 'None',
      };
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) {
        final PageController pageController = PageController();
        int activePage = 0;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 520, maxWidth: 420),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dialog Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.analytics_outlined,
                              color: Color(0xFF0C5AD2),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$partTitle Defect Breakdown',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Swipe left / right to view each defect',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                GestureDetector(
                                  onTap: () => _showSeverityRankingDialog(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFBFDBFE)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.help_outline_rounded, color: Color(0xFF0C5AD2), size: 13),
                                        SizedBox(width: 4),
                                        Text(
                                          'Severity Ranking',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0C5AD2),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                            onPressed: () => Navigator.of(ctx).pop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),

                    // Page Indicator Dots
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(pages.length, (i) {
                          final isCurrent = i == activePage;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 6,
                            width: isCurrent ? 22 : 6,
                            decoration: BoxDecoration(
                              color: isCurrent ? const Color(0xFF0C5AD2) : const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),

                    // Swipeable PageView with defect details
                    Flexible(
                      child: SizedBox(
                        height: 380,
                        child: PageView.builder(
                          controller: pageController,
                          itemCount: pages.length,
                          onPageChanged: (i) {
                            setDialogState(() {
                              activePage = i;
                            });
                          },
                          itemBuilder: (context, idx) {
                            final page = pages[idx];
                            final int count = page['count'] as int;
                            final double? area = page['area'] as double?;
                            final double? coverage = page['coverage'] as double?;
                            final String severity = page['severity'] as String;
                            final bool hasDefect = count > 0;

                            final Color statusColor = hasDefect
                                ? _getSeverityColor(severity)
                                : const Color(0xFF10B981);

                            return SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Defect Category Badge & Icon
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: (page['isCrack'] == true)
                                          ? CustomPaint(
                                              size: const Size(28, 28),
                                              painter: _CrackIconPainter(color: statusColor),
                                            )
                                          : Icon(
                                              page['icon'] as IconData,
                                              size: 28,
                                              color: statusColor,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    page['title'] as String,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      hasDefect ? '$count Detected' : 'No Defects Detected',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),

                                  // 4 Detail Grid Blocks: Count, Area, Severity, Coverage
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Count',
                                          value: '$count',
                                          icon: Icons.tag_rounded,
                                          valueColor: statusColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Severity',
                                          value: severity,
                                          icon: Icons.shield_outlined,
                                          valueColor: statusColor,
                                          onHelpTap: () => _showSeverityRankingDialog(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Damage Area',
                                          value: area != null ? '${area.toStringAsFixed(2)} cm²' : '0.00 cm²',
                                          icon: Icons.aspect_ratio_rounded,
                                          valueColor: const Color(0xFF1E293B),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildDefectMetricCard(
                                          label: 'Coverage',
                                          value: coverage != null
                                              ? '${(coverage * 100).toStringAsFixed(2)}%'
                                              : '0.00%',
                                          icon: Icons.pie_chart_outline_rounded,
                                          valueColor: const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  // Bottom helper status text
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          hasDefect ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded,
                                          size: 16,
                                          color: statusColor,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            hasDefect
                                                ? 'Detected during AI surface assessment. Severity level evaluated as $severity.'
                                                : 'Zero $partTitle ${page['defectType']} defects found during evaluation.',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF64748B),
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Swipe Navigation controls
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: activePage > 0
                                ? () {
                                    pageController.previousPage(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.chevron_left_rounded, size: 20),
                            label: const Text('Previous', style: TextStyle(fontSize: 12.5)),
                          ),
                          Text(
                            '${activePage + 1} of ${pages.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: activePage < pages.length - 1
                                ? () {
                                    pageController.nextPage(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                            icon: const Text('Next', style: TextStyle(fontSize: 12.5)),
                            label: const Icon(Icons.chevron_right_rounded, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDefectMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color valueColor,
    VoidCallback? onHelpTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF64748B)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              if (onHelpTap != null)
                GestureDetector(
                  onTap: onHelpTap,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.help_outline_rounded,
                      size: 13,
                      color: Color(0xFF0C5AD2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showSeverityRankingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final rankings = [
          {
            'level': 'Critical',
            'color': const Color(0xFFDC2626),
            'bgColor': const Color(0xFFFEF2F2),
            'icon': Icons.dangerous_rounded,
            'desc': 'Deep cracks, extensive shattered areas, or damage that impairs device function or touch response.',
          },
          {
            'level': 'Major',
            'color': const Color(0xFFEA580C),
            'bgColor': const Color(0xFFFFF7ED),
            'icon': Icons.warning_rounded,
            'desc': 'Noticeable cracks, deep scratches, or distinct discolouration patches clearly visible at arm’s length.',
          },
          {
            'level': 'Minor',
            'color': const Color(0xFFD97706),
            'bgColor': const Color(0xFFFFFBEB),
            'icon': Icons.error_outline_rounded,
            'desc': 'Light surface scratches, hairline marks, or slight cosmetic wear that does not affect functionality.',
          },
          {
            'level': 'Low',
            'color': const Color(0xFF0284C7),
            'bgColor': const Color(0xFFF0F9FF),
            'icon': Icons.info_outline_rounded,
            'desc': 'Micro-scratches or faint signs of handling visible only under direct angled light inspection.',
          },
          {
            'level': 'None',
            'color': const Color(0xFF10B981),
            'bgColor': const Color(0xFFF0FDF4),
            'icon': Icons.check_circle_outline_rounded,
            'desc': 'Pristine surface with zero detected cosmetic blemishes or structural anomalies.',
          },
        ];

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.help_outline_rounded,
                          color: Color(0xFF0C5AD2),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Severity Ranking Guide',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Defect severity classifications explained',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                        onPressed: () => Navigator.of(ctx).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // Ranking list
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: rankings.map((r) {
                      final Color col = r['color'] as Color;
                      final Color bg = r['bgColor'] as Color;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: col.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(r['icon'] as IconData, size: 20, color: col),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r['level'] as String,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: col,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    r['desc'] as String,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF475569),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Close Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C5AD2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInspectionPhotosCard(List<String> localPhotos) {
    // Extract real images from evaluation['images'] subcollection / list
    final List<Map<String, dynamic>> evalImages = [];
    if (evaluation?['images'] is List) {
      for (final img in evaluation!['images']) {
        if (img is Map) {
          evalImages.add(Map<String, dynamic>.from(img));
        }
      }
    }

    // Determine items to display: prefer remote inspection images, fallback to localPhotos
    final bool hasEvalImages = evalImages.isNotEmpty;
    final int itemCount = hasEvalImages ? evalImages.length : localPhotos.length;

    final photos = List.generate(itemCount, (index) {
      String? url;
      String? filePath;
      String caption = 'Photo ${index + 1}';

      if (hasEvalImages) {
        final imgObj = evalImages[index];
        url = imgObj['imageUrl']?.toString() ?? imgObj['originalImageUrl']?.toString();
        final view = imgObj['imageView']?.toString();
        if (view != null && view.isNotEmpty) {
          caption = view.replaceAll('_', ' ').toUpperCase();
        }
      } else {
        filePath = localPhotos[index];
      }

      return (url: url, filePath: filePath, caption: caption);
    });
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Inspection Photos',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              if (itemCount > 0)
                Text(
                  '$itemCount photo${itemCount > 1 ? 's' : ''} (tap to enlarge)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (itemCount == 0)
            Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Center(
                child: Text(
                  'No inspection photos available',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            )
          else
            // Horizontal scrollable list showing initial 2 photos in view
            LayoutBuilder(
              builder: (context, constraints) {
                // Showing 2 initial items in view with gap of 12
                final double itemWidth = (constraints.maxWidth - 12) / 2;
                return SizedBox(
                  height: 130,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: itemCount,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final photo = photos[index];
                      return SizedBox(
                        width: itemWidth,
                        child: GestureDetector(
                          onTap: () {
                            showDialog<void>(
                              context: context,
                              builder: (_) => InspectionPhotoGallery(
                                photos: photos,
                                initialIndex: index,
                              ),
                            );
                          },
                          child: _buildPhotoThumbCard(
                            imageUrl: photo.url,
                            filePath: photo.filePath,
                            caption: photo.caption,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoThumbCard({
    String? imageUrl,
    String? filePath,
    required String caption,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Center(
                child: Icon(Icons.broken_image_rounded, color: Color(0xFF94A3B8)),
              ),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            )
          else if (filePath != null && filePath.isNotEmpty && File(filePath).existsSync())
            Image.file(
              File(filePath),
              fit: BoxFit.cover,
            )
          else
            Container(
              color: const Color(0xFFE2E8F0),
              child: const Center(
                child: Icon(Icons.smartphone_rounded, size: 36, color: Color(0xFF94A3B8)),
              ),
            ),

          // Caption overlay banner
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              color: Colors.black.withValues(alpha: 0.55),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.zoom_in, color: Colors.white, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// Custom painter rendering a multi-branched surface glass crack pattern
class _CrackIconPainter extends CustomPainter {
  final Color color;

  const _CrackIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final double w = size.width;
    final double h = size.height;

    // Main jagged fracture spine down the center
    final mainPath = Path();
    mainPath.moveTo(w * 0.28, h * 0.14);
    mainPath.lineTo(w * 0.40, h * 0.16);
    mainPath.lineTo(w * 0.48, h * 0.28);
    mainPath.lineTo(w * 0.42, h * 0.36);
    mainPath.lineTo(w * 0.46, h * 0.48);
    mainPath.lineTo(w * 0.38, h * 0.58);
    mainPath.lineTo(w * 0.44, h * 0.68);
    mainPath.lineTo(w * 0.40, h * 0.74);
    mainPath.lineTo(w * 0.50, h * 0.82);
    mainPath.lineTo(w * 0.64, h * 0.94);
    canvas.drawPath(mainPath, paint);

    // Left branch 1 (top left fissure)
    final bLeft1 = Path();
    bLeft1.moveTo(w * 0.38, h * 0.16);
    bLeft1.lineTo(w * 0.32, h * 0.26);
    bLeft1.lineTo(w * 0.18, h * 0.32);
    canvas.drawPath(bLeft1, paint);

    // Left branch 2 (mid left horizontal fork)
    final bLeft2 = Path();
    bLeft2.moveTo(w * 0.46, h * 0.48);
    bLeft2.lineTo(w * 0.34, h * 0.46);
    bLeft2.lineTo(w * 0.24, h * 0.40);
    canvas.drawPath(bLeft2, paint);

    // Left branch 3 (bottom left fork)
    final bLeft3 = Path();
    bLeft3.moveTo(w * 0.40, h * 0.74);
    bLeft3.lineTo(w * 0.30, h * 0.78);
    bLeft3.lineTo(w * 0.34, h * 0.88);
    canvas.drawPath(bLeft3, paint);

    // Right branch 1 (top right sharp shoot)
    final bRight1 = Path();
    bRight1.moveTo(w * 0.48, h * 0.28);
    bRight1.lineTo(w * 0.64, h * 0.20);
    canvas.drawPath(bRight1, paint);

    // Right branch 2 (upper-mid right meandering crack)
    final bRight2 = Path();
    bRight2.moveTo(w * 0.42, h * 0.36);
    bRight2.lineTo(w * 0.56, h * 0.32);
    bRight2.lineTo(w * 0.74, h * 0.34);
    bRight2.lineTo(w * 0.76, h * 0.44);
    bRight2.lineTo(w * 0.66, h * 0.52);
    bRight2.lineTo(w * 0.64, h * 0.60);
    canvas.drawPath(bRight2, paint);

    // Right branch 3 (bottom right fork)
    final bRight3 = Path();
    bRight3.moveTo(w * 0.64, h * 0.60);
    bRight3.lineTo(w * 0.58, h * 0.68);
    canvas.drawPath(bRight3, paint);

    final bRight4 = Path();
    bRight4.moveTo(w * 0.64, h * 0.60);
    bRight4.lineTo(w * 0.70, h * 0.70);
    canvas.drawPath(bRight4, paint);
  }

  @override
  bool shouldRepaint(covariant _CrackIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
