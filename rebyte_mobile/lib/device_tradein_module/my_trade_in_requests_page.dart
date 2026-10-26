import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../account_management_module/home_page.dart';
import '../account_management_module/services/session_service.dart';
import '../widgets/rebyte_app_bar.dart';
import 'assessment_result_page.dart';
import 'improve_assessment_page.dart';
import 'inspection_method_page.dart';
import 'models/device_model.dart';
import 'preliminary_quotation_page.dart';
import 'schedule_inspection_page.dart';
import 'services/trade_in_flow_session.dart';
import 'services/trade_in_service.dart';
import 'trade_in_request_created_page.dart';
import 'trade_in_request_details_page.dart';
import '../widgets/rebyte_bottom_nav_bar.dart';
import '../widgets/device_title_formatter.dart';

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

class _TradeInTabState {
  final String tabKey;
  final ScrollController scrollController = ScrollController();
  List<Map<String, dynamic>> requests = [];
  int page = 1;
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;

  _TradeInTabState({required this.tabKey});

  void dispose() {
    scrollController.dispose();
  }
}

class _MyTradeInRequestsPageState extends State<MyTradeInRequestsPage>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;
  String _activeStatusFilter = 'All';

  // Toast state
  String? _toastMessage;
  bool _isToastError = false;

  void _showToast(String message, [bool isError = false]) {
    if (!mounted) return;
    setState(() {
      _toastMessage = message;
      _isToastError = isError;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _toastMessage == message) {
        setState(() => _toastMessage = null);
      }
    });
  }

  late final List<_TradeInTabState> _tabStates = [
    _TradeInTabState(tabKey: 'active'),
    _TradeInTabState(tabKey: 'in_progress'),
    _TradeInTabState(tabKey: 'completed'),
    _TradeInTabState(tabKey: 'cancelled'),
  ];

  int _activeCount = 0;
  int _inProgressCount = 0;
  int _completedCount = 0;
  int _cancelledCount = 0;

  int _filterConfirmedCount = 0;
  int _filterEvaluatedCount = 0;
  int _filterQuotedCount = 0;
  int _filterAgreedCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
        final idx = _tabController.index;
        if (_tabStates[idx].requests.isEmpty && !_tabStates[idx].isLoadingMore) {
          _loadTab(idx, isRefresh: true);
        }
      }
    });

    for (int i = 0; i < _tabStates.length; i++) {
      final idx = i;
      _tabStates[idx].scrollController.addListener(() {
        final ctrl = _tabStates[idx].scrollController;
        if (ctrl.hasClients &&
            ctrl.position.pixels >= ctrl.position.maxScrollExtent - 250) {
          _loadMore(idx);
        }
      });
    }

    _loadTab(0, isRefresh: true);
    _loadTab(1, isRefresh: true);
    _loadTab(2, isRefresh: true);
    _loadTab(3, isRefresh: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final s in _tabStates) {
      s.dispose();
    }
    super.dispose();
  }

  Future<String> _resolveEffectiveEmail() async {
    String effectiveEmail = widget.email.trim();
    if (effectiveEmail.isEmpty || effectiveEmail == 'customer@rebyte.com') {
      try {
        final session = await SessionService.getSession();
        final sEmail = session['email']?.trim();
        if (sEmail != null && sEmail.isNotEmpty) {
          effectiveEmail = sEmail;
        } else if (TradeInFlowSession.currentUserEmail != null &&
            TradeInFlowSession.currentUserEmail!.trim().isNotEmpty) {
          effectiveEmail = TradeInFlowSession.currentUserEmail!.trim();
        } else {
          final fbEmail = FirebaseAuth.instance.currentUser?.email?.trim();
          if (fbEmail != null && fbEmail.isNotEmpty) {
            effectiveEmail = fbEmail;
          }
        }
      } catch (_) {}
    }

    if (effectiveEmail.isEmpty || effectiveEmail == 'customer@rebyte.com') {
      effectiveEmail = 'lolincoln021@gmail.com';
    }
    return effectiveEmail;
  }

  Future<void> _loadTab(int tabIndex, {bool isRefresh = false}) async {
    if (tabIndex < 0 || tabIndex >= _tabStates.length) return;
    final state = _tabStates[tabIndex];

    if (isRefresh) {
      state.page = 1;
      state.hasMore = true;
      setState(() {
        state.isLoading = true;
      });
    }

    final email = await _resolveEffectiveEmail();
    final String? statusFilter = (tabIndex == 0 && _activeStatusFilter != 'All')
        ? _activeStatusFilter
        : null;

    final response = await TradeInService.fetchUserTradeInRequestsPaginated(
      userEmail: email,
      tab: state.tabKey,
      status: statusFilter,
      page: state.page,
      limit: 10,
    );

    if (!mounted) return;

    final newItems = List<Map<String, dynamic>>.from(response['requests'] ?? []);
    final counts = response['counts'] as Map<String, dynamic>? ?? {};
    final activeFilters = counts['activeFilters'] as Map<String, dynamic>? ?? {};

    setState(() {
      if (state.page == 1) {
        state.requests = newItems;
      } else {
        state.requests.addAll(newItems);
      }
      state.hasMore = response['hasMore'] == true;
      state.isLoading = false;
      state.isLoadingMore = false;

      // Update global tab counts
      if (counts['active'] != null) _activeCount = counts['active'] as int;
      if (counts['in_progress'] != null) _inProgressCount = counts['in_progress'] as int;
      if (counts['completed'] != null) _completedCount = counts['completed'] as int;
      if (counts['cancelled'] != null) _cancelledCount = counts['cancelled'] as int;

      if (activeFilters['all'] != null) _activeCount = activeFilters['all'] as int;
      if (activeFilters['confirmed'] != null) _filterConfirmedCount = activeFilters['confirmed'] as int;
      if (activeFilters['evaluated'] != null) _filterEvaluatedCount = activeFilters['evaluated'] as int;
      if (activeFilters['quoted'] != null) _filterQuotedCount = activeFilters['quoted'] as int;
      if (activeFilters['agreed'] != null) {
        _filterAgreedCount = activeFilters['agreed'] as int;
      } else if (activeFilters['accepted'] != null) {
        _filterAgreedCount = activeFilters['accepted'] as int;
      }
    });
  }

  Future<void> _loadMore(int tabIndex) async {
    if (tabIndex < 0 || tabIndex >= _tabStates.length) return;
    final state = _tabStates[tabIndex];
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    setState(() {
      state.isLoadingMore = true;
    });

    state.page += 1;
    final email = await _resolveEffectiveEmail();
    final String? statusFilter = (tabIndex == 0 && _activeStatusFilter != 'All')
        ? _activeStatusFilter
        : null;

    final response = await TradeInService.fetchUserTradeInRequestsPaginated(
      userEmail: email,
      tab: state.tabKey,
      status: statusFilter,
      page: state.page,
      limit: 10,
    );

    if (!mounted) return;

    final newItems = List<Map<String, dynamic>>.from(response['requests'] ?? []);
    setState(() {
      state.requests.addAll(newItems);
      state.hasMore = response['hasMore'] == true;
      state.isLoadingMore = false;
    });
  }



  bool _isCollectionService(Map<String, dynamic> req) {
    final rawMethod = (req['inspectionMethod'] ??
            req['method'] ??
            req['taskType'] ??
            req['appointmentType'] ??
            '')
        .toString()
        .toLowerCase();
    return rawMethod.contains('collect') ||
        rawMethod.contains('pickup') ||
        rawMethod.contains('pick up') ||
        rawMethod.contains('ship');
  }

  String _getServiceType(Map<String, dynamic> req) {
    return _isCollectionService(req) ? 'Collection' : 'Inspection';
  }

  String _formatEstimatedValue(dynamic estValueVal) {
    if (estValueVal == null) return '';
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

    if (minD == null && maxD == null) {
      return '';
    }

    if (minD != null && maxD != null && minD != maxD) {
      return 'RM ${fmt.format(minD)} - RM ${fmt.format(maxD)}';
    } else {
      final val = minD ?? maxD!;
      return 'RM ${fmt.format(val)}';
    }
  }

  String _getDeclinedReturnDate(Map<String, dynamic> req) {
    DateTime? declineDate;
    final rawDate = req['rejectedAt'] ?? req['declinedAt'] ?? req['updatedAt'];
    if (rawDate != null) {
      if (rawDate is DateTime) {
        declineDate = rawDate;
      } else if (rawDate is String) {
        declineDate = DateTime.tryParse(rawDate);
      } else if (rawDate is Map && rawDate['_seconds'] != null) {
        final sec = int.tryParse(rawDate['_seconds'].toString()) ?? 0;
        final nano = int.tryParse(rawDate['_nanoseconds']?.toString() ?? '0') ?? 0;
        declineDate = DateTime.fromMillisecondsSinceEpoch(sec * 1000 + (nano / 1000000).round());
      }
    }
    declineDate ??= DateTime.now();
    final returnDate = declineDate.add(const Duration(days: 3));
    return DateFormat('dd-MM-yyyy').format(returnDate);
  }

  Map<String, dynamic> _getStatusConfig(String rawStatus, [Map<String, dynamic>? req]) {
    final s = rawStatus.toLowerCase().trim();
    final rawBooking = (req?['bookingStatus'] ?? '').toString().toLowerCase().trim();
    final rawAppt = (req?['appointmentStatus'] ?? '').toString().toLowerCase().trim();

    final docStatus = (req?['status'] ?? '').toString().toLowerCase().trim();
    final isCancelled = s == 'cancelled' ||
        s == 'canceled' ||
        s.contains('cancel') ||
        rawBooking == 'cancelled' ||
        rawAppt == 'cancelled';
    final isRejected = s == 'rejected' ||
        s.contains('reject') ||
        docStatus == 'rejected' ||
        rawBooking == 'rejected' ||
        rawAppt == 'rejected';
    final isDeclined = !isRejected && (s == 'declined' ||
        s.contains('declin') ||
        docStatus == 'declined' ||
        rawBooking == 'declined' ||
        rawAppt == 'declined');
    final isPaid = req?['isPaid'] == true || s == 'paid' || docStatus == 'paid';
    final isAccepted = !isPaid && (docStatus == 'accepted' || s == 'accepted');
    final isInProgress = !isCancelled &&
        !isRejected &&
        !isDeclined &&
        !isPaid &&
        !isAccepted &&
        !(s == 'completed' || s == 'complete') &&
        !(s == 'inspected' || docStatus == 'inspected' || rawBooking == 'inspected' || rawAppt == 'inspected' || (req?['finalQuotation'] != null)) &&
        !(s == 'inspecting' || s.contains('inspect') || rawBooking == 'inspecting' || rawAppt == 'inspecting') &&
        !(s.contains('hold') || s == 'on hold' || rawBooking == 'on hold' || rawAppt == 'on hold') &&
        (s == 'in progress' ||
            s == 'ongoing' ||
            s == 'on progress' ||
            s.contains('progress') ||
            rawBooking == 'in progress' ||
            rawBooking == 'ongoing' ||
            rawAppt == 'in progress' ||
            rawAppt == 'ongoing' ||
            docStatus == 'in progress' ||
            docStatus == 'ongoing');
    final hasBooking = !isInProgress &&
        ((rawBooking == 'confirmed') ||
            (req?['appointmentDate'] != null) ||
            (req?['appointmentID'] != null) ||
            s == 'scheduled' ||
            docStatus == 'scheduled' ||
            s.contains('schedul') ||
            docStatus.contains('schedul'));
    final isAgreed = !isPaid && !isAccepted && !hasBooking && !isInProgress && (docStatus == 'agreed' || s == 'agreed' || s.contains('agree') || docStatus.contains('agree'));

    if (isCancelled) {
      return {
        'label': 'Cancelled',
        'bg': const Color(0xFFF1F5F9),
        'color': const Color(0xFF64748B),
        'icon': Icons.close_rounded,
      };
    } else if (isRejected) {
      return {
        'label': 'Rejected',
        'bg': const Color(0xFFFEE2E2),
        'color': const Color(0xFFDC2626),
        'icon': Icons.cancel_outlined,
      };
    } else if (isDeclined) {
      return {
        'label': 'Declined',
        'bg': const Color(0xFFFEE2E2),
        'color': const Color(0xFFDC2626),
        'icon': Icons.cancel_outlined,
      };
    } else if (isPaid) {
      return {
        'label': 'Paid',
        'bg': const Color(0xFFDCFCE7),
        'color': const Color(0xFF16A34A),
        'icon': Icons.paid_outlined,
      };
    } else if (isAccepted) {
      return {
        'label': 'Accepted',
        'bg': const Color(0xFFDCFCE7),
        'color': const Color(0xFF16A34A),
        'icon': Icons.task_alt_rounded,
      };
    } else if (s == 'completed' || s == 'complete') {
      return {
        'label': 'Completed',
        'bg': const Color(0xFFDCFCE7),
        'color': const Color(0xFF16A34A),
        'icon': Icons.task_alt_rounded,
      };
    } else if (s == 'inspected' ||
        docStatus == 'inspected' ||
        rawBooking == 'inspected' ||
        rawAppt == 'inspected' ||
        (req?['finalQuotation'] != null && !isAccepted && !(s == 'completed' || s == 'complete'))) {
      return {
        'label': 'Inspected',
        'bg': const Color(0xFFF5F3FF),
        'color': const Color(0xFF7C3AED),
        'icon': Icons.fact_check_outlined,
      };
    } else if (s.contains('hold') || s == 'on hold' || rawBooking == 'on hold' || rawAppt == 'on hold') {
      return {
        'label': 'On Hold',
        'bg': const Color(0xFFFFF7ED),
        'color': const Color(0xFFEA580C),
        'icon': Icons.pause_circle_outline_rounded,
      };
    } else if (s == 'inspecting' || s.contains('inspect') || rawBooking == 'inspecting' || rawAppt == 'inspecting') {
      return {
        'label': 'Inspecting',
        'bg': const Color(0xFFF5F3FF),
        'color': const Color(0xFF7C3AED),
        'icon': Icons.fact_check_outlined,
      };
    } else if (isInProgress) {
      return {
        'label': 'In Progress',
        'bg': const Color(0xFFEFF6FF),
        'color': const Color(0xFF0C5AD2),
        'icon': Icons.navigation_rounded,
      };
    } else if (hasBooking || s == 'scheduled' || s.contains('schedul')) {
      return {
        'label': 'Scheduled',
        'bg': const Color(0xFFEFF6FF),
        'color': const Color(0xFF0C5AD2),
        'icon': Icons.event_available_rounded,
      };
    } else if (isAgreed) {
      return {
        'label': 'Agreed',
        'bg': const Color(0xFFECFDF5),
        'color': const Color(0xFF059669),
        'icon': Icons.check_circle_outline_rounded,
      };
    } else if (s.contains('accept')) {
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
    } else if (s.contains('submit') || s.contains('transit') || s == 'confirmed') {
      return {
        'label': 'Confirmed',
        'bg': const Color(0xFFFEF3C7),
        'color': const Color(0xFFD97706),
        'icon': Icons.verified_outlined,
      };
    } else {
      return {
        'label': 'Confirmed',
        'bg': const Color(0xFFFEF3C7),
        'color': const Color(0xFFD97706),
        'icon': Icons.verified_outlined,
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

  void _navigateToViewProgress(Map<String, dynamic> req) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TradeInRequestDetailsPage(
          request: req,
          isLoggedIn: widget.isLoggedIn,
          email: widget.email,
          name: widget.name,
        ),
      ),
    ).then((_) {
      _loadTab(0, isRefresh: true);
      _loadTab(1, isRefresh: true);
      _loadTab(2, isRefresh: true);
      _loadTab(3, isRefresh: true);
    });
  }

  void _navigateToEditBooking(Map<String, dynamic> req) {
    final deviceObj = _buildDeviceFromReq(req);
    final rawId = req['tradeInRequestID']?.toString() ?? 'TRD-8992-BX';
    final cleanId = rawId.replaceAll('#', '');
    final estValue = _formatEstimatedValue(req['estimatedValue']);
    final isCollect = _isCollectionService(req);
    final method = req['inspectionMethod']?.toString() ??
        (isCollect ? 'Doorstep Collection' : 'On-Site Inspection');

    final bookingAddressID = req['addressID']?.toString();
    final bookingAddressLine = (req['appointmentLocation'] ?? req['inspectionAddress'] ?? req['address'])?.toString();
    final bookingDate = req['appointmentDate']?.toString();
    final bookingSlot = req['appointmentTime']?.toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScheduleInspectionPage(
          tradeInRequestID: cleanId,
          method: method,
          device: deviceObj,
          estimatedValue: estValue,
          email: widget.email,
          name: widget.name,
          isLoggedIn: widget.isLoggedIn,
          fromMyTradeInRequests: true,
          initialAddressID: bookingAddressID,
          initialAddressLine: bookingAddressLine,
          initialDate: bookingDate,
          initialSlot: bookingSlot,
        ),
      ),
    ).then((_) {
      _loadTab(_tabController.index, isRefresh: true);
    });
  }

  void _continueRequest(Map<String, dynamic> req) {
    final status = (req['requestStatus'] ?? '').toString().toLowerCase().trim();
    final deviceObj = _buildDeviceFromReq(req);
    final rawId = req['tradeInRequestID']?.toString() ?? 'TRD-8992-BX';
    final cleanId = rawId.replaceAll('#', '');
    final estValue = _formatEstimatedValue(req['estimatedValue']);
    final rawBooking = (req['bookingStatus'] ?? '').toString().toLowerCase().trim();
    final rawAppt = (req['appointmentStatus'] ?? '').toString().toLowerCase().trim();

    // If cancelled or declined, do nothing
    if (status == 'cancelled' || status == 'canceled' || status.contains('cancel') ||
        status == 'declined' || status == 'rejected' || status.contains('declin') || status.contains('reject') ||
        rawBooking == 'cancelled' || rawBooking == 'declined' ||
        rawAppt == 'cancelled' || rawAppt == 'declined') {
      return;
    }

    if (status == 'on hold' || status.contains('hold') || req['bookingStatus']?.toString().toLowerCase() == 'on hold' || req['appointmentStatus']?.toString().toLowerCase() == 'on hold') {
      // On Hold -> Navigate to ScheduleInspectionPage so customer can reselect date, time, and address
      final bookingAddressID = req['addressID']?.toString();
      final bookingAddressLine = (req['appointmentLocation'] ?? req['inspectionAddress'] ?? req['address'])?.toString();
      final bookingDate = req['appointmentDate']?.toString();
      final bookingSlot = req['appointmentTime']?.toString();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScheduleInspectionPage(
            tradeInRequestID: cleanId,
            method: req['inspectionMethod']?.toString() ?? 'On-Site Inspection',
            device: deviceObj,
            estimatedValue: estValue,
            email: widget.email,
            name: widget.name,
            isLoggedIn: widget.isLoggedIn,
            fromMyTradeInRequests: true,
            initialAddressID: bookingAddressID,
            initialAddressLine: bookingAddressLine,
            initialDate: bookingDate,
            initialSlot: bookingSlot,
          ),
        ),
      ).then((_) {
        _loadTab(_tabController.index, isRefresh: true);
      });
    } else if (status == 'submitted' || status.contains('transit') || status.contains('submit')) {
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
    } else if (status == 'scheduled' || status.contains('schedul') || status == 'in progress' || status == 'ongoing' || status == 'inspected' || status == 'inspecting' || status.contains('inspect') || req['appointmentDate'] != null) {
      // Scheduled / In Progress -> Given Image Page (TradeInRequestDetailsPage)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TradeInRequestDetailsPage(
            request: req,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
          ),
        ),
      );
    } else if (status == 'agreed' || status.contains('agree')) {
      // Agreed -> Choose Inspection Method Page (InspectionMethodPage)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InspectionMethodPage(
            tradeInRequestID: cleanId,
            device: deviceObj,
            estimatedValue: estValue,
            email: widget.email,
            name: widget.name,
            isLoggedIn: widget.isLoggedIn,
            fromMyTradeInRequests: true,
          ),
        ),
      ).then((_) {
        _loadTab(_tabController.index, isRefresh: true);
      });
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
        req['status'] = 'Cancelled';
        req['bookingStatus'] = 'Cancelled';
      });
      _loadTab(0, isRefresh: true);
      _loadTab(1, isRefresh: true);
      _loadTab(3, isRefresh: true);

      if (!mounted) return;
      _showToast('Trade-in request $formattedId has been cancelled successfully.');
    }
  }

  void _showRequestDetailsModal(Map<String, dynamic> req) {
    final rawStatus = (req['requestStatus'] ?? req['status'] ?? '').toString().toLowerCase().trim();
    final rawBooking = (req['bookingStatus'] ?? '').toString().toLowerCase().trim();
    final rawAppt = (req['appointmentStatus'] ?? '').toString().toLowerCase().trim();

    // If cancelled or declined, do nothing
    if (rawStatus == 'cancelled' || rawStatus == 'canceled' || rawStatus.contains('cancel') ||
        rawStatus == 'declined' || rawStatus == 'rejected' || rawStatus.contains('declin') || rawStatus.contains('reject') ||
        rawBooking == 'cancelled' || rawBooking == 'declined' ||
        rawAppt == 'cancelled' || rawAppt == 'declined') {
      return;
    }

    final isOnHold = rawStatus == 'on hold' ||
        rawStatus.contains('hold') ||
        rawBooking == 'on hold' ||
        rawAppt == 'on hold';

    if (isOnHold) {
      _continueRequest(req);
      return;
    }

    final isScheduled = rawStatus == 'scheduled' ||
        rawStatus.contains('schedul') ||
        rawStatus == 'inspected' ||
        rawStatus == 'inspecting' ||
        rawStatus.contains('inspect') ||
        req['appointmentDate'] != null ||
        (req['bookingStatus'] ?? '').toString().toLowerCase() == 'confirmed';

    if (isScheduled) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TradeInRequestDetailsPage(
            request: req,
            isLoggedIn: widget.isLoggedIn,
            email: widget.email,
            name: widget.name,
          ),
        ),
      );
      return;
    }

    final dev = req['device'] is Map<String, dynamic> ? req['device'] : null;
    final brand = dev?['brand']?.toString() ?? 'Apple';
    final model = dev?['model']?.toString() ?? 'iPhone 13 Pro';
    final storage = dev?['storageCapacity']?.toString() ?? '128GB';
    final colour = dev?['colour']?.toString() ?? dev?['color']?.toString() ?? 'Graphite';
    final imei = req['imeiNum']?.toString() ?? dev?['imeiNum']?.toString() ?? '352948119028472';
    final reqId = req['tradeInRequestID']?.toString() ?? '#TRD-8992-BX';
    final status = req['requestStatus']?.toString() ?? 'Submitted';
    final estValue = _formatEstimatedValue(req['estimatedValue']);
    final serviceType = _getServiceType(req);
    final statusCfg = _getStatusConfig(status, req);

    final quotation = req['finalQuotation'] is Map<String, dynamic>
        ? req['finalQuotation'] as Map<String, dynamic>
        : (req['finalQuotation'] is Map
            ? Map<String, dynamic>.from(req['finalQuotation'] as Map)
            : <String, dynamic>{});

    double? resolvedFinalOffer;
    if (quotation['finalOfferPrice'] != null) {
      resolvedFinalOffer = double.tryParse(quotation['finalOfferPrice'].toString());
    } else if (req['finalOfferPrice'] != null) {
      resolvedFinalOffer = double.tryParse(req['finalOfferPrice'].toString());
    } else if (req['finalOfferedValue'] != null) {
      resolvedFinalOffer = double.tryParse(req['finalOfferedValue'].toString());
    } else if (req['offeredPrice'] != null) {
      resolvedFinalOffer = double.tryParse(req['offeredPrice'].toString());
    }

    final docStatus = (req['status'] ?? '').toString().toLowerCase().trim();
    final isRejected = rawStatus == 'rejected' ||
        rawStatus.contains('reject') ||
        docStatus == 'rejected' ||
        rawBooking == 'rejected' ||
        rawAppt == 'rejected';
    final isDeclined = !isRejected && (rawStatus == 'declined' ||
        rawStatus.contains('declin') ||
        docStatus == 'declined' ||
        rawBooking == 'declined' ||
        rawAppt == 'declined');
    final isPaid = req['isPaid'] == true || rawStatus == 'paid' || docStatus == 'paid';
    final isAccepted = !isPaid && (docStatus == 'accepted' || rawStatus == 'accepted');
    final isCompleted = isPaid || isAccepted || rawStatus == 'completed' || rawStatus == 'complete';

    final bool isInspected = rawStatus == 'inspected' ||
        rawBooking == 'inspected' ||
        rawAppt == 'inspected' ||
        docStatus == 'inspected' ||
        req['inspectedAt'] != null ||
        quotation.isNotEmpty;

    final bool showOfferPrice = (isInspected || isPaid || isAccepted || isCompleted || isRejected || isDeclined) &&
        resolvedFinalOffer != null &&
        resolvedFinalOffer > 0;

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
                formatDeviceTitle(brand, model),
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
                    _buildModalInfoRow(
                      showOfferPrice ? 'Actual Offer Price' : 'Est. Trade-In Value',
                      showOfferPrice
                          ? 'RM ${NumberFormat('#,##0.00').format(resolvedFinalOffer)}'
                          : estValue,
                      isHighlight: true,
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildModalInfoRow('Service Type', serviceType),
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
        child: Stack(
          children: [
            Column(
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

            // Tab Bar: Active, On Progress, Completed, Cancelled
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
                            Text('Active ($_activeCount)'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.pending_actions_rounded, size: 17),
                            const SizedBox(width: 6),
                            Text('On Progress ($_inProgressCount)'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded, size: 17),
                            const SizedBox(width: 6),
                            Text('Completed ($_completedCount)'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cancel_outlined, size: 17),
                            const SizedBox(width: 6),
                            Text('Cancelled ($_cancelledCount)'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Request List Views across 4 tabs
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildActiveTab(_tabStates[0]),
                  _buildRequestList(_tabStates[1], tabType: 'in_progress'),
                  _buildRequestList(_tabStates[2], tabType: 'completed'),
                  _buildRequestList(_tabStates[3], tabType: 'cancelled'),
                ],
              ),
            ),
          ],
        ),

        // Top Floating Toast Banner
        if (_toastMessage != null)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _isToastError ? const Color(0xFFE11D48) : const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      _isToastError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _toastMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _toastMessage = null),
                      child: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                    ),
                  ],
                ),
              ),
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

  /// Builds the Active tab with 4 status filter chips: Confirmed, Evaluated, Quoted, Accepted
  Widget _buildActiveTab(_TradeInTabState state) {
    if (_activeStatusFilter == 'Scheduled') {
      _activeStatusFilter = 'All';
    }

    return Column(
      children: [
        // Status Filter Chips: All, Confirmed, Evaluated, Quoted, Accepted
        Container(
          height: 44,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildFilterChip('All', _activeCount),
              const SizedBox(width: 8),
              _buildFilterChip('Confirmed', _filterConfirmedCount),
              const SizedBox(width: 8),
              _buildFilterChip('Evaluated', _filterEvaluatedCount),
              const SizedBox(width: 8),
              _buildFilterChip('Quoted', _filterQuotedCount),
              const SizedBox(width: 8),
              _buildFilterChip('Agreed', _filterAgreedCount),
            ],
          ),
        ),
        // Filtered Request List with infinite scroll
        Expanded(
          child: _buildRequestList(
            state,
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
        if (_activeStatusFilter != label) {
          setState(() {
            _activeStatusFilter = label;
          });
          _loadTab(0, isRefresh: true);
        }
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
    _TradeInTabState state, {
    required String tabType,
    String? emptyMessage,
  }) {
    final tabIdx = _tabStates.indexWhere((s) => s.tabKey == tabType);

    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0C5AD2)),
      );
    }

    final requests = state.requests;

    if (requests.isEmpty) {
      String defaultEmptyMsg;
      IconData emptyIcon;
      if (tabType == 'active') {
        defaultEmptyMsg = 'No active trade-in requests found';
        emptyIcon = Icons.sync_problem_rounded;
      } else if (tabType == 'in_progress') {
        defaultEmptyMsg = 'No trade-in requests currently on progress';
        emptyIcon = Icons.pending_actions_rounded;
      } else if (tabType == 'completed') {
        defaultEmptyMsg = 'No completed trade-in requests';
        emptyIcon = Icons.check_circle_outline_rounded;
      } else {
        defaultEmptyMsg = 'No cancelled trade-in requests';
        emptyIcon = Icons.cancel_outlined;
      }

      return RefreshIndicator(
        onRefresh: () => _loadTab(tabIdx != -1 ? tabIdx : 0, isRefresh: true),
        color: const Color(0xFF0C5AD2),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.45,
              child: Center(
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
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadTab(tabIdx != -1 ? tabIdx : 0, isRefresh: true),
      color: const Color(0xFF0C5AD2),
      child: ListView.builder(
        controller: state.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: requests.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == requests.length) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF0C5AD2),
                ),
              ),
            );
          }
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
    final fullDeviceName = formatDeviceTitle(brand, model);
    final reqId = req['tradeInRequestID']?.toString() ?? '#TRD-8992-BX';
    final formattedId = reqId.startsWith('#') ? reqId : '#$reqId';
    final status = req['requestStatus']?.toString() ?? 'Submitted';
    final estValue = _formatEstimatedValue(req['estimatedValue']);
    final serviceType = _getServiceType(req);
    final isCollect = _isCollectionService(req);
    final statusCfg = _getStatusConfig(status, req);
    final String? imgUrl = req['deviceImage']?.toString();
    final docStatus = (req['status'] ?? '').toString().toLowerCase().trim();
    final rawStatus = status.toLowerCase().trim();
    final rawBookingStatus = (req['bookingStatus'] ?? '').toString().toLowerCase().trim();
    final rawApptStatus = (req['appointmentStatus'] ?? '').toString().toLowerCase().trim();
    final isRejected = rawStatus == 'rejected' ||
        rawStatus.contains('reject') ||
        docStatus == 'rejected' ||
        rawBookingStatus == 'rejected' ||
        rawApptStatus == 'rejected';
    final isDeclined = !isRejected && (rawStatus == 'declined' ||
        rawStatus.contains('declin') ||
        docStatus == 'declined' ||
        rawBookingStatus == 'declined' ||
        rawApptStatus == 'declined');
    final isCancelled = !isRejected && !isDeclined && (rawStatus == 'cancelled' ||
        rawStatus == 'canceled' ||
        rawStatus.contains('cancel') ||
        rawBookingStatus == 'cancelled' ||
        rawApptStatus == 'cancelled');
    final isPaid = req['isPaid'] == true || rawStatus == 'paid' || docStatus == 'paid';
    final isAccepted = !isPaid && (docStatus == 'accepted' || rawStatus == 'accepted');
    final isCompleted = tabType == 'completed' || isPaid || isAccepted || rawStatus == 'completed' || rawStatus == 'complete';

    final quotation = req['finalQuotation'] is Map<String, dynamic>
        ? req['finalQuotation'] as Map<String, dynamic>
        : (req['finalQuotation'] is Map
            ? Map<String, dynamic>.from(req['finalQuotation'] as Map)
            : <String, dynamic>{});

    double? resolvedFinalOffer;
    if (quotation['finalOfferPrice'] != null) {
      resolvedFinalOffer = double.tryParse(quotation['finalOfferPrice'].toString());
    } else if (req['finalOfferPrice'] != null) {
      resolvedFinalOffer = double.tryParse(req['finalOfferPrice'].toString());
    } else if (req['finalOfferedValue'] != null) {
      resolvedFinalOffer = double.tryParse(req['finalOfferedValue'].toString());
    } else if (req['offeredPrice'] != null) {
      resolvedFinalOffer = double.tryParse(req['offeredPrice'].toString());
    }

    final bool isInspected = rawStatus == 'inspected' ||
        rawBookingStatus == 'inspected' ||
        rawApptStatus == 'inspected' ||
        docStatus == 'inspected' ||
        req['inspectedAt'] != null ||
        quotation.isNotEmpty;

    final bool showOfferPrice = (isInspected || isPaid || isAccepted || isCompleted || isRejected || isDeclined) &&
        resolvedFinalOffer != null &&
        resolvedFinalOffer > 0;

    final String displayPrice = showOfferPrice
        ? 'RM ${NumberFormat('#,##0.00').format(resolvedFinalOffer)}'
        : estValue;
    final String priceLabel = showOfferPrice ? 'ACTUAL OFFER PRICE' : 'EST. VALUE';

    final Color priceColor;
    final Color priceLabelColor;
    if (showOfferPrice) {
      if (isAccepted || isCompleted) {
        priceColor = const Color(0xFF16A34A);
        priceLabelColor = const Color(0xFF16A34A);
      } else if (isRejected || isDeclined) {
        priceColor = const Color(0xFF0F172A);
        priceLabelColor = const Color(0xFF64748B);
      } else {
        // Inspected
        priceColor = const Color(0xFF7C3AED);
        priceLabelColor = const Color(0xFF7C3AED);
      }
    } else {
      priceColor = const Color(0xFF0F172A);
      priceLabelColor = const Color(0xFF64748B);
    }

    final isInspecting = !isAccepted && !isCompleted && !isInspected && (rawStatus == 'inspecting' ||
        rawBookingStatus == 'inspecting' ||
        rawApptStatus == 'inspecting');
    final isInProgress = !isCancelled && !isDeclined && !isRejected && !isCompleted && !isAccepted && (isInspecting ||
        isInspected ||
        rawStatus == 'in progress' ||
        rawStatus == 'ongoing' ||
        rawStatus.contains('progress') ||
        rawBookingStatus == 'in progress' ||
        rawBookingStatus == 'ongoing' ||
        rawApptStatus == 'in progress' ||
        rawApptStatus == 'ongoing');
    final isOnHold = !isCancelled && !isDeclined && !isRejected && !isCompleted && !isAccepted && !isInspected && (rawStatus == 'on hold' ||
        rawStatus.contains('hold') ||
        rawBookingStatus == 'on hold' ||
        rawApptStatus == 'on hold');
    final hasDateTime = req['appointmentDate'] != null && req['appointmentTime'] != null;
    final appointmentStr = hasDateTime ? '${req['appointmentDate']} • ${req['appointmentTime']}' : null;

    final String statusLabel = (statusCfg['label'] as String? ?? '').toLowerCase();
    final bool isConfirmed = statusLabel == 'confirmed' || rawStatus.contains('submit') || rawStatus.contains('transit') || rawStatus == 'confirmed';
    final bool isEvaluated = statusLabel == 'evaluated' || rawStatus.contains('evaluat');

    final bool hasEstimatedValueInRecord = req['estimatedValue'] != null && _formatEstimatedValue(req['estimatedValue']).trim().isNotEmpty;
    final bool isActuallyCancelled = isCancelled || (tabType == 'cancelled' && !isDeclined && !isRejected);

    // On Active tab:
    // - Confirmed and Evaluated request DONT have the est value and service type
    // - Quoted and Agreed request DONT have the service type (they keep est value / offer price)
    // On Cancelled:
    // - Depends on whether it is before quoted or after quoted (checked via estimatedValue in tradeinRequest record)
    //   If yes: have est value
    //   If not: dont put est value
    //   And cancelled DONT have service type
    // On Declined:
    // - DONT have service type
    final bool showPriceSection;
    if (tabType == 'active') {
      showPriceSection = (!isConfirmed && !isEvaluated);
    } else if (isActuallyCancelled) {
      showPriceSection = hasEstimatedValueInRecord;
    } else if (isDeclined || isRejected) {
      showPriceSection = showOfferPrice || hasEstimatedValueInRecord;
    } else {
      showPriceSection = displayPrice.trim().isNotEmpty;
    }

    final bool showServiceTypeSection;
    if (isRejected) {
      showServiceTypeSection = true;
    } else if (tabType == 'active' || isCancelled || isDeclined || isActuallyCancelled) {
      showServiceTypeSection = false;
    } else {
      showServiceTypeSection = true;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: (tabType == 'active' || tabType == 'cancelled' || isCancelled || isDeclined || isRejected)
          ? null
          : () {
              if (tabType == 'in_progress' || tabType == 'completed' || isAccepted || isPaid || isInspected) {
                _navigateToViewProgress(req);
              } else if (tabType == 'on_hold') {
                _navigateToEditBooking(req);
              } else {
                _showRequestDetailsModal(req);
              }
            },
      child: Container(
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
                onTap: (tabType == 'active' || tabType == 'cancelled' || isCancelled || isDeclined || isRejected)
                    ? null
                    : () {
                        if (tabType == 'in_progress' || tabType == 'completed' || isAccepted || isPaid || isInspected) {
                          _navigateToViewProgress(req);
                        } else if (tabType == 'on_hold') {
                          _navigateToEditBooking(req);
                        } else {
                          _showRequestDetailsModal(req);
                        }
                      },
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

          // Price Section: ACTUAL OFFER PRICE or EST. VALUE
          if (showPriceSection) ...[
            const SizedBox(height: 14),
            Text(
              priceLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: priceLabelColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              displayPrice,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: priceColor,
                letterSpacing: -0.3,
              ),
            ),
          ],

          // SERVICE TYPE
          if (showServiceTypeSection) ...[
            const SizedBox(height: 14),
            const Text(
              'SERVICE TYPE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  isCollect ? Icons.local_shipping_outlined : Icons.fact_check_outlined,
                  size: 16,
                  color: isCollect ? const Color(0xFFD97706) : const Color(0xFF0C5AD2),
                ),
                const SizedBox(width: 6),
                Text(
                  serviceType,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ],

          // APPOINTMENT (If scheduled)
          if (appointmentStr != null) ...[
            const SizedBox(height: 14),
            const Text(
              'APPOINTMENT SCHEDULED',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0C5AD2),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.event_available_rounded, size: 16, color: Color(0xFF0C5AD2)),
                const SizedBox(width: 6),
                Text(
                  appointmentStr,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),

          // Action Buttons: Cancelled, On Hold, In Progress, Completed, Active
          if (tabType == 'cancelled' || isCancelled || isDeclined || isRejected) ...[
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
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (isRejected || (isDeclined && (req['finalQuotation'] != null || req['finalOfferPrice'] != null || req['inspectedAt'] != null)))
                          ? 'The phone will be sent to you at ${_getDeclinedReturnDate(req)}'
                          : (isDeclined
                              ? 'This trade-in request has been declined'
                              : 'This trade-in request has been cancelled'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isOnHold) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFEDD5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFEA580C), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your scheduled ${req['inspectionMethod'] ?? 'inspection'} is currently on hold because no technician is available. Please reselect your appointment or cancel.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF9A3412),
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
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
                          Icon(Icons.event_repeat_rounded, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Reschedule',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (isInProgress) ...[
            // In Progress: Staff has started task, cancel and edit booking cannot appear
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => _navigateToViewProgress(req),
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
                    Icon(Icons.visibility_outlined, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'View Progress',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (tabType == 'in_progress') ...[
            // On Progress: Cancel and View Progress buttons like active tab
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

                // Edit Booking Button (navigates to calendar page)
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: () => _navigateToEditBooking(req),
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
                          Icon(Icons.edit_calendar_rounded, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Edit Booking',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (tabType == 'completed' || isAccepted || isPaid) ...[
            // Completed Order: View Completed Summary
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => _navigateToViewProgress(req),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'View Summary',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
