import 'package:flutter/material.dart';

import '../decision_assistance_module/diagnostic_suite_page.dart';
import '../decision_assistance_module/diagnostic_exit_dialog.dart';
import '../decision_assistance_module/staff_diagnostic_scope.dart';
import '../staff_module/staff_home_page.dart';
import 'widgets/staff_app_bar_and_drawer.dart';

class StaffDeviceSelfTestPage extends StatefulWidget {
  final String deviceID;

  const StaffDeviceSelfTestPage({super.key, required this.deviceID});

  @override
  State<StaffDeviceSelfTestPage> createState() =>
      _StaffDeviceSelfTestPageState();
}

class _StaffDeviceSelfTestPageState extends State<StaffDeviceSelfTestPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _testNavigator = GlobalKey<NavigatorState>();
  bool _testInProgress = false;
  bool _confirmingExit = false;
  bool _saving = false;
  bool _saved = false;

  Future<Map<String, dynamic>> _save(Future<Map<String, dynamic>> Function() save) async {
    if (!mounted || _confirmingExit || _saving) return {'success': false};
    if (_saved) return {'success': true};
    _testInProgress = false;
    setState(() => _saving = true);
    final result = await save();
    if (!mounted) return {'success': false};
    setState(() {
      _saving = false;
      _saved = result['success'] == true;
    });
    return result;
  }

  Future<bool> _confirmExit() async {
    if (_saved) return true;
    if (_confirmingExit) return false;
    if (_saving) {
      StaffToast.show(
        context,
        'Please wait while the self-test is saved.',
        isError: true,
      );
      return false;
    }
    if (!_testInProgress) return true;
    _confirmingExit = true;
    try {
      return await showDiagnosticExitDialog(context, 'Self Test') == true;
    } finally {
      _confirmingExit = false;
    }
  }

  Future<void> _exit() async {
    if (!await _confirmExit() || !mounted) return;
    Navigator.pop(context, _saved);
  }

  Future<void> _openProfile() async {
    if (!await _confirmExit() || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const StaffHomePage(initialIndex: 3)),
      result: _saved,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        key: _scaffoldKey,
        appBar: _testInProgress
            ? null
            : StaffAppBar(
                scaffoldKey: _scaffoldKey,
                onProfilePressed: _openProfile,
              ),
        drawer: _testInProgress
            ? null
            : StaffDrawer(selectedIndex: 2, onBeforeNavigate: _confirmExit),
        bottomNavigationBar: _testInProgress
            ? null
            : StaffBottomNavBar(
                currentIndex: 2,
                onBeforeNavigate: _confirmExit,
              ),
        body: StaffDiagnosticScope(
          deviceID: widget.deviceID,
          saved: _saved,
          saving: _saving,
          exit: _exit,
          start: () => setState(() => _testInProgress = true),
          save: _save,
          child: Navigator(
            key: _testNavigator,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const DiagnosticSuitePage(isLoggedIn: true),
            ),
          ),
        ),
      ),
    );
  }
}
