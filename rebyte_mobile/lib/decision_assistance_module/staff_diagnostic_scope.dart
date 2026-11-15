import 'package:flutter/widgets.dart';

class StaffDiagnosticScope extends InheritedWidget {
  final String deviceID;
  final bool saved;
  final bool saving;
  final VoidCallback exit;
  final VoidCallback start;
  final Future<Map<String, dynamic>> Function(Future<Map<String, dynamic>> Function()) save;

  const StaffDiagnosticScope({
    super.key,
    required this.deviceID,
    required this.saved,
    required this.saving,
    required this.exit,
    required this.start,
    required this.save,
    required super.child,
  });

  static StaffDiagnosticScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StaffDiagnosticScope>();

  static bool requestExit(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<StaffDiagnosticScope>();
    if (scope == null) return false;
    scope.exit();
    return true;
  }

  @override
  bool updateShouldNotify(StaffDiagnosticScope oldWidget) =>
      saved != oldWidget.saved || saving != oldWidget.saving;
}
