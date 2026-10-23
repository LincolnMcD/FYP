import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../task_assignment_module/services/task_assignment_service.dart';
import '../task_assignment_module/staff_task_details_page.dart';
import 'staff_leave_application_page.dart';

class StaffSchedulePage extends StatefulWidget {
  final String? email;
  final String? staffID;
  final bool showBackButton;

  const StaffSchedulePage({
    super.key,
    this.email,
    this.staffID,
    this.showBackButton = false,
  });

  @override
  State<StaffSchedulePage> createState() => _StaffSchedulePageState();
}

class _StaffSchedulePageState extends State<StaffSchedulePage> {
  bool _isWeeklyView = false; // false: Daily, true: Weekly
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _allTasks = [];
  List<Map<String, dynamic>> _approvedLeaves = [];
  final Set<String> _expandedDays = {};

  @override
  void initState() {
    super.initState();
    _expandedDays.add(DateFormat('yyyy-MM-dd').format(_selectedDate));
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        TaskAssignmentService.fetchStaffTasks(
          email: widget.email,
          staffID: widget.staffID,
        ),
        TaskAssignmentService.fetchLeaveApplications(
          email: widget.email,
          staffID: widget.staffID,
        ),
      ]);

      if (mounted) {
        final tasks = results[0];
        final leaves = results[1];
        setState(() {
          _allTasks = tasks.where((t) {
            final s = (t['scheduleStatus']?.toString() ?? '').toLowerCase();
            return s != 'absent' && s != 'cancelled';
          }).toList();
          _approvedLeaves = leaves.where((l) {
            final st = (l['leaveStatus'] ?? '').toString().toUpperCase();
            return st == 'APPROVED';
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  DateTime? _parseLeaveDate(String? dStr) {
    if (dStr == null || dStr.trim().isEmpty) return null;
    try {
      final trimmed = dStr.trim();
      final parts = trimmed.split('/');
      if (parts.length == 3) {
        final d = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final y = int.parse(parts[2]);
        return DateTime(y, m, d);
      }
      final isoDate = DateTime.tryParse(trimmed);
      if (isoDate != null) {
        return DateTime(isoDate.year, isoDate.month, isoDate.day);
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _getApprovedLeaveForDate(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    for (final leave in _approvedLeaves) {
      final start = _parseLeaveDate(leave['startDate']?.toString());
      final end = _parseLeaveDate(leave['endDate']?.toString());
      if (start != null) {
        final normStart = DateTime(start.year, start.month, start.day);
        final normEnd = end != null ? DateTime(end.year, end.month, end.day) : normStart;
        if (!target.isBefore(normStart) && !target.isAfter(normEnd)) {
          return leave;
        }
      }
    }
    return null;
  }

  DateTime _parseScheduleDate(Map<String, dynamic> task) {
    final scheduleDateStr = task['scheduleDate']?.toString();
    final startTimeStr = task['scheduleStartTime']?.toString();
    if (scheduleDateStr != null && scheduleDateStr.isNotEmpty) {
      if (startTimeStr != null && startTimeStr.isNotEmpty) {
        final cleanTime = startTimeStr.length == 5 ? '$startTimeStr:00' : startTimeStr;
        final dt = DateTime.tryParse('${scheduleDateStr}T$cleanTime');
        if (dt != null) return dt;
      }
      final d = DateTime.tryParse(scheduleDateStr);
      if (d != null) return d;
    }
    return DateTime.now();
  }

  List<Map<String, dynamic>> get _dailyTasks {
    final selYear = _selectedDate.year;
    final selMonth = _selectedDate.month;
    final selDay = _selectedDate.day;

    final list = _allTasks.where((task) {
      final dt = _parseScheduleDate(task);
      return dt.year == selYear && dt.month == selMonth && dt.day == selDay;
    }).toList();

    list.sort((a, b) => _parseScheduleDate(a).compareTo(_parseScheduleDate(b)));
    return list;
  }

  List<DateTime> get _currentWeekDays {
    final weekday = _selectedDate.weekday; // 1: Mon, 7: Sun
    final monday = _selectedDate.subtract(Duration(days: weekday - 1));
    return List.generate(7, (index) => monday.add(Duration(days: index)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Row(
          children: [
            if (widget.showBackButton || Navigator.canPop(context)) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 24),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 14),
            ],
            const Text(
              'Schedule',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: IconButton(
              tooltip: 'Leave Applications',
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDBEAFE)),
                ),
                child: const Icon(
                  Icons.event_note_rounded,
                  color: Color(0xFF0C5AD2),
                  size: 20,
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StaffLeaveApplicationPage(
                      email: widget.email,
                      staffID: widget.staffID,
                    ),
                  ),
                ).then((_) => _loadTasks());
              },
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5AD2)))
          : RefreshIndicator(
              onRefresh: _loadTasks,
              color: const Color(0xFF0C5AD2),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isWeeklyView) ...[
                      _buildDateStrip(),
                      const SizedBox(height: 20),
                    ],
                    _buildModeToggle(),
                    const SizedBox(height: 24),
                    if (!_isWeeklyView)
                      _buildDailyTimeline()
                    else
                      _buildWeeklyAccordionList(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDateStrip() {
    final days = _currentWeekDays;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: days.map((day) {
        final isSelected = day.year == _selectedDate.year &&
            day.month == _selectedDate.month &&
            day.day == _selectedDate.day;
        final weekdayLabel = DateFormat('EEE').format(day).toUpperCase();
        final dayNum = DateFormat('d').format(day);
        final isLeaveDay = _getApprovedLeaveForDate(day) != null;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedDate = day;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF0C5AD2)
                  : (isLeaveDay ? const Color(0xFFFEF3C7) : Colors.transparent),
              borderRadius: BorderRadius.circular(22),
              border: isLeaveDay && !isSelected
                  ? Border.all(color: const Color(0xFFFDE68A))
                  : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF0C5AD2).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  weekdayLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white70
                        : (isLeaveDay ? const Color(0xFFB45309) : const Color(0xFF64748B)),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  dayNum,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isSelected
                        ? Colors.white
                        : (isLeaveDay ? const Color(0xFF92400E) : const Color(0xFF0F172A)),
                  ),
                ),
                if (isLeaveDay) ...[
                  const SizedBox(height: 3),
                  Icon(
                    Icons.beach_access_rounded,
                    size: 11,
                    color: isSelected ? Colors.white : const Color(0xFFD97706),
                  ),
                ] else if (isSelected) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isWeeklyView = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_isWeeklyView ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: !_isWeeklyView
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    'Daily',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: !_isWeeklyView ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isWeeklyView = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _isWeeklyView ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _isWeeklyView
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    'Weekly',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _isWeeklyView ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyLeaveBanner(Map<String, dynamic> leave) {
    final leaveType = leave['leaveType']?.toString() ?? 'Leave';
    final reason = leave['reason']?.toString();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFCD34D), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD97706).withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.beach_access_rounded,
              size: 48,
              color: Color(0xFFD97706),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'You are on leave',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF92400E),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$leaveType • Approved',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF92400E),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Enjoy your day off! No delivery tasks assigned for today.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF78350F).withValues(alpha: 0.8),
            ),
          ),
          if (reason != null && reason.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Reason: "$reason"',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: const Color(0xFF78350F).withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDailyTimeline() {
    final tasks = _dailyTasks;
    final approvedLeave = _getApprovedLeaveForDate(_selectedDate);

    if (approvedLeave != null) {
      return Column(
        children: [
          _buildDailyLeaveBanner(approvedLeave),
          if (tasks.isNotEmpty) ...[
            for (final task in tasks) ...[
              _buildTimelineSlot(task),
              const SizedBox(height: 18),
            ],
          ],
        ],
      );
    }

    if (tasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 60),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.calendar_today_outlined, size: 54, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(
              'No delivery tasks scheduled for ${DateFormat('MMMM d').format(_selectedDate)}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final task in tasks) ...[
          _buildTimelineSlot(task),
          const SizedBox(height: 18),
        ],
        _buildLunchBreakSlot(),
      ],
    );
  }

  Widget _buildTimelineSlot(Map<String, dynamic> task) {
    final startTimeStr = task['scheduleStartTime']?.toString() ?? '09:00';
    final endTimeStr = task['scheduleEndTime']?.toString() ?? '10:00';
    final status = (task['taskStatus']?.toString() ?? task['scheduleStatus']?.toString() ?? 'assigned').toLowerCase();

    final startParts = startTimeStr.split(':');
    final endParts = endTimeStr.split(':');
    int durationMins = 45;
    if (startParts.length == 2 && endParts.length == 2) {
      final sMins = (int.tryParse(startParts[0]) ?? 9) * 60 + (int.tryParse(startParts[1]) ?? 0);
      final eMins = (int.tryParse(endParts[0]) ?? 10) * 60 + (int.tryParse(endParts[1]) ?? 0);
      if (eMins > sMins) durationMins = eMins - sMins;
    }

    String durationText = '$durationMins m';
    if (durationMins >= 60) {
      final h = durationMins ~/ 60;
      final m = durationMins % 60;
      durationText = m > 0 ? '${h}h ${m}m' : '${h}h';
    }

    final isOngoing = status == 'shipping' || status == 'ongoing';
    final isDone = status == 'delivered' || status == 'completed';

    String badgeLabel = 'Upcoming';
    Color badgeBg = const Color(0xFFEFF6FF);
    Color badgeColor = const Color(0xFF2563EB);
    IconData badgeIcon = Icons.access_time_rounded;

    if (isOngoing) {
      badgeLabel = 'In Progress';
      badgeBg = const Color(0xFFFEF3C7);
      badgeColor = const Color(0xFFD97706);
      badgeIcon = Icons.local_shipping_outlined;
    } else if (isDone) {
      badgeLabel = 'Delivered';
      badgeBg = const Color(0xFFECFDF5);
      badgeColor = const Color(0xFF10B981);
      badgeIcon = Icons.check_circle_outline;
    }

    final deviceTitle = task['deviceModel']?.toString() ?? task['orderID']?.toString() ?? 'Delivery Inspection';
    final customerName = task['customerName']?.toString() ?? 'Customer';
    final destination = task['deliveryAddress']?.toString() ?? 'Penang Hub';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 55,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              startTimeStr,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0C5AD2),
              ),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StaffTaskDetailsPage(
                    task: task,
                    onTaskUpdated: _loadTasks,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isOngoing ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0),
                  width: isOngoing ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: badgeBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(badgeIcon, size: 12, color: badgeColor),
                            const SizedBox(width: 4),
                            Text(
                              badgeLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: badgeColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        durationText,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    deviceTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(
                        customerName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF0C5AD2)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          destination,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLunchBreakSlot() {
    return Row(
      children: [
        const SizedBox(
          width: 55,
          child: Text(
            '13:00',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDBEAFE)),
            ),
            alignment: Alignment.center,
            child: const Text(
              'Blocked: Lunch Break',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyAccordionList() {
    final days = _currentWeekDays;

    return Column(
      children: days.map((day) {
        final dateKey = DateFormat('yyyy-MM-dd').format(day);
        final dayTasks = _allTasks.where((t) {
          final dt = _parseScheduleDate(t);
          return dt.year == day.year && dt.month == day.month && dt.day == day.day;
        }).toList();

        final approvedLeave = _getApprovedLeaveForDate(day);
        final isLeaveDay = approvedLeave != null;
        final isExpanded = _expandedDays.contains(dateKey);
        final weekdayLabel = DateFormat('EEE').format(day).toUpperCase();
        final dayNum = DateFormat('d').format(day);
        final hasDelivery = dayTasks.any((t) {
          final raw = (t['taskType']?.toString() ?? t['taskTypeLabel']?.toString() ?? '').toLowerCase();
          return raw.contains('deliver') || (!raw.contains('inspect') && raw.isEmpty);
        });
        final hasInspection = dayTasks.any((t) {
          final raw = (t['taskType']?.toString() ?? t['taskTypeLabel']?.toString() ?? '').toLowerCase();
          return raw.contains('inspect');
        });

        final String dayTypeSubtitle;
        if (isLeaveDay) {
          dayTypeSubtitle = approvedLeave['leaveType']?.toString() ?? 'Approved Leave';
        } else if (dayTasks.isEmpty) {
          dayTypeSubtitle = 'No scheduled tasks';
        } else if (hasDelivery && hasInspection) {
          dayTypeSubtitle = 'Delivery, Inspection';
        } else if (hasInspection) {
          dayTypeSubtitle = 'Inspection';
        } else {
          dayTypeSubtitle = 'Delivery';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isExpanded
                  ? const Color(0xFFDBEAFE)
                  : (isLeaveDay ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  setState(() {
                    if (_expandedDays.contains(dateKey)) {
                      _expandedDays.remove(dateKey);
                    } else {
                      _expandedDays.add(dateKey);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 52,
                        decoration: BoxDecoration(
                          color: isExpanded
                              ? const Color(0xFF0C5AD2)
                              : (isLeaveDay ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              weekdayLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isExpanded
                                    ? Colors.white70
                                    : (isLeaveDay ? const Color(0xFFB45309) : const Color(0xFF64748B)),
                              ),
                            ),
                            Text(
                              dayNum,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: isExpanded
                                    ? Colors.white
                                    : (isLeaveDay ? const Color(0xFF92400E) : const Color(0xFF0F172A)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isLeaveDay)
                              Row(
                                children: [
                                  const Text(
                                    'OFF',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFD97706),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFFFDE68A)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.beach_access_rounded, size: 12, color: Color(0xFFD97706)),
                                        SizedBox(width: 4),
                                        Text(
                                          'On Leave',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFB45309),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                '${dayTasks.length} ${dayTasks.length == 1 ? "Task" : "Tasks"}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            const SizedBox(height: 3),
                            Text(
                              dayTypeSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isLeaveDay ? FontWeight.w600 : FontWeight.w500,
                                color: isLeaveDay ? const Color(0xFFB45309) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: const Color(0xFF64748B),
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded) ...[
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: isLeaveDay
                      ? Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFEF3C7),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.beach_access_rounded,
                                      color: Color(0xFFD97706),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'You are on leave (${approvedLeave['leaveType'] ?? 'Approved Leave'})',
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF92400E),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Enjoy your day off! No delivery tasks assigned.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: const Color(0xFFB45309).withValues(alpha: 0.9),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (dayTasks.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              for (final task in dayTasks) ...[
                                _buildTimelineSlot(task),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ],
                        )
                      : (dayTasks.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'No scheduled tasks for this day',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            )
                          : Column(
                              children: [
                                for (final task in dayTasks) ...[
                                  _buildTimelineSlot(task),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            )),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}
