import 'package:flutter/widgets.dart';

/// Lets signed-in pages pause session monitoring while a public flow (such as
/// password reset) is open above them in the navigator.
final RouteObserver<ModalRoute<dynamic>> appRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();
