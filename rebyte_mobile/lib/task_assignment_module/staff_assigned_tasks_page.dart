import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/task_assignment_service.dart';
import 'staff_task_details_page.dart';

class StaffAssignedTasksPage extends StatefulWidget {
  final String? email;
  final String? staffID;

  const StaffAssignedTasksPage({
    super.key,
    this.email,
    this.staffID,
  });

  @override
  State<StaffAssignedTasksPage> createState() => _StaffAssignedTasksPageState();
}

class _StaffAssignedTasksPageState extends State<StaffAssignedTasksPage> {
  int _selectedTabIndex = 0; // 0: Assigned, 1: In Progress, 2: Completed
  bool _isLoading = true;
  List<Map<String, dynamic>> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
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

  List<Map<String, dynamic>> get _assignedTasks {
    return _tasks.where((t) {
      final s = (t['scheduleStatus']?.toString() ?? '').toLowerCase();
      final ts = (t['taskStatus']?.toString() ?? '').toLowerCase();
      return s == 'assigned' || ts == 'packaging';
    }).toList();
  }

  List<Map<String, dynamic>> get _inProgressTasks {
    return _tasks.where((t) {
      final s = (t['scheduleStatus']?.toString() ?? '').toLowerCase();
      final ts = (t['taskStatus']?.toString() ?? '').toLowerCase();
      return s == 'ongoing' || ts == 'shipping' || ts == 'in progress';
    }).toList();
  }

  List<Map<String, dynamic>> get _completedTasks {
    return _tasks.where((t) {
      final s = (t['scheduleStatus']?.toString() ?? '').toLowerCase();
      final ts = (t['taskStatus']?.toString() ?? '').toLowerCase();
      return s == 'completed' || ts == 'delivered';
    }).toList();
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
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            // Header: Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                children: const [
                  Text(
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
                  _buildTabItem(0, 'Assigned', _assignedTasks.length),
                  const SizedBox(width: 12),
                  _buildTabItem(1, 'In Progress', _inProgressTasks.length),
                  const SizedBox(width: 12),
                  _buildTabItem(2, 'Completed', 0),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
    );
  }

  Widget _buildTabItem(int index, String label, int badgeCount) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFF64748B),
                  ),
                ),
                if (badgeCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0C5AD2) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badgeCount.toString(),
                      style: TextStyle(
                        fontSize: 11,
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
            height: 2.5,
            width: 70,
            color: isSelected ? const Color(0xFF0C5AD2) : Colors.transparent,
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

    final isAssigned = scheduleStatus == 'assigned' || taskStatus == 'Packaging';
    final isShipping = scheduleStatus == 'ongoing' || taskStatus == 'Shipping';

    void navigateToDetails() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StaffTaskDetailsPage(
            task: task,
            onTaskUpdated: _loadTasks,
          ),
        ),
      );
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      itemTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '👤 $customerName • $itemSpecs',
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
          const SizedBox(height: 14),

          // Action Buttons: Start Inspection/Delivery & Details
          Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () async {
                    if (isAssigned) {
                      // Move to Shipping (In Progress)
                      await TaskAssignmentService.updateTaskStatus(
                        taskID: taskID,
                        orderID: orderID,
                        scheduleID: scheduleID,
                        status: 'Shipping',
                      );
                      _loadTasks();
                    } else if (isShipping) {
                      // Mark Delivered (Completed)
                      await TaskAssignmentService.updateTaskStatus(
                        taskID: taskID,
                        orderID: orderID,
                        scheduleID: scheduleID,
                        status: 'Delivered',
                      );
                      _loadTasks();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0C5AD2),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    isAssigned
                        ? 'Start Delivery'
                        : isShipping
                            ? 'Complete Delivery'
                            : 'Completed',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
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
        ],
      ),
    ),
    ),
    );
  }
}
