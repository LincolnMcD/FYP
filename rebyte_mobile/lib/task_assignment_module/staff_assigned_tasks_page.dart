import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/task_assignment_service.dart';
import 'staff_navigation_page.dart';
import 'staff_task_details_page.dart';

class StaffAssignedTasksPage extends StatefulWidget {
  final String? email;
  final String? staffID;
  final bool showBackButton;

  const StaffAssignedTasksPage({
    super.key,
    this.email,
    this.staffID,
    this.showBackButton = false,
  });

  @override
  State<StaffAssignedTasksPage> createState() => _StaffAssignedTasksPageState();
}

class _StaffAssignedTasksPageState extends State<StaffAssignedTasksPage> {
  int _selectedTabIndex = 0; // 0: Assigned, 1: In Progress, 2: Completed
  bool _isLoading = true;
  List<Map<String, dynamic>> _tasks = [];
  final Set<String> _startingTaskIDs = {};
  String? _toast;
  bool _toastError = false;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  void _showToast(String message, [bool isError = false]) {
    setState(() {
      _toast = message;
      _toastError = isError;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _loadTasks() async {
    setState(() => _isLoading = true);
    final tasks = await TaskAssignmentService.fetchStaffTasks(
      email: widget.email,
      staffID: widget.staffID,
    );
    if (mounted) {
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    }
  }

  DateTime _getTaskScheduleDateTime(Map<String, dynamic> task) {
    final startTimeStr = task['scheduleStartTime']?.toString();
    final scheduleDateStr = task['scheduleDate']?.toString();
    DateTime? dt;
    if (startTimeStr != null && startTimeStr.isNotEmpty) {
      if (startTimeStr.contains('-') || startTimeStr.contains('T')) {
        dt = DateTime.tryParse(startTimeStr);
      } else if (scheduleDateStr != null && scheduleDateStr.isNotEmpty) {
        final cleanTime = startTimeStr.length == 5 ? '$startTimeStr:00' : startTimeStr;
        dt = DateTime.tryParse('${scheduleDateStr}T$cleanTime');
      }
    }
    dt ??= (scheduleDateStr != null ? DateTime.tryParse(scheduleDateStr) : null);
    dt ??= DateTime.tryParse(task['createdAt']?.toString() ?? '');
    return dt ?? DateTime(2099);
  }

  List<Map<String, dynamic>> get _assignedTasks {
    final list = _tasks.where((t) {
      final s = (t['scheduleStatus']?.toString() ?? '').toLowerCase();
      final ts = (t['taskStatus']?.toString() ?? '').toLowerCase();
      if (s == 'absent' || s == 'rejected' || s == 'cancelled' || ts == 'rejected' || ts == 'cancelled' || ts == 'unassigned') {
        return false;
      }
      return s == 'assigned' || ts == 'packaging';
    }).toList();

    // Sort from earliest to latest task
    list.sort((a, b) => _getTaskScheduleDateTime(a).compareTo(_getTaskScheduleDateTime(b)));
    return list;
  }

  List<Map<String, dynamic>> get _inProgressTasks {
    final list = _tasks.where((t) {
      final s = (t['scheduleStatus']?.toString() ?? '').toLowerCase();
      final ts = (t['taskStatus']?.toString() ?? '').toLowerCase();
      if (s == 'absent' || s == 'rejected' || s == 'cancelled' || ts == 'rejected' || ts == 'cancelled' || ts == 'unassigned') {
        return false;
      }
      return s == 'ongoing' || ts == 'shipping' || ts == 'in progress';
    }).toList();

    // Sort from earliest to latest task
    list.sort((a, b) => _getTaskScheduleDateTime(a).compareTo(_getTaskScheduleDateTime(b)));
    return list;
  }

  List<Map<String, dynamic>> get _completedTasks {
    final list = _tasks.where((t) {
      final s = (t['scheduleStatus']?.toString() ?? '').toLowerCase();
      final ts = (t['taskStatus']?.toString() ?? '').toLowerCase();
      return s == 'completed' || ts == 'delivered';
    }).toList();

    // Sort completed tasks from earliest to latest task
    list.sort((a, b) => _getTaskScheduleDateTime(a).compareTo(_getTaskScheduleDateTime(b)));

    return list;
  }

  List<Map<String, dynamic>> get _currentTabTasks {
    switch (_selectedTabIndex) {
      case 0:
        return _assignedTasks;
      case 1:
        return _inProgressTasks;
      case 2:
        return _completedTasks;
      default:
        return _assignedTasks;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                // Header: Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    children: [
                      if (widget.showBackButton) ...[
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: const Icon(Icons.arrow_back, size: 20, color: Color(0xFF0F172A)),
                          ),
                        ),
                      ],
                      const Text(
                        'Assigned Tasks',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tab bar: Assigned (badge), In Progress (badge), Completed
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Expanded(child: _buildTabItem(0, 'Assigned', _assignedTasks.length)),
                      Expanded(child: _buildTabItem(1, 'In Progress', _inProgressTasks.length)),
                      Expanded(child: _buildTabItem(2, 'Completed', 0)),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFFE2E8F0), thickness: 1, height: 1),

                // Task list or loading
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF0C5AD2)))
                      : RefreshIndicator(
                          onRefresh: _loadTasks,
                          color: const Color(0xFF0C5AD2),
                          child: _currentTabTasks.isEmpty
                              ? ListView(
                                  children: [
                                    SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                                    Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                                          const SizedBox(height: 12),
                                          Text(
                                            'No ${_selectedTabIndex == 0 ? "assigned" : _selectedTabIndex == 1 ? "in-progress" : "completed"} tasks found',
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  itemCount: _currentTabTasks.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                                  itemBuilder: (context, index) {
                                    return _buildTaskCard(_currentTabTasks[index]);
                                  },
                                ),
                        ),
                ),
              ],
            ),
          ),
          if (_toast != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: _toastError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _toastError ? Icons.error_outline : Icons.check_circle_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _toast!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, String label, int badgeCount) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                      color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
                    ),
                  ),
                ),
                if (badgeCount > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badgeCount.toString(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            height: 3.0,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF0C5AD2) : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final orderID = task['orderID']?.toString() ?? 'RB-9901';
    final taskID = task['taskID']?.toString() ?? '';
    final scheduleID = task['scheduleID']?.toString() ?? '';
    final customerName = task['customerName']?.toString() ?? 'Sarah J.';
    final address = task['deliveryAddress']?.toString() ?? 'Central Hub';
    final startTimeStr = task['scheduleStartTime']?.toString();
    final taskStatus = task['taskStatus']?.toString() ?? 'Packaging';
    final scheduleStatus = task['scheduleStatus']?.toString() ?? 'assigned';

    final scheduleDateStr = task['scheduleDate']?.toString();
    final endTimeStr = task['scheduleEndTime']?.toString();

    DateTime? scheduleDate;
    if (startTimeStr != null && startTimeStr.isNotEmpty) {
      if (startTimeStr.contains('-') || startTimeStr.contains('T')) {
        scheduleDate = DateTime.tryParse(startTimeStr);
      } else if (scheduleDateStr != null && scheduleDateStr.isNotEmpty) {
        // e.g. "2026-10-20T09:00:00"
        final cleanTime = startTimeStr.length == 5 ? '$startTimeStr:00' : startTimeStr;
        scheduleDate = DateTime.tryParse('${scheduleDateStr}T$cleanTime');
      }
    }
    scheduleDate ??= (scheduleDateStr != null ? DateTime.tryParse(scheduleDateStr) : null) ?? DateTime.now();

    // Format Start Time (and End Time if available)
    String timeFormatted = DateFormat('h:mm a').format(scheduleDate);
    if (endTimeStr != null && endTimeStr.isNotEmpty && !endTimeStr.contains('T')) {
      try {
        final cleanEndTime = endTimeStr.length == 5 ? '$endTimeStr:00' : endTimeStr;
        final endDt = DateTime.tryParse('${scheduleDateStr ?? DateFormat('yyyy-MM-dd').format(scheduleDate)}T$cleanEndTime');
        if (endDt != null) {
          timeFormatted = '${DateFormat('h:mm a').format(scheduleDate)} - ${DateFormat('h:mm a').format(endDt)}';
        }
      } catch (_) {}
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final taskDay = DateTime(scheduleDate.year, scheduleDate.month, scheduleDate.day);
    final dayDiff = taskDay.difference(today).inDays;

    final String dayLabel;
    if (dayDiff == 0) {
      dayLabel = 'Today';
    } else if (dayDiff == 1) {
      dayLabel = 'Tomorrow';
    } else {
      dayLabel = DateFormat('MMM d, yyyy').format(scheduleDate); // e.g. Oct 22, 2026
    }

    // Items info
    final items = task['items'] as List? ?? [];
    String itemTitle = 'Delivery Package';
    String itemSpecs = 'Order Delivery';
    String? imageUrl;
    if (items.isNotEmpty && items[0] is Map) {
      final first = items[0] as Map;
      itemTitle = '${first['brand'] ?? ''} ${first['model'] ?? ''}'.trim();
      if (itemTitle.isEmpty) itemTitle = 'Delivery Package';
      itemSpecs = first['storage']?.toString() ?? 'Good Condition';
      imageUrl = first['imageUrl']?.toString();
    }

    final completedAtRaw = task['completedAt']?.toString() ?? '';
    String completedAtLabel = '';
    if (completedAtRaw.isNotEmpty) {
      final dt = DateTime.tryParse(completedAtRaw);
      if (dt != null) {
        completedAtLabel = DateFormat('d MMM yyyy, h:mm a').format(dt.toLocal());
      }
    }
    final proofOfDeliveryUrl = task['proofOfDeliveryUrl']?.toString() ?? '';

    final lowerStatus = taskStatus.toLowerCase();
    final lowerSched = scheduleStatus.toLowerCase();
    final isAssigned = lowerSched == 'assigned' || lowerStatus == 'packaging';
    final isShipping = lowerSched == 'ongoing' || lowerStatus == 'shipping' || lowerStatus == 'in progress';
    final isCompleted = lowerSched == 'completed' || lowerStatus == 'delivered';

    void navigateToDetails() async {
      final res = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StaffTaskDetailsPage(
            task: task,
            onTaskUpdated: _loadTasks,
          ),
        ),
      );
      if (res != null) {
        _loadTasks();
        if (mounted) {
          if (res is Map && res['rejected'] == true) {
            _showToast(res['message']?.toString() ?? 'Delivery task is rejected', false);
          } else {
            _showToast(res is String ? res : 'Delivery completed successfully!');
          }
        }
      }
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: navigateToDetails,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Order Badge & Time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  orderID.startsWith('#') ? orderID : '#$orderID',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0C5AD2),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 12, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        dayLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0C5AD2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time_filled, size: 13, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        timeFormatted,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Product & Client Row
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: imageUrl != null && imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.devices, color: Color(0xFF94A3B8)),
                          )
                        : const Icon(Icons.devices, color: Color(0xFF94A3B8)),
                  ),
                  if (items.length > 1)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${items.length}x',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            itemTitle,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (items.length > 1) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Text(
                              '${items.length} Products',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      items.length > 1
                          ? '👤 $customerName • ${items.length} items to deliver'
                          : '👤 $customerName • $itemSpecs',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Address Pill
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFF0C5AD2), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    address,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // Action Buttons: Start Inspection/Delivery & Details (only for non-completed tasks)
          if (!isCompleted) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Builder(
                    builder: (context) {
                      final isStarting = _startingTaskIDs.contains(taskID);

                      return ElevatedButton(
                        onPressed: isStarting
                            ? null
                            : () async {
                                if (isAssigned) {
                                  setState(() {
                                    _startingTaskIDs.add(taskID);
                                  });

                                  try {
                                    // Move to Shipping (In Progress) and transition to Navigation Page
                                    await TaskAssignmentService.updateTaskStatus(
                                      taskID: taskID,
                                      orderID: orderID,
                                      scheduleID: scheduleID,
                                      status: 'Shipping',
                                    );
                                    _loadTasks();

                                    final ongoingTask = Map<String, dynamic>.from(task);
                                    ongoingTask['taskStatus'] = 'Shipping';
                                    ongoingTask['scheduleStatus'] = 'ongoing';

                                    if (!mounted || !context.mounted) return;
                                    final res = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => StaffNavigationPage(
                                          task: ongoingTask,
                                          onTaskUpdated: _loadTasks,
                                        ),
                                      ),
                                    );
                                    _loadTasks();
                                    if (res != null && mounted) {
                                      _showToast(res is String ? res : 'Delivery completed successfully!');
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      _showToast('Failed to start delivery: $e', true);
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        _startingTaskIDs.remove(taskID);
                                      });
                                    }
                                  }
                                } else if (isShipping) {
                                  // Already in shipping -> open Navigation Page directly
                                  if (!mounted) return;
                                  final res = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => StaffNavigationPage(
                                        task: task,
                                        onTaskUpdated: _loadTasks,
                                      ),
                                    ),
                                  );
                                  _loadTasks();
                                  if (res != null && mounted) {
                                    _showToast(res is String ? res : 'Delivery completed successfully!');
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isStarting
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF0C5AD2),
                          disabledBackgroundColor: const Color(0xFF94A3B8),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isStarting
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Starting...',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                isAssigned
                                    ? 'Start Delivery'
                                    : 'Continue Navigation',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: navigateToDetails,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      completedAtLabel.isNotEmpty
                          ? 'Delivered: $completedAtLabel'
                          : 'Delivered successfully',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ),
                  if (proofOfDeliveryUrl.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.camera_alt_rounded, size: 12, color: Color(0xFF16A34A)),
                          SizedBox(width: 3),
                          Text(
                            'Proof',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF16A34A)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    ),
    ),
    );
  }
}
