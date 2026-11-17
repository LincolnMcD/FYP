import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'staff_profile_page.dart';
import '../task_assignment_module/widgets/staff_app_bar_and_drawer.dart';
import '../account_management_module/services/session_service.dart';
import '../account_management_module/services/auth_service.dart';
import '../account_management_module/services/account_session_watch_service.dart';
import '../account_management_module/services/app_route_observer.dart';
import '../account_management_module/home_page.dart';
import '../task_assignment_module/services/task_assignment_service.dart';
import 'staff_schedule_page.dart';
import 'staff_leave_application_page.dart';
import 'rebyte_standards_page.dart';
import '../task_assignment_module/staff_assigned_tasks_page.dart';

class StaffHomePage extends StatefulWidget {
  final String? toastMessage;
  final int? initialIndex;
  final int? initialTaskTabIndex;
  final String? email;
  final bool initialShowStandards;

  const StaffHomePage({
    super.key,
    this.toastMessage,
    this.initialIndex,
    this.initialTaskTabIndex,
    this.email,
    this.initialShowStandards = false,
  });

  @override
  State<StaffHomePage> createState() => _StaffHomePageState();
}

class _StaffHomePageState extends State<StaffHomePage> with WidgetsBindingObserver, RouteAware {
  late int _selectedIndex;
  bool _showStandards = false;
  String? _name;
  String? _email;
  String? _position;
  String? _toastMessage;
  final bool _isToastError = false;
  bool _staffSessionCheckInProgress = false;
  bool _staffSessionEnding = false;
  int _sessionCheckFailures = 0;
  DateTime? _nextSessionCheckAt;
  ModalRoute<dynamic>? _observedRoute;

  List<Map<String, dynamic>>? _cachedTasks;
  Map<String, dynamic>? _cachedLeave;
  int _dashboardLoad = 0;
  late Future<List<Map<String, dynamic>>?> _dashboardTasks;
  late Future<Map<String, dynamic>?> _dashboardLeave;

  void _refreshDashboard() {
    final load = ++_dashboardLoad;
    _cachedTasks = null;
    _cachedLeave = null;
    _dashboardTasks = Future.microtask(() => TaskAssignmentService.fetchStaffTasks(
      email: _email,
      requireLiveData: true,
      onCached: (tasks) {
        if (mounted && load == _dashboardLoad) setState(() => _cachedTasks = tasks);
      },
    )).then<List<Map<String, dynamic>>?>((tasks) => tasks, onError: (_) => null);
    _dashboardLeave = Future.microtask(() => _loadDashboardLeave(load))
        .then<Map<String, dynamic>?>((leave) => leave, onError: (_) => null);
  }

  Future<Map<String, dynamic>> _loadDashboardLeave(int load) async {
    final email = _email ?? (await SessionService.getSession())['email'];
    if (email == null || email.isEmpty) throw StateError('Staff session missing');
    return TaskAssignmentService.fetchLeaveBalance(
      email: email, requireLiveData: true,
      onCached: (leave) {
        if (mounted && load == _dashboardLoad) setState(() => _cachedLeave = leave);
      },
    );
  }

  bool get _isCurrentRoute => ModalRoute.of(context)?.isCurrent ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _observedRoute) {
      if (_observedRoute != null) appRouteObserver.unsubscribe(this);
      _observedRoute = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    if (!_staffSessionEnding) {
      setState(_refreshDashboard);
      AccountSessionWatchService.restart(baseUrl: AuthService.baseUrl, onState: _handleStaffSessionState);
    }
  }
  
  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex ?? 0;
    _showStandards = widget.initialShowStandards;
    if (widget.email != null && widget.email!.isNotEmpty) {
      _email = widget.email;
    }
    WidgetsBinding.instance.addObserver(this);
    _toastMessage = widget.toastMessage;
    if (_toastMessage != null) {
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) setState(() => _toastMessage = null);
      });
    }
    _refreshDashboard();
    _loadSession();
    _loadFreshStaffProfile();
    AccountSessionWatchService.start(baseUrl: AuthService.baseUrl, onState: _handleStaffSessionState);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isCurrentRoute) {
      setState(_refreshDashboard);
      AccountSessionWatchService.restart(baseUrl: AuthService.baseUrl, onState: _handleStaffSessionState);
    }
  }

  Future<void> _handleStaffSessionState(Map<String, dynamic> state) async {
    if (!mounted || _staffSessionEnding || AccountSessionWatchService.isSuspendedForPublicFlow) return;
    if (state['expired'] == true || (state['active'] == true && state['role'] != 'staff')) {
      if (AuthService.passwordChangeInProgress) {
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (mounted && !_staffSessionEnding) {
            AccountSessionWatchService.restart(baseUrl: AuthService.baseUrl, onState: _handleStaffSessionState);
          }
        });
        return;
      }
      await _endStaffSession(archived: state['archived'] == true);
    } else if (state['active'] == true && state['changed'] == true) {
      await _verifyStaffSession();
    }
  }

  Future<void> _verifyStaffSession() async {
    if (_staffSessionCheckInProgress || _staffSessionEnding) return;
    if (_nextSessionCheckAt != null && DateTime.now().isBefore(_nextSessionCheckAt!)) return;
    _staffSessionCheckInProgress = true;
    try {
      final result = await AuthService.checkStaffSession();
      if (result['expired'] == true) {
        await _endStaffSession(archived: result['archived'] == true);
      } else if (result['success'] == true) {
        _sessionCheckFailures = 0;
        _nextSessionCheckAt = null;
        if (result['profile'] is Map) {
          await _applyStaffProfile(Map<String, dynamic>.from(result['profile'] as Map));
        } else {
          await _loadFreshStaffProfile();
        }
      } else if (result['transient'] == true) {
        _sessionCheckFailures = (_sessionCheckFailures + 1).clamp(1, 5).toInt();
        final seconds = (15 * (1 << (_sessionCheckFailures - 1))).clamp(15, 300).toInt();
        _nextSessionCheckAt = DateTime.now().add(Duration(seconds: seconds));
      }
    } finally {
      _staffSessionCheckInProgress = false;
    }
  }

  Future<void> _endStaffSession({bool archived = false}) async {
    if (_staffSessionEnding) return;
    _staffSessionEnding = true;
    await SessionService.clearSession();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => HomePage(
          isLoggedIn: false,
          toastMessage: archived
              ? 'This account has been archived. Please contact administrator.'
              : 'Session expired. Please log in again.',
          toastIsError: true,
        ),
      ),
      (route) => false,
    );
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadSession() async {
    final session = await SessionService.getSession();
    if (session.isNotEmpty) {
      if (mounted) {
        setState(() {
          _email = session['email'];
          _name = session['name'];
        });
      }
    }
  }

  Future<void> _applyStaffProfile(Map<String, dynamic> profile) async {
    final name = (profile['fullName'] as String?)?.trim();
    final email = (profile['email'] as String?)?.trim();
    final rawPos = (profile['position'] as String?)?.trim();
    final pos = rawPos == 'Both' ? 'Inspector & Collector' : rawPos;
    if (!mounted) return;
    final shouldPersistIdentity =
        email?.isNotEmpty == true && name?.isNotEmpty == true && (_email != email || _name != name);
    setState(() {
      if (name?.isNotEmpty == true) _name = name;
      if (email?.isNotEmpty == true) _email = email;
      if (pos?.isNotEmpty == true) _position = pos;
    });
    if (shouldPersistIdentity) {
      await SessionService.saveSession(email: email!, name: name!, role: 'Staff');
    }
  }

  Future<void> _loadFreshStaffProfile() async {
    final result = await AuthService.getStaffProfile();
    if (result['success'] == true && result['data'] is Map) {
      await _applyStaffProfile(Map<String, dynamic>.from(result['data'] as Map));
      return;
    }
    final session = await SessionService.getSession();
    final email = session['email'];
    if (email == null || email.isEmpty) return;
    final fallback = await AuthService.getProfile(email);
    if (fallback['success'] == true && fallback['data'] is Map) {
      await _applyStaffProfile(Map<String, dynamic>.from(fallback['data'] as Map));
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: StaffDrawer(
        selectedIndex: _showStandards ? 4 : _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _showStandards = index == 4;
            if (!_showStandards) _selectedIndex = index;
          });
          if (index == 0) _refreshDashboard();
        },
        onLogout: _showLogoutDialog,
      ),
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            style: const ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
              overlayColor: WidgetStatePropertyAll(Colors.transparent),
              shadowColor: WidgetStatePropertyAll(Colors.transparent),
              elevation: WidgetStatePropertyAll(0),
            ),
            icon: const Icon(Icons.menu, color: Color(0xFF0C5AD2)),
            onPressed: () { Scaffold.of(context).openDrawer(); },
          ),
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedIndex = 3;
                _showStandards = false;
                });
                _verifyStaffSession();
              },
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.grey.shade300,
                child: Icon(
                  Icons.person,
                  color: Colors.grey.shade600,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _showStandards
              ? ReByteStandardsPage(onExit: () => setState(() => _showStandards = false))
              : _selectedIndex == 3
              ? StaffProfilePage(
                  name: _name,
                  email: _email,
                  position: _position,
                  onLogout: _showLogoutDialog,
                  onProfileUpdated: () async { await _loadFreshStaffProfile(); },
                  onNavigateToTasks: () {
                    setState(() {
                      _selectedIndex = 2;
                      _showStandards = false;
                    });
                  },
                  onNavigateToSchedule: () {
                    setState(() {
                      _selectedIndex = 1;
                      _showStandards = false;
                    });
                  },
                  onNavigateToStandards: () {
                    setState(() => _showStandards = true);
                  },
                )
              : _selectedIndex == 2
                  ? StaffAssignedTasksPage(
                      key: ValueKey('staff_tasks_${_email ?? 'session'}_${widget.initialTaskTabIndex ?? 0}'),
                      email: _email,
                      initialTabIndex: widget.initialTaskTabIndex ?? 0,
                    )
                  : _selectedIndex == 1
                      ? StaffSchedulePage(
                          email: _email,
                        )
                      : _buildDashboard(),
      if (_toastMessage != null)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Dismissible(
                key: UniqueKey(),
                direction: DismissDirection.horizontal,
                onDismissed: (_) => setState(() => _toastMessage = null),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: _isToastError ? const Color(0xFFE11D48) : Colors.green.shade600,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        Icon(_isToastError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_toastMessage!, textAlign: TextAlign.justify, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, -5))],
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() {
            if (index == 0) _refreshDashboard();
            _selectedIndex = index;
            _showStandards = false;
          }),
          selectedItemColor: const Color(0xFF0C5AD2),
          unselectedItemColor: const Color(0xFF64748B),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
          items: [
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded, size: 24), label: 'Dashboard'),
            const BottomNavigationBarItem(icon: Icon(Icons.calendar_today_rounded, size: 24), label: 'Schedule'),
            const BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined, size: 24), label: 'Tasks'),
            const BottomNavigationBarItem(icon: Icon(Icons.person_outline, size: 24), label: 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard(String title, String count, IconData icon, Color primary, Color background) {
    return Container(
      padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12, right: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: background, shape: BoxShape.circle),
                child: Icon(icon, color: primary, size: 14),
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(title, style: const TextStyle(color: Color(0xFF475569), fontSize: 10, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 12),
          Text(count, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final today = DateTime.now().toUtc().add(const Duration(hours: 8));
    String dateKey(DateTime date) => date.toIso8601String().split('T').first;
    final todayKey = dateKey(today);

    int? category(Map<String, dynamic> task) {
      final status = (task['taskStatus'] ?? '').toString().trim().toLowerCase();
      final schedule = (task['scheduleStatus'] ?? '').toString().trim().toLowerCase();
      const excluded = ['absent', 'rejected', 'cancelled', 'reassigned', 'unassigned'];
      if (excluded.contains(status) || excluded.contains(schedule)) return null;
      if (schedule == 'completed' || ['completed', 'delivered'].contains(status)) return 2;
      if (schedule == 'ongoing' || ['in progress', 'ongoing', 'shipping'].contains(status)) return 1;
      if (schedule == 'assigned' || ['assigned', 'packaging'].contains(status)) return 0;
      return null;
    }

    String fields(Map<String, dynamic> task, List<String> keys) =>
        keys.map((key) => task[key]?.toString() ?? '').where((value) => value.isNotEmpty).join(' · ');

    Widget taskCard(Map<String, dynamic> task, {bool actionRequired = false}) {
      final type = (task['taskType'] ?? '').toString().toLowerCase();
      final inspect = type.contains('inspect');
      final collect = type.contains('collect');
      final accent = Color(inspect ? 0xFF7C3AED : collect ? 0xFF059669 : 0xFF2563EB);
      final background = Color(inspect ? 0xFFF3E8FF : collect ? 0xFFECFDF5 : 0xFFEFF6FF);
      final label = inspect ? 'Inspection' : collect ? 'Collection' : 'Delivery';
      final status = category(task);
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => setState(() {
            _selectedIndex = actionRequired ? 2 : 1;
            _showStandards = false;
          }),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: .35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
                      child: Icon(
                        inspect ? Icons.assignment_outlined
                            : collect ? Icons.local_mall_outlined : Icons.local_shipping_outlined,
                        color: accent, size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(label, style: TextStyle(
                      color: accent, fontWeight: FontWeight.w700, fontSize: 12,
                    ))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            status == 2 ? Icons.check_circle_outline
                                : status == 1 ? Icons.timelapse : Icons.schedule,
                            size: 13, color: accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            status == 2 ? 'Completed' : status == 1 ? 'In Progress' : 'Assigned',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  fields(task, ['scheduleStartTime', 'scheduleEndTime']),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0C5AD2)),
                ),
                const SizedBox(height: 8),
                Text(
                  task['deviceModel']?.toString() ?? task['model']?.toString() ?? label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 5),
                Text(
                  task['customerName']?.toString() ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    const heading = TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 15);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Welcome, ${_name?.split(" ").first ?? "Staff"}!', style: const TextStyle(color: Color(0xFF0C5AD2), fontWeight: FontWeight.w900, fontSize: 16)),
          Text(MaterialLocalizations.of(context).formatFullDate(today), style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          const SizedBox(height: 16),
          FutureBuilder<List<Map<String, dynamic>>?>(
            future: _dashboardTasks,
            builder: (context, snapshot) {
              final tasks = snapshot.connectionState == ConnectionState.waiting
                  ? _cachedTasks ?? snapshot.data : snapshot.data ?? _cachedTasks;
              final scheduled = (tasks ?? []).where((task) =>
                  task['scheduleDate'] == todayKey && category(task) != null).toList()
                ..sort((a, b) => fields(a, ['scheduleStartTime']).compareTo(fields(b, ['scheduleStartTime'])));
              final active = scheduled.where((task) => category(task) == 1).toList();
              final completed = (tasks ?? []).where((task) {
                if (category(task) != 2) return false;
                final date = DateTime.tryParse(task['completedAt']?.toString() ?? '');
                return date == null ? task['scheduleDate'] == todayKey
                    : dateKey(date.toUtc().add(const Duration(hours: 8))) == todayKey;
              }).length;
              String count(int value) => tasks == null ? '—' : value.toString();
              final message = snapshot.connectionState == ConnectionState.waiting
                  ? 'Loading tasks…' : 'Could not load tasks.';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: _buildKpiCard('Active', count(scheduled.where((task) => category(task) == 0).length), Icons.assignment_outlined, Colors.blue, const Color(0xFFEFF6FF))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildKpiCard('In Progress', count(scheduled.where((task) => category(task) == 1).length), Icons.timelapse, Colors.orange, const Color(0xFFFFFBEB))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildKpiCard('Completed', count(completed), Icons.check_circle_outline, Colors.green, const Color(0xFFECFDF5))),
                  ]),
                  const SizedBox(height: 20),
                  Text('Action Required', style: heading),
                  const SizedBox(height: 12),
                  if (tasks == null) Text(message)
                  else if (active.isEmpty) _buildEmptyTaskCard(
                    Icons.task_alt_rounded,
                    'No tasks in progress',
                    'Tasks you start will appear here.',
                  )
                  else if (active.length == 1) taskCard(active.single, actionRequired: true)
                  else LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final task in active)
                        Container(width: constraints.maxWidth * .85, margin: const EdgeInsets.only(right: 12), child: taskCard(task, actionRequired: true)),
                    ]),
                  )),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: Text("Today's Schedule", style: heading)),
                    TextButton(onPressed: () => setState(() => _selectedIndex = 1), child: const Text('View All')),
                  ]),
                  if (tasks == null) Text(message)
                  else if (scheduled.isEmpty) _buildEmptyTaskCard(
                    Icons.event_available_outlined,
                    'No tasks scheduled today',
                    'New assignments will appear here.',
                  )
                  else SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final task in scheduled)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: SizedBox(width: 250, child: taskCard(task)),
                        ),
                    ]),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: FutureBuilder<Map<String, dynamic>?>(
                  future: _dashboardLeave,
                  builder: (context, snapshot) {
                    final leave = snapshot.connectionState == ConnectionState.waiting
                        ? _cachedLeave ?? snapshot.data : snapshot.data ?? _cachedLeave;
                    return _buildDashboardTile(
                    icon: Icons.beach_access_outlined,
                    title: 'Leave Balance',
                    accent: const Color(0xFF0C5AD2),
                    detail: leave == null
                        ? Text(snapshot.connectionState == ConnectionState.waiting ? 'Loading…' : 'Unavailable')
                        : Table(
                            columnWidths: const {
                              0: IntrinsicColumnWidth(),
                              1: IntrinsicColumnWidth(),
                              2: IntrinsicColumnWidth(),
                              3: FlexColumnWidth(),
                            },
                            children: [
                              for (final entry in {'Annual': 'annualRemaining', 'MC': 'medicalRemaining'}.entries)
                                TableRow(children: [
                                  Text(entry.key, textAlign: TextAlign.end),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: const Text(':'),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text(
                                      '${leave[entry.value] ?? '—'}',
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Text('days'),
                                  ),
                                ]),
                            ],
                          ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => StaffLeaveApplicationPage(email: _email),
                    )),
                    );
                  },
                )),
                const SizedBox(width: 12),
                Expanded(child: _buildDashboardTile(
                  icon: Icons.menu_book_outlined,
                  title: 'Guidance Library',
                  accent: const Color(0xFF6D28D9),
                  detail: const Text('Inspection standards'),
                  onTap: () => setState(() => _showStandards = true),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTaskCard(IconData icon, String title, String detail) {
    return Card(
      margin: EdgeInsets.zero,
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFEFF6FF),
                foregroundColor: const Color(0xFF0C5AD2),
                child: Icon(icon),
              ),
              const SizedBox(height: 8),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTile({
    required IconData icon,
    required String title,
    required Widget detail,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Card(
      color: Colors.white,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: accent.withValues(alpha: 0.25)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              DefaultTextStyle.merge(
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.w800),
                child: detail,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Confirm Logout',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      size: 20,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              const Text(
                'Are you sure you want to log out of your ReByte Staff account?',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                ),
              ),

              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      child: const Text(
                        'CANCEL',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
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
                        backgroundColor: const Color(0xFFE11D48),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'LOGOUT',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
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
