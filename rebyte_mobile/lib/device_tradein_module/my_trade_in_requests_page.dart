import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../account_management_module/home_page.dart';
import '../widgets/rebyte_app_bar.dart';
import 'assessment_result_page.dart';
import 'improve_assessment_page.dart';
import 'models/device_model.dart';
import 'preliminary_quotation_page.dart';
import 'services/trade_in_service.dart';
import 'trade_in_request_created_page.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';

class MyTradeInRequestsPage extends StatefulWidget {
  final String email;
  final String? name;
  final bool isLoggedIn;

  const MyTradeInRequestsPage({
    super.key,
    required this.email,
    this.name,
    this.isLoggedIn = true,
  });

  @override
  State<MyTradeInRequestsPage> createState() => _MyTradeInRequestsPageState();
}

class _MyTradeInRequestsPageState extends State<MyTradeInRequestsPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _allRequests = [];
  String _activeStatusFilter = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    final list = await TradeInService.fetchUserTradeInRequests(widget.email);

    if (mounted) {
      setState(() {
        _allRequests = list;
        _isLoading = false;
      });
    }
  }

  bool _isActiveRequest(Map<String, dynamic> req) {
    if (_isCompletedRequest(req) || _isCancelledRequest(req)) {
      return false;
    }
    return true;
  }

  bool _isCompletedRequest(Map<String, dynamic> req) {
    final status = (req['requestStatus'] ?? '').toString().toLowerCase().trim();
    return status == 'completed' ||
        status.contains('complet') ||
        status == 'accepted' ||
        status.contains('accept');
  }

  bool _isCancelledRequest(Map<String, dynamic> req) {
    final status = (req['requestStatus'] ?? '').toString().toLowerCase().trim();
    return status == 'cancelled' ||
        status == 'canceled' ||
        status == 'rejected' ||
        status == 'declined';
  }

  String _formatSubmittedDate(dynamic dateVal) {
    if (dateVal == null) return 'Oct 26, 2023';
    try {
      if (dateVal is DateTime) {
        return DateFormat('MMM d, yyyy').format(dateVal);
      }
      if (dateVal is Map && dateVal['_seconds'] != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(
            (dateVal['_seconds'] as int) * 1000);
        return DateFormat('MMM d, yyyy').format(dt);
      }
      final str = dateVal.toString();
      final dt = DateTime.tryParse(str);
      if (dt != null) {
        return DateFormat('MMM d, yyyy').format(dt);
      }
    } catch (_) {}
    return 'Oct 26, 2023';
  }

  String _formatEstimatedValue(dynamic estValueVal) {
    final fmt = NumberFormat('#,##0.00');

    double? minD;
    double? maxD;

    if (estValueVal is Map) {
      final min = estValueVal['min'] ?? estValueVal['minEstimatedValue'];
      final max = estValueVal['max'] ?? estValueVal['maxEstimatedValue'];
      if (min != null) minD = (min is num) ? min.toDouble() : double.tryParse(min.toString());
      if (max != null) maxD = (max is num) ? max.toDouble() : double.tryParse(max.toString());
    } else if (estValueVal is List && estValueVal.length >= 2) {
      minD = (estValueVal[0] is num) ? estValueVal[0].toDouble() : double.tryParse(estValueVal[0].toString());
      maxD = (estValueVal[1] is num) ? estValueVal[1].toDouble() : double.tryParse(estValueVal[1].toString());
    } else if (estValueVal != null) {
      final str = estValueVal.toString();
      final matches = RegExp(r'[\d,]+(?:\.\d+)?').allMatches(str).map((m) {
        return double.tryParse(m.group(0)!.replaceAll(',', ''));
      }).whereType<double>().toList();

      if (matches.length >= 2) {
        minD = matches[0];
        maxD = matches[1];
      } else if (matches.length == 1) {
        minD = matches[0];
        maxD = matches[0];
      }
    }

    minD ??= 2340.50;
    maxD ??= 2355.30;

    return 'RM ${fmt.format(minD)} - RM ${fmt.format(maxD)}';
  }

  Map<String, dynamic> _getStatusConfig(String rawStatus) {
    final s = rawStatus.toLowerCase().trim();
    if (s.contains('accept')) {
      return {
        'label': 'Accepted',
        'bg': const Color(0xFFECFDF5),
        'color': const Color(0xFF10B981),
        'icon': Icons.check_circle_outline_rounded,
      };
    } else if (s.contains('quote') || s == 'quoted') {
      return {
        'label': 'Quoted',
        'bg': const Color(0xFFF3E8FF),
        'color': const Color(0xFF7E22CE),
        'icon': Icons.local_offer_outlined,
      };
    } else if (s.contains('evaluat')) {
      return {
        'label': 'Evaluated',
        'bg': const Color(0xFFEFF6FF),
        'color': const Color(0xFF2563EB),
        'icon': Icons.fact_check_outlined,
      };
    } else if (s.contains('submit') || s.contains('transit')) {
      return {
        'label': 'Submitted',
        'bg': const Color(0xFFFEF3C7),
        'color': const Color(0xFFD97706),
        'icon': Icons.local_shipping_rounded,
      };
    } else if (s.contains('reject') || s.contains('declin')) {
      return {
        'label': 'Declined',
        'bg': const Color(0xFFFEE2E2),
        'color': const Color(0xFFDC2626),
        'icon': Icons.cancel_outlined,
      };
    } else if (s.contains('cancel')) {
      return {
        'label': 'Cancelled',
        'bg': const Color(0xFFF1F5F9),
        'color': const Color(0xFF64748B),
        'icon': Icons.close_rounded,
      };
    } else {
      return {
        'label': 'Submitted',
        'bg': const Color(0xFFFEF3C7),
        'color': const Color(0xFFD97706),
        'icon': Icons.local_shipping_rounded,
      };
    }
  }

  DeviceModel _buildDeviceFromReq(Map<String, dynamic> req) {
    final dev = req['device'] is Map<String, dynamic>
        ? req['device'] as Map<String, dynamic>
        : null;
    return DeviceModel(
      deviceID: req['deviceID']?.toString() ?? dev?['deviceID']?.toString() ?? '',
      brand: dev?['brand']?.toString() ?? 'Apple',
      model: dev?['model']?.toString() ?? 'iPhone 13 Pro',
      storageCapacity: dev?['storageCapacity']?.toString() ?? '128GB',
      colour: dev?['colour']?.toString() ?? dev?['color']?.toString() ?? 'Graphite',
      imeiNum: req['imeiNum']?.toString() ?? dev?['imeiNum']?.toString(),
    );
  }

  void _continueRequest(Map<String, dynamic> req) {
    final status = (req['requestStatus'] ?? '').toString().toLowerCase().trim();
    final deviceObj = _buildDeviceFromReq(req);
    final rawId = req['tradeInRequestID']?.toString() ?? 'TRD-8992-BX';
    final cleanId = rawId.replaceAll('#', '');
    final estValue = _formatEstimatedValue(req['estimatedValue']);

    if (status == 'submitted' || status.contains('transit') || status.contains('submit')) {
      // 1. Submitted -> Improve Your Assessment Page
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImproveAssessmentPage(
            device: deviceObj,
            tradeInRequestID: cleanId,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            fromMyTradeInRequests: true,
          ),
        ),
      );
    } else if (status == 'evaluated' || status.contains('evaluat')) {
      // 2. Evaluated -> Condition Page (Assessment Result Page)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AssessmentResultPage(
            device: deviceObj,
            tradeInRequestID: cleanId,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            fromMyTradeInRequests: true,
          ),
        ),
      );
    } else if (status == 'quoted' || status.contains('quote')) {
      // 3. Quoted -> Quotation Page (Preliminary Quotation Page)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreliminaryQuotationPage(
            device: deviceObj,
            tradeInRequestID: cleanId,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            estimatedValue: estValue,
            fromMyTradeInRequests: true,
          ),
        ),
      );
    } else if (status == 'accepted' || status.contains('accept') || status == 'completed') {
      // 4. Accepted -> Given Image Page (Request Created Page)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TradeInRequestCreatedPage(
            tradeInRequestID: cleanId,
            device: deviceObj,
            estimatedValue: estValue,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
            isRejected: false,
            fromMyTradeInRequests: true,
          ),
        ),
      );
    } else {
      _showRequestDetailsModal(req);
    }
  }

  Future<void> _confirmCancelRequest(Map<String, dynamic> req) async {
    final reqId = req['tradeInRequestID']?.toString() ?? '#TRD-8992-BX';
    final formattedId = reqId.startsWith('#') ? reqId : '#$reqId';

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel Trade-In Request?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        content: Text(
          'Are you sure you want to cancel trade-in request $formattedId? This action cannot be undone.',
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF475569),
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Keep Request',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Yes, Cancel',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final cleanId = reqId.replaceAll('#', '');
      try {
        if (cleanId.isNotEmpty) {
          await TradeInService.updateTradeInStatus(
            tradeInRequestID: cleanId,
            status: 'Cancelled',
          );
        }
      } catch (_) {}

      setState(() {
        req['requestStatus'] = 'Cancelled';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trade-in request $formattedId has been cancelled.'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showRequestDetailsModal(Map<String, dynamic> req) {
    final dev = req['device'] is Map<String, dynamic> ? req['device'] : null;
    final brand = dev?['brand']?.toString() ?? 'Apple';
    final model = dev?['model']?.toString() ?? 'iPhone 13 Pro';
    final storage = dev?['storageCapacity']?.toString() ?? '128GB';
    final colour = dev?['colour']?.toString() ?? dev?['color']?.toString() ?? 'Graphite';
    final imei = req['imeiNum']?.toString() ?? dev?['imeiNum']?.toString() ?? '352948119028472';
    final reqId = req['tradeInRequestID']?.toString() ?? '#TRD-8992-BX';
    final status = req['requestStatus']?.toString() ?? 'Submitted';
    final estValue = _formatEstimatedValue(req['estimatedValue']);
    final dateSubmitted = _formatSubmittedDate(req['submittedAt']);
    final statusCfg = _getStatusConfig(status);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.of(ctx).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    reqId.startsWith('#') ? reqId : '#$reqId',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0C5AD2),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusCfg['bg'] as Color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusCfg['icon'] as IconData, size: 13, color: statusCfg['color'] as Color),
                        const SizedBox(width: 4),
                        Text(
                          statusCfg['label'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusCfg['color'] as Color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$brand $model',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildModalInfoRow('Storage', storage),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildModalInfoRow('Colour', colour),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildModalInfoRow('IMEI Number', imei),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildModalInfoRow('Est. Trade-In Value', estValue, isHighlight: true),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildModalInfoRow('Date Submitted', dateSubmitted),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _continueRequest(req);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Continue Request',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalInfoRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isHighlight ? FontWeight.w900 : FontWeight.w700,
            color: isHighlight ? const Color(0xFF0C5AD2) : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Separate Active, Completed, and Cancelled requests
    List<Map<String, dynamic>> activeRequests =
        _allRequests.where((r) => _isActiveRequest(r)).toList();
    List<Map<String, dynamic>> completedRequests =
        _allRequests.where((r) => _isCompletedRequest(r)).toList();
    List<Map<String, dynamic>> cancelledRequests =
        _allRequests.where((r) => _isCancelledRequest(r)).toList();

    // If all lists are empty (e.g. fresh user or demo session), show default demo records
    if (_allRequests.isEmpty && !_isLoading) {
      activeRequests = [
        {
          'tradeInRequestID': '#TRD-8992-BX',
          'requestStatus': 'Submitted',
          'submittedAt': '2023-10-26T10:00:00.000Z',
          'device': {
            'brand': 'Apple',
            'model': 'iPhone 13 Pro',
            'storageCapacity': '128GB',
            'colour': 'Graphite',
            'imeiNum': '352948119028472',
          },
          'estimatedValue': {'min': 1050.5, 'max': 1520.0},
        },
        {
          'tradeInRequestID': '#TRD-7412-EK',
          'requestStatus': 'Evaluated',
          'submittedAt': '2023-10-24T14:30:00.000Z',
          'device': {
            'brand': 'Samsung',
            'model': 'Galaxy S23 Ultra',
            'storageCapacity': '256GB',
            'colour': 'Phantom Black',
            'imeiNum': '358291048291024',
          },
          'estimatedValue': {'min': 2100.0, 'max': 2450.5},
        },
        {
          'tradeInRequestID': '#TRD-6204-AQ',
          'requestStatus': 'Quoted',
          'submittedAt': '2023-10-22T09:15:00.000Z',
          'device': {
            'brand': 'Apple',
            'model': 'iPhone 14 Pro Max',
            'storageCapacity': '256GB',
            'colour': 'Deep Purple',
            'imeiNum': '359182049182019',
          },
          'estimatedValue': {'min': 2340.5, 'max': 2355.3},
        },
      ];
      completedRequests = [
        {
          'tradeInRequestID': '#TRD-5510-CL',
          'requestStatus': 'Accepted',
          'submittedAt': '2023-10-20T16:45:00.000Z',
          'device': {
            'brand': 'Google',
            'model': 'Pixel 8 Pro',
            'storageCapacity': '128GB',
            'colour': 'Bay Blue',
            'imeiNum': '357192840192841',
          },
          'estimatedValue': {'min': 1800.0, 'max': 2100.5},
        },
      ];
      cancelledRequests = [
        {
          'tradeInRequestID': '#TRD-3201-CL',
          'requestStatus': 'Cancelled',
          'submittedAt': '2023-10-18T10:41:00.000Z',
          'device': {
            'brand': 'Samsung',
            'model': 'Galaxy A15',
            'storageCapacity': '64GB',
            'colour': 'Blue',
            'imeiNum': '359161831531204',
          },
          'estimatedValue': {'min': 350.5, 'max': 450.0},
        },
      ];
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: ReByteAppBar(
        scaffoldKey: _scaffoldKey,
      ),
      drawer: ReByteDrawer(
        isLoggedIn: widget.isLoggedIn,
        email: widget.email,
        name: widget.name,
        isTradeInRequestsSelected: true,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Back button + Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 24),
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (context) => HomePage(
                              isLoggedIn: widget.isLoggedIn,
                              email: widget.email,
                              name: widget.name,
                              initialIndex: 2,
                            ),
                          ),
                          (route) => false,
                        );
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'My Trade-In Requests',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Tab Bar: Active, Completed, Cancelled
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: const Color(0xFF0C5AD2),
                    unselectedLabelColor: const Color(0xFF64748B),
                    labelStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                    indicatorColor: const Color(0xFF0C5AD2),
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.tab,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sync_rounded, size: 17),
                            const SizedBox(width: 6),
                            Text('Active (${activeRequests.length})'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded, size: 17),
                            const SizedBox(width: 6),
                            Text('Completed (${completedRequests.length})'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cancel_outlined, size: 17),
                            const SizedBox(width: 6),
                            Text('Cancelled (${cancelledRequests.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Request List Views across 3 tabs
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF0C5AD2)),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildActiveTab(activeRequests),
                        _buildRequestList(completedRequests, tabType: 'completed'),
                        _buildRequestList(cancelledRequests, tabType: 'cancelled'),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const ReByteBottomNavBar(
        selectedIndex: -1,
      ),
    );
  }

  /// Builds the Active tab with 3 status filter chips: Submitted, Evaluated, Quoted
  Widget _buildActiveTab(List<Map<String, dynamic>> activeRequests) {
    // Compute item counts for the filter chips
    final submittedCount = activeRequests.where((r) {
      final s = (r['requestStatus'] ?? '').toString().toLowerCase();
      return s.contains('submit') || s.contains('transit');
    }).length;

    final evaluatedCount = activeRequests.where((r) {
      final s = (r['requestStatus'] ?? '').toString().toLowerCase();
      return s.contains('evaluat');
    }).length;

    final quotedCount = activeRequests.where((r) {
      final s = (r['requestStatus'] ?? '').toString().toLowerCase();
      return s.contains('quote');
    }).length;

    // Filter requests according to _activeStatusFilter
    final filteredRequests = activeRequests.where((r) {
      if (_activeStatusFilter == 'All') return true;
      final s = (r['requestStatus'] ?? '').toString().toLowerCase().trim();
      if (_activeStatusFilter == 'Submitted') {
        return s.contains('submit') || s.contains('transit');
      } else if (_activeStatusFilter == 'Evaluated') {
        return s.contains('evaluat');
      } else if (_activeStatusFilter == 'Quoted') {
        return s.contains('quote');
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Status Filter Chips: All, Submitted, Evaluated, Quoted
        Container(
          height: 44,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildFilterChip('All', activeRequests.length),
              const SizedBox(width: 8),
              _buildFilterChip('Submitted', submittedCount),
              const SizedBox(width: 8),
              _buildFilterChip('Evaluated', evaluatedCount),
              const SizedBox(width: 8),
              _buildFilterChip('Quoted', quotedCount),
            ],
          ),
        ),
        // Filtered Request List
        Expanded(
          child: _buildRequestList(
            filteredRequests,
            tabType: 'active',
            emptyMessage: _activeStatusFilter == 'All'
                ? 'No active trade-in requests found'
                : 'No $_activeStatusFilter trade-in requests found',
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, int count) {
    final isSelected = _activeStatusFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeStatusFilter = label;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0C5AD2) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFCBD5E1),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0C5AD2).withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestList(
    List<Map<String, dynamic>> requests, {
    required String tabType,
    String? emptyMessage,
  }) {
    if (requests.isEmpty) {
      String defaultEmptyMsg;
      IconData emptyIcon;
      if (tabType == 'active') {
        defaultEmptyMsg = 'No active trade-in requests found';
        emptyIcon = Icons.sync_problem_rounded;
      } else if (tabType == 'completed') {
        defaultEmptyMsg = 'No completed trade-in requests';
        emptyIcon = Icons.check_circle_outline_rounded;
      } else {
        defaultEmptyMsg = 'No cancelled trade-in requests';
        emptyIcon = Icons.cancel_outlined;
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              emptyIcon,
              size: 54,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 14),
            Text(
              emptyMessage ?? defaultEmptyMsg,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      color: const Color(0xFF0C5AD2),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: requests.length,
        itemBuilder: (context, index) {
          final req = requests[index];
          return _buildTradeInCard(req, tabType: tabType);
        },
      ),
    );
  }

  Widget _buildTradeInCard(Map<String, dynamic> req, {required String tabType}) {
    final dev = req['device'] is Map<String, dynamic> ? req['device'] : null;
    final brand = dev?['brand']?.toString() ?? 'Apple';
    final model = dev?['model']?.toString() ?? 'iPhone 13 Pro';
    final fullDeviceName = '$brand $model'.replaceAll('Apple Apple', 'Apple').trim();
    final reqId = req['tradeInRequestID']?.toString() ?? '#TRD-8992-BX';
    final formattedId = reqId.startsWith('#') ? reqId : '#$reqId';
    final status = req['requestStatus']?.toString() ?? 'Submitted';
    final estValue = _formatEstimatedValue(req['estimatedValue']);
    final dateSubmitted = _formatSubmittedDate(req['submittedAt']);
    final statusCfg = _getStatusConfig(status);
    final String? imgUrl = req['deviceImage']?.toString();
    final isCancelled = status.toLowerCase() == 'cancelled';

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device graphic mockup preview (centered)
          Center(
            child: GestureDetector(
              onTap: () => _showRequestDetailsModal(req),
              child: Container(
                height: 125,
                width: 125,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: imgUrl != null && imgUrl.isNotEmpty
                      ? Image.network(
                          imgUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => _buildFallbackDeviceVisual(),
                        )
                      : _buildFallbackDeviceVisual(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ID and Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                formattedId,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0C5AD2),
                  letterSpacing: 0.3,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusCfg['bg'] as Color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusCfg['icon'] as IconData, size: 13, color: statusCfg['color'] as Color),
                    const SizedBox(width: 5),
                    Text(
                      statusCfg['label'] as String,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: statusCfg['color'] as Color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Device Model Name
          Text(
            fullDeviceName,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),

          // EST. VALUE
          const Text(
            'EST. VALUE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            estValue,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),

          // DATE SUBMITTED
          const Text(
            'DATE SUBMITTED',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateSubmitted,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 18),

          // Action Buttons: Only Active and Completed orders can continue
          if (tabType == 'cancelled' || isCancelled) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                  SizedBox(width: 8),
                  Text(
                    'This trade-in request has been cancelled',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (tabType == 'completed') ...[
            // Completed Order: Can continue to Request Created / Inspection page
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => _continueRequest(req),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5AD2),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continue',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 16),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Active Order: Both Cancel and Continue are available
            Row(
              children: [
                // Cancel Button
                Expanded(
                  flex: 1,
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: () => _confirmCancelRequest(req),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Continue Button
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => _continueRequest(req),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0C5AD2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Continue',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFallbackDeviceVisual() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Container(
          width: 54,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCBD5E1), width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Speaker Notch
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 14,
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFF94A3B8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Screen mockup icon
              const Icon(
                Icons.phone_iphone_rounded,
                size: 28,
                color: Color(0xFF0C5AD2),
              ),
              // Home indicator line
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                width: 16,
                height: 2,
                decoration: BoxDecoration(
                  color: const Color(0xFF94A3B8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
