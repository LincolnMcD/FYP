import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../staff_module/staff_home_page.dart';
import 'perform_device_inspection_page.dart';
import 'services/task_assignment_service.dart';
import 'services/delivery_socket_service.dart';
import 'widgets/proof_of_delivery_dialog.dart';

class StaffNavigationPage extends StatefulWidget {
  final Map<String, dynamic> task;
  final VoidCallback? onTaskUpdated;

  const StaffNavigationPage({
    super.key,
    required this.task,
    this.onTaskUpdated,
  });

  @override
  State<StaffNavigationPage> createState() => _StaffNavigationPageState();
}

class _StaffNavigationPageState extends State<StaffNavigationPage> {
  InAppWebViewController? _webViewController;
  bool _isMapLoading = true;
  bool _isActionLoading = false;
  late Map<String, dynamic> _task;
  final DeliverySocketService _socketService = DeliverySocketService();

  // Fallback origin: ReByte Central Hub
  static const double companyLat = 5.453240417145323;
  static const double companyLng = 100.2848625551094;
  static const double _maneuverPassBufferM = 6;

  double _staffOriginLat = companyLat;
  double _staffOriginLng = companyLng;
  double _currentHeading = 0.0;
  bool _hasStaffGpsOrigin = false;

  late double _destLat;
  late double _destLng;
  late String _address;
  late String _customerName;
  late String _orderID;
  late String _taskID;
  late String _scheduleID;

  int _estDurationMinutes = 15;
  double _estDistanceKm = 4.2;
  double _totalRouteDistanceM = 0;
  double _totalRouteDurationSec = 0;
  double _routeSpeedMps = 7.5;
  List<List<double>> _routePoints = [];
  List<double> _routeCumulativeDistancesM = [];
  double _routeProgressM = 0;

  // In-App Turn-By-Turn Navigation State
  bool _isNavigating = false;
  bool _voiceGuidanceEnabled = true;
  String _lastSpokenInstruction = '';
  DateTime? _lastSpeechTime;
  bool _hasSpokenAdvanceNotice = false;
  bool _hasSpokenTurnPrompt = false;
  bool _hasSpokenArrival = false;
  bool _isRecalculatingRoute = false;
  int _offRouteConsecutiveCount = 0;
  static const MethodChannel _ttsChannel = MethodChannel(
    'com.tarumt.rebyte/hardware',
  );
  StreamSubscription<Position>? _positionStreamSub;
  List<Map<String, dynamic>> _osrmSteps = [];
  int _currentStepIndex = 0;
  String _currentInstruction = 'Head towards destination';
  String _currentManeuverModifier = 'straight';
  double _distanceToNextManeuverM = 0;
  DateTime? _lastRouteRecalcTime;
  Timer? _speechQueueTimer;
  String? _pendingSpeechText;
  DateTime? _lastGpsBackendSyncTime;

  String _formatDistanceSpeech(double distanceM) {
    final roundM = (distanceM / 10).round() * 10;
    if (roundM >= 1000) {
      final km = (roundM / 1000).toStringAsFixed(1);
      return '$km kilometers';
    }
    return '$roundM meters';
  }

  void _speakVoiceInstruction(String text, {bool force = false}) {
    if (!_voiceGuidanceEnabled || text.trim().isEmpty) return;
    final cleanText = text.trim();
    final now = DateTime.now();

    if (!force &&
        cleanText.toLowerCase() == _lastSpokenInstruction.toLowerCase()) {
      return;
    }

    final elapsedMs = _lastSpeechTime == null
        ? 99999
        : now.difference(_lastSpeechTime!).inMilliseconds;
    const minIntervalMs = 2000;

    if (force || elapsedMs >= minIntervalMs) {
      _speechQueueTimer?.cancel();
      _speechQueueTimer = null;
      _pendingSpeechText = null;
      _executeSpeak(cleanText);
    } else {
      // Queue the speech so the voice follows the updated text as soon as the previous utterance completes
      _pendingSpeechText = cleanText;
      _speechQueueTimer?.cancel();
      final waitMs = minIntervalMs - elapsedMs + 100;
      _speechQueueTimer = Timer(Duration(milliseconds: waitMs), () {
        if (_pendingSpeechText != null && mounted) {
          final toSpeak = _pendingSpeechText!;
          _pendingSpeechText = null;
          _executeSpeak(toSpeak);
        }
      });
    }
  }

  void _executeSpeak(String text) async {
    _lastSpeechTime = DateTime.now();
    _lastSpokenInstruction = text;
    try {
      await _ttsChannel.invokeMethod('speakText', {'text': text});
    } catch (e) {
      debugPrint('TTS navigation voice error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _task = Map<String, dynamic>.from(widget.task);
    _destLat = (_task['destinationLat'] as num?)?.toDouble() ?? 5.4045;
    _destLng = (_task['destinationLng'] as num?)?.toDouble() ?? 100.3333;
    _address =
        _task['deliveryAddress']?.toString() ?? '123 Tech Lane, Kuala Lumpur';
    _customerName = _task['customerName']?.toString() ?? 'Customer';
    _taskID = _task['taskID']?.toString() ?? '';
    _scheduleID = _task['scheduleID']?.toString() ?? '';

    // Prioritize tradeInRequestID for trade-in / inspection / collection tasks so room IDs match customer perfectly
    final rawTradeIn = _task['tradeInRequestID']?.toString() ?? '';
    final rawOrder = _task['orderID']?.toString() ?? '';
    final rawAppt = _task['appointmentID']?.toString() ?? '';
    if (rawTradeIn.isNotEmpty) {
      _orderID = rawTradeIn.replaceAll('#', '').trim();
    } else if (rawOrder.isNotEmpty && rawOrder != 'RB-9901') {
      _orderID = rawOrder.replaceAll('#', '').trim();
    } else if (rawAppt.isNotEmpty) {
      _orderID = rawAppt.replaceAll('#', '').trim();
    } else {
      _orderID = rawOrder.isNotEmpty ? rawOrder.replaceAll('#', '').trim() : _taskID.replaceAll('TSK-', '').trim();
    }

    _initNavigationRoute();
  }

  @override
  void dispose() {
    _speechQueueTimer?.cancel();
    _speechQueueTimer = null;
    _stopLiveGpsTracking();
    _socketService.leaveRoom(_orderID);
    _socketService.dispose();
    super.dispose();
  }

  /// 1. Acquire current Staff GPS location and calculate route to customer destination via OSRM
  Future<void> _initNavigationRoute() async {
    // Connect to Socket.IO delivery room: delivery:<orderID>
    _socketService.connect(
      orderID: _orderID,
      tradeInRequestID: _task['tradeInRequestID']?.toString(),
      taskID: _taskID,
      appointmentID: _task['appointmentID']?.toString(),
      role: 'staff',
    );

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );
          _staffOriginLat = pos.latitude;
          _staffOriginLng = pos.longitude;
          _hasStaffGpsOrigin = true;
          if (pos.heading >= 0) {
            _currentHeading = pos.heading;
          }
          // Immediately sync staff's real-time GPS location via Socket.IO
          _socketService.sendLocation(
            orderID: _orderID,
            tradeInRequestID: _task['tradeInRequestID']?.toString(),
            taskID: _taskID,
            appointmentID: _task['appointmentID']?.toString(),
            lat: pos.latitude,
            lng: pos.longitude,
            heading: _currentHeading,
          );
          // Also sync to backend
          TaskAssignmentService.updateStaffLiveLocation(
            orderID: _orderID,
            taskID: _taskID,
            staffID: _task['staffID']?.toString(),
            lat: pos.latitude,
            lng: pos.longitude,
            heading: _currentHeading,
          );
        }
      }
    } catch (e) {
      debugPrint('Staff origin GPS fetch error: $e');
    }

    // Load OSRM driving route with full steps from current staff location to destination
    await _loadOsrmRoute();

    // Start live GPS tracking immediately so the vehicle pointer moves in real-time as staff moves
    _startLiveGpsTracking();
  }

  /// Fetch full driving route and maneuver steps using OSRM
  Future<void> _loadOsrmRoute({bool isRecalculating = false}) async {
    if (_isRecalculatingRoute && isRecalculating) return;

    final fromLat = _staffOriginLat;
    final fromLng = _staffOriginLng;

    if (isRecalculating) {
      _isRecalculatingRoute = true;
    }

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$fromLng,$fromLat;$_destLng,$_destLat?overview=full&geometries=geojson&steps=true',
      );
      final res = await http
          .get(
            url,
            headers: {'User-Agent': 'ReByte-App/1.0 (Mobile Delivery Module)'},
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final r = data['routes'][0];
          final durSec = (r['duration'] as num?)?.toDouble() ?? 0;
          final distM = (r['distance'] as num?)?.toDouble() ?? 0;
          final coords = (r['geometry']?['coordinates'] as List?) ?? [];

          final pts = coords.map<List<double>>((c) {
            final lng = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            return [lat, lng];
          }).toList();
          final routeCumulativeDistances = _buildRouteCumulativeDistances(pts);
          final routeProgress = _findProgressOnRoute(
            _staffOriginLat,
            _staffOriginLng,
            pts,
            routeCumulativeDistances,
          );

          // Parse navigation steps
          List<Map<String, dynamic>> parsedSteps = [];
          double stepRouteDistanceM = 0;
          if (r['legs'] != null && (r['legs'] as List).isNotEmpty) {
            final leg = r['legs'][0];
            final steps = (leg['steps'] as List?) ?? [];
            for (final s in steps) {
              final maneuver = s['maneuver'] as Map<String, dynamic>? ?? {};
              final location = (maneuver['location'] as List?) ?? [];
              final type = maneuver['type']?.toString() ?? 'turn';
              final modifier = maneuver['modifier']?.toString() ?? '';
              final streetName = s['name']?.toString() ?? '';
              final distance = (s['distance'] as num?)?.toDouble() ?? 0;

              parsedSteps.add({
                'type': type,
                'modifier': modifier.isNotEmpty ? modifier : type,
                'streetName': streetName,
                'instruction': _formatStepInstruction(
                  type,
                  modifier,
                  streetName,
                ),
                'distance': distance,
                'routeDistanceM': stepRouteDistanceM,
                'locationLat': location.length > 1
                    ? (location[1] as num).toDouble()
                    : 0.0,
                'locationLng': location.isNotEmpty
                    ? (location[0] as num).toDouble()
                    : 0.0,
              });
              stepRouteDistanceM += distance;
            }
          }

          if (mounted) {
            final targetIdx = _findUpcomingStepIndex(
              routeProgress,
              parsedSteps,
            );
            final activeStep =
                parsedSteps.isNotEmpty && targetIdx < parsedSteps.length
                ? parsedSteps[targetIdx]
                : null;

            double initialManeuverDist = 0;
            if (activeStep != null) {
              final maneuverRouteDistance =
                  (activeStep['routeDistanceM'] as num?)?.toDouble() ??
                  routeProgress;
              initialManeuverDist = math
                  .max(0.0, maneuverRouteDistance - routeProgress)
                  .toDouble();
            }

            _totalRouteDistanceM = distM;
            _totalRouteDurationSec = durSec;
            if (distM > 0 && durSec > 0) {
              _routeSpeedMps = distM / durSec;
            }

            final remainingM = math.max(0.0, distM - routeProgress);
            final remainingRatio = distM > 0 ? (remainingM / distM).clamp(0.0, 1.0) : 1.0;
            final remainingSec = durSec * remainingRatio;
            final initialMins = math.max(1, (remainingSec / 60).ceil());

            setState(() {
              _estDurationMinutes = initialMins;
              _estDistanceKm = double.parse((distM / 1000).toStringAsFixed(1));
              _routePoints = pts;
              _routeCumulativeDistancesM = routeCumulativeDistances;
              _routeProgressM = routeProgress;
              _osrmSteps = parsedSteps;
              _currentStepIndex = targetIdx;
              _hasSpokenAdvanceNotice = false;
              _hasSpokenTurnPrompt = false;
              _hasSpokenArrival = false;
              if (activeStep != null) {
                final instruction =
                    activeStep['instruction'] ?? 'Head towards destination';
                _currentInstruction = instruction;
                _currentManeuverModifier = activeStep['modifier'] ?? 'straight';
                _distanceToNextManeuverM = initialManeuverDist;

                if (_isNavigating) {
                  final distStr = _formatDistanceSpeech(initialManeuverDist);
                  _speakVoiceInstruction(
                    'In $distStr, $instruction',
                    force: true,
                  );
                }
              }
            });
            _updateMapRoute();
          }
          _isRecalculatingRoute = false;
          return;
        }
      }
    } catch (e) {
      debugPrint('OSRM routing error: $e');
    } finally {
      _isRecalculatingRoute = false;
    }

    // Fallback: ONLY apply direct line points if we have NO existing route at all.
    // Never wipe out an active route on a temporary network delay!
    if (mounted && _routePoints.isEmpty) {
      setState(() {
        _routePoints = [
          [fromLat, fromLng],
          [_destLat, _destLng],
        ];
        _currentInstruction = 'Proceed to destination';
        _currentManeuverModifier = 'straight';
      });
      _updateMapRoute();
    }
  }

  String _formatStepInstruction(
    String type,
    String modifier,
    String streetName,
  ) {
    final street = streetName.trim().isNotEmpty ? ' onto $streetName' : '';
    switch (type) {
      case 'depart':
        return 'Head out${street.isNotEmpty ? street : ''}';
      case 'arrive':
        return streetName.trim().isNotEmpty
            ? 'Continue on $streetName'
            : 'Continue straight';
      case 'roundabout':
      case 'rotary':
        return 'At the roundabout, take the exit$street';
      case 'fork':
        return modifier.contains('left')
            ? 'Keep left at the fork$street'
            : 'Keep right at the fork$street';
      case 'end of road':
        return modifier.contains('left')
            ? 'At the end of road, turn left$street'
            : 'At the end of road, turn right$street';
      case 'merge':
        return 'Merge$street';
      case 'turn':
      default:
        if (modifier == 'slight left') {
          return 'Slight left$street';
        } else if (modifier == 'sharp left') {
          return 'Sharp left$street';
        } else if (modifier.contains('left')) {
          return 'Turn left$street';
        } else if (modifier == 'slight right') {
          return 'Slight right$street';
        } else if (modifier == 'sharp right') {
          return 'Sharp right$street';
        } else if (modifier.contains('right')) {
          return 'Turn right$street';
        } else if (modifier == 'straight') {
          return streetName.isNotEmpty
              ? 'Continue onto $streetName'
              : 'Continue straight';
        } else if (modifier == 'uturn') {
          return 'Make a U-turn$street';
        }
        return streetName.isNotEmpty
            ? 'Continue on $streetName'
            : 'Continue along the route';
    }
  }

  void _updateMapRoute() {
    if (_webViewController != null && _routePoints.isNotEmpty) {
      final jsonPoints = jsonEncode(_routePoints);
      _webViewController?.evaluateJavascript(
        source:
            '''
        updateRoute($jsonPoints, $_staffOriginLat, $_staffOriginLng, $_destLat, $_destLng, ${_hasStaffGpsOrigin ? "'Your Current Location'" : "'ReByte Central Hub'"}, $_currentHeading);
      ''',
      );
    }
  }

  List<double> _buildRouteCumulativeDistances(List<List<double>> points) {
    if (points.isEmpty) return const [];
    final distances = <double>[0];
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      distances.add(
        distances.last +
            Geolocator.distanceBetween(
              previous[0],
              previous[1],
              current[0],
              current[1],
            ),
      );
    }
    return distances;
  }

  double _findProgressOnRoute(
    double lat,
    double lng,
    List<List<double>> points,
    List<double> cumulativeDistances, {
    double? previousProgress,
  }) {
    if (points.isEmpty || cumulativeDistances.length != points.length) return 0;

    // Search locally after the first fix. This prevents a nearby parallel road
    // or a later crossing from jumping the navigation forward to another route segment.
    final lowerBound = previousProgress == null
        ? 0
        : math.max(0, previousProgress - 25);
    final upperBound = previousProgress == null
        ? double.infinity
        : previousProgress + 300;
    var nearestDistance = double.infinity;
    var nearestProgress = previousProgress ?? 0;
    void considerSegment(int i) {
      final start = points[i];
      final end = points[i + 1];
      final referenceLat = ((start[0] + end[0] + lat) / 3) * math.pi / 180;
      const metersPerDegree = 111320.0;
      final longitudeScale = math.cos(referenceLat);
      final startX = start[1] * metersPerDegree * longitudeScale;
      final startY = start[0] * metersPerDegree;
      final endX = end[1] * metersPerDegree * longitudeScale;
      final endY = end[0] * metersPerDegree;
      final positionX = lng * metersPerDegree * longitudeScale;
      final positionY = lat * metersPerDegree;
      final segmentX = endX - startX;
      final segmentY = endY - startY;
      final segmentLengthSquared = segmentX * segmentX + segmentY * segmentY;
      final fraction = segmentLengthSquared == 0
          ? 0.0
          : (((positionX - startX) * segmentX +
                        (positionY - startY) * segmentY) /
                    segmentLengthSquared)
                .clamp(0.0, 1.0)
                .toDouble();
      final projectedLat = start[0] + (end[0] - start[0]) * fraction;
      final projectedLng = start[1] + (end[1] - start[1]) * fraction;
      final distance = Geolocator.distanceBetween(
        lat,
        lng,
        projectedLat,
        projectedLng,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestProgress =
            cumulativeDistances[i] +
            (cumulativeDistances[i + 1] - cumulativeDistances[i]) * fraction;
      }
    }

    void searchRoute({required bool localOnly}) {
      for (var i = 0; i < points.length - 1; i++) {
        if (localOnly) {
          final segmentStart = cumulativeDistances[i];
          final segmentEnd = cumulativeDistances[i + 1];
          if (segmentEnd < lowerBound || segmentStart > upperBound) continue;
        }
        considerSegment(i);
      }
    }

    searchRoute(localOnly: previousProgress != null);

    // The route may have been loaded before the user started navigation, or a
    // GPS update may jump farther than the local look-ahead window. If its
    // nearest local point is far away, rematch the complete route once rather
    // than leaving progress stuck at the old maneuver forever.
    if (nearestDistance > 80) {
      nearestDistance = double.infinity;
      searchRoute(localOnly: false);
    }
    if (previousProgress != null && nearestDistance > 80) {
      return previousProgress;
    }
    if (previousProgress != null) {
      return math.max(previousProgress, nearestProgress);
    }
    return nearestProgress;
  }

  int _findUpcomingStepIndex(
    double routeProgressM,
    List<Map<String, dynamic>> steps,
  ) {
    if (steps.isEmpty) return 0;
    if (steps.length == 1) return 0;

    // OSRM puts each maneuver at the beginning of its step. Keep a small grace
    // distance around the corner so GPS noise does not skip the turn instruction.
    for (var i = 1; i < steps.length; i++) {
      final maneuverDistance =
          (steps[i]['routeDistanceM'] as num?)?.toDouble() ?? 0;
      if (maneuverDistance >= routeProgressM - _maneuverPassBufferM) return i;
    }
    return steps.length - 1;
  }

  double _distanceAlongRouteToStep(Map<String, dynamic> step) {
    final maneuverDistance =
        (step['routeDistanceM'] as num?)?.toDouble() ?? _routeProgressM;
    return math.max(0.0, maneuverDistance - _routeProgressM).toDouble();
  }

  void _syncStepPreviewToCurrentPosition(double curLat, double curLng) {
    if (_osrmSteps.isEmpty) return;

    _routeProgressM = _findProgressOnRoute(
      curLat,
      curLng,
      _routePoints,
      _routeCumulativeDistancesM,
      previousProgress: _routeProgressM,
    );
    final syncIdx = _findUpcomingStepIndex(_routeProgressM, _osrmSteps);
    final step = _osrmSteps[syncIdx];
    setState(() {
      _currentStepIndex = syncIdx;
      _currentInstruction =
          step['instruction'] ?? 'Proceed towards destination';
      _currentManeuverModifier = step['modifier'] ?? 'straight';
      _distanceToNextManeuverM = _distanceAlongRouteToStep(step);
    });
  }

  /// Start pure in-app navigation mode using OSRM
  void _startInAppNavigation() async {
    // 1. Immediately fetch freshest GPS position to eliminate any initial lag
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      ).timeout(const Duration(seconds: 2));
      _staffOriginLat = pos.latitude;
      _staffOriginLng = pos.longitude;
      if (pos.heading >= 0) _currentHeading = pos.heading;
      _hasStaffGpsOrigin = true;
    } catch (e) {
      debugPrint('Fast GPS fix error on start nav: $e');
    }

    // 2. Match the current GPS position to the route in sequence, then select
    // the first maneuver ahead. Geographic-nearest-corner matching can pick a
    // later turn across a block or on a parallel road.
    _routeProgressM = _findProgressOnRoute(
      _staffOriginLat,
      _staffOriginLng,
      _routePoints,
      _routeCumulativeDistancesM,
      previousProgress: _routeProgressM,
    );
    final syncIdx = _findUpcomingStepIndex(_routeProgressM, _osrmSteps);

    _currentStepIndex = syncIdx;

    if (_osrmSteps.isNotEmpty && syncIdx < _osrmSteps.length) {
      final step = _osrmSteps[syncIdx];
      _currentInstruction =
          step['instruction'] ?? 'Proceed towards destination';
      _currentManeuverModifier = step['modifier'] ?? 'straight';
      _distanceToNextManeuverM = _distanceAlongRouteToStep(step);
    }

    setState(() {
      _isNavigating = true;
      _hasSpokenAdvanceNotice = false;
      _hasSpokenTurnPrompt = false;
      _hasSpokenArrival = false;
    });

    // 3. Immediately reflect the latest GPS position on map, center camera and zoom in
    _webViewController?.evaluateJavascript(
      source:
          '''
      setVehiclePosition($_staffOriginLat, $_staffOriginLng, $_currentHeading, true, true);
      centerOnStaff(18);
    ''',
    );

    // 4. Ensure live GPS tracking stream is running
    if (_positionStreamSub == null) {
      _startLiveGpsTracking();
    }

    // 5. Emit audible sound message for the first upcoming navigation instruction
    if (_osrmSteps.isNotEmpty && _currentStepIndex < _osrmSteps.length) {
      final targetStep = _osrmSteps[_currentStepIndex];
      final targetDist = _distanceToNextManeuverM;
      final roundDist = (targetDist / 10).round() * 10;
      final distStr = roundDist >= 1000
          ? '${(roundDist / 1000).toStringAsFixed(1)} kilometers'
          : '$roundDist meters';

      _speakVoiceInstruction(
        'Starting navigation. In $distStr, ${targetStep['instruction']}',
        force: true,
      );
    } else if (_currentInstruction.isNotEmpty) {
      _speakVoiceInstruction(
        'Starting navigation. $_currentInstruction',
        force: true,
      );
    }

    // 6. Only recalculate route if we don't have route points yet
    if (_routePoints.isEmpty) {
      _loadOsrmRoute(isRecalculating: false);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('In-app navigation started with live voice guidance.'),
        backgroundColor: Color(0xFF0C5AD2),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _stopInAppNavigation() {
    setState(() {
      _isNavigating = false;
    });
    // Keep GPS tracking running so the pointer continues moving on the map as staff moves
    _webViewController?.evaluateJavascript(source: 'fitFullRoute();');
  }

  void _startLiveGpsTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2, // Smooth real-time update every 2 meters
      );

      _positionStreamSub?.cancel();
      _positionStreamSub =
          Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).listen((Position position) {
            if (!mounted) return;

            double heading = position.heading;
            // If device heading is invalid or stationary, derive bearing from previous coordinate
            if (heading < 0 || heading == 0.0) {
              heading = _calculateBearing(
                _staffOriginLat,
                _staffOriginLng,
                position.latitude,
                position.longitude,
              );
            }

            setState(() {
              _staffOriginLat = position.latitude;
              _staffOriginLng = position.longitude;
              _currentHeading = heading;
              _hasStaffGpsOrigin = true;
              _updateRemainingRoadDistanceAndDuration(
                position.latitude,
                position.longitude,
              );
            });

            // Update leaflet vehicle pin position, rotation, camera follow, and trim traveled path
            _webViewController?.evaluateJavascript(
              source:
                  '''
          setVehiclePosition(${position.latitude}, ${position.longitude}, $heading, ${_isNavigating ? 'true' : 'false'}, ${_isNavigating ? 'true' : 'false'});
        ''',
            );

            // Update progress along steps if actively navigating, or keep step in sync if viewing map
            if (_isNavigating) {
              _updateNavigationProgress(position.latitude, position.longitude);
            } else {
              _syncStepPreviewToCurrentPosition(
                position.latitude,
                position.longitude,
              );
            }

            // Emit live staff GPS location, distance, and duration to Socket.IO room in real-time
            _socketService.sendLocation(
              orderID: _orderID,
              tradeInRequestID: _task['tradeInRequestID']?.toString(),
              taskID: _taskID,
              appointmentID: _task['appointmentID']?.toString(),
              lat: position.latitude,
              lng: position.longitude,
              heading: heading,
              speed: position.speed,
              estimatedDistanceKm: _estDistanceKm,
              estimatedDurationMinutes: _estDurationMinutes,
            );

            // Sync live staff GPS location to backend every 3 seconds as persistence
            final now = DateTime.now();
            if (_lastGpsBackendSyncTime == null ||
                now.difference(_lastGpsBackendSyncTime!).inSeconds >= 3) {
              _lastGpsBackendSyncTime = now;
              TaskAssignmentService.updateStaffLiveLocation(
                orderID: _orderID,
                taskID: _taskID,
                staffID: _task['staffID']?.toString(),
                lat: position.latitude,
                lng: position.longitude,
                heading: heading,
                estimatedDistanceKm: _estDistanceKm,
                estimatedDurationMinutes: _estDurationMinutes,
              );
            }
          });
    } catch (e) {
      debugPrint('Live GPS stream error: $e');
    }
  }

  void _stopLiveGpsTracking() {
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
  }

  double _calculateBearing(double lat1, double lng1, double lat2, double lng2) {
    if (lat1 == lat2 && lng1 == lng2) return _currentHeading;
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final deltaLambda = (lng2 - lng1) * math.pi / 180;
    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    final theta = math.atan2(y, x);
    return (theta * 180 / math.pi + 360) % 360;
  }

  /// Dynamically calculate remaining road distance and duration along the OSRM route
  void _updateRemainingRoadDistanceAndDuration(double curLat, double curLng) {
    final straightDistM = Geolocator.distanceBetween(
      curLat,
      curLng,
      _destLat,
      _destLng,
    );

    // Curbside arrival threshold: <= 25m
    if (straightDistM <= 25) {
      _estDistanceKm = 0.0;
      _estDurationMinutes = 0;
      return;
    }

    double remainingRoadM;
    if (_routeCumulativeDistancesM.isNotEmpty && _routeCumulativeDistancesM.last > 0) {
      final totalM = _routeCumulativeDistancesM.last;
      // Remaining distance along the actual OSRM road polyline
      remainingRoadM = math.max(0.0, totalM - _routeProgressM);
      // Sanity check: road distance cannot be less than straight-line distance
      if (remainingRoadM < straightDistM) {
        remainingRoadM = straightDistM * 1.25;
      }
    } else {
      // Urban road winding factor (approx 1.25x - 1.3x straight line)
      remainingRoadM = straightDistM * 1.25;
    }

    final distKm = double.parse((remainingRoadM / 1000).toStringAsFixed(1));

    // Proportionate countdown of remaining route duration using .ceil()
    // Exactly matches the calculation used in CustomerDeliveryTrackingPage
    final totalDist = _totalRouteDistanceM > 0
        ? _totalRouteDistanceM
        : (_routeCumulativeDistancesM.isNotEmpty ? _routeCumulativeDistancesM.last : 0.0);

    final remainingRatio = totalDist > 0 ? (remainingRoadM / totalDist).clamp(0.0, 1.0) : 1.0;
    final remainingSec = _totalRouteDurationSec > 0
        ? (_totalRouteDurationSec * remainingRatio)
        : (remainingRoadM / (_routeSpeedMps > 2.0 ? _routeSpeedMps : 7.5));
    final durMins = math.max(1, (remainingSec / 60).ceil());

    _estDistanceKm = distKm;
    _estDurationMinutes = durMins;
  }

  void _advanceToStep(int newStepIndex, double distToDest) {
    if (newStepIndex >= _osrmSteps.length) {
      newStepIndex = _osrmSteps.length - 1;
    }
    if (newStepIndex == _currentStepIndex && _distanceToNextManeuverM > 0) {
      return;
    }

    _currentStepIndex = newStepIndex;
    _hasSpokenAdvanceNotice = false;
    _hasSpokenTurnPrompt = false;

    final step = _osrmSteps[_currentStepIndex];
    final dist = _distanceAlongRouteToStep(step);

    final instructionText = step['instruction'] ?? 'Continue along route';
    final streetName = (step['streetName'] as String?)?.trim() ?? '';
    final modifier = step['modifier']?.toString() ?? 'straight';

    setState(() {
      _currentInstruction = instructionText;
      _currentManeuverModifier = modifier;
      _distanceToNextManeuverM = dist;
      _updateRemainingRoadDistanceAndDuration(
        _staffOriginLat,
        _staffOriginLng,
      );
    });

    HapticFeedback.lightImpact();

    // Voice announcement for the newly activated step
    final distStr = _formatDistanceSpeech(dist);
    final isArriveStep =
        step['type'] == 'arrive' || _currentStepIndex >= _osrmSteps.length - 1;

    if (isArriveStep) {
      _speakVoiceInstruction(
        streetName.isNotEmpty
            ? 'Continue on $streetName for $distStr'
            : 'Continue straight for $distStr',
        force: true,
      );
    } else if (dist <= 60) {
      // Immediate prompt for rapid consecutive turns (e.g. right then left in close proximity)
      _speakVoiceInstruction('Then, $instructionText', force: true);
      _hasSpokenAdvanceNotice = true;
      _hasSpokenTurnPrompt = true;
    } else if (dist <= 120) {
      _speakVoiceInstruction('Then in $distStr, $instructionText', force: true);
      _hasSpokenAdvanceNotice = true;
    } else {
      if (streetName.isNotEmpty &&
          (modifier == 'straight' || step['type'] == 'continue')) {
        _speakVoiceInstruction(
          'Continue onto $streetName for $distStr',
          force: true,
        );
      } else {
        _speakVoiceInstruction('In $distStr, $instructionText', force: true);
      }
      if (dist <= 250) {
        _hasSpokenAdvanceNotice = true;
      }
    }
  }

  void _updateNavigationProgress(double curLat, double curLng) {
    if (_osrmSteps.isEmpty) return;

    _routeProgressM = _findProgressOnRoute(
      curLat,
      curLng,
      _routePoints,
      _routeCumulativeDistancesM,
      previousProgress: _routeProgressM,
    );

    // Remaining distance to destination
    final distToDest = Geolocator.distanceBetween(
      curLat,
      curLng,
      _destLat,
      _destLng,
    );

    // 1. Destination Arrived (Curbside/roadside outside house: <= 25m on final stretch, <= 15m if turns remain)
    final isFinalStretch = _currentStepIndex >= _osrmSteps.length - 1;
    final arrivalThreshold = isFinalStretch ? 25.0 : 15.0;

    if (distToDest <= arrivalThreshold) {
      if (!_hasSpokenArrival) {
        _hasSpokenArrival = true;
        _speakVoiceInstruction(
          'Destination arrived. You have arrived at your destination.',
          force: true,
        );
        HapticFeedback.heavyImpact();
      }
      setState(() {
        _currentInstruction = 'Destination arrived';
        _currentManeuverModifier = 'arrive';
        _distanceToNextManeuverM = 0;
        _estDurationMinutes = 0;
        _estDistanceKm = 0;
      });
      return;
    }

    // Process upcoming maneuver step
    if (_currentStepIndex < _osrmSteps.length) {
      final currentStep = _osrmSteps[_currentStepIndex];
      final maneuverRouteDistance =
          (currentStep['routeDistanceM'] as num?)?.toDouble() ??
          _routeProgressM;
      final distToTarget = math
          .max(0.0, maneuverRouteDistance - _routeProgressM)
          .toDouble();

      // Advance only after route-matched progress has carried the vehicle past
      // the maneuver point. Straight-line proximity can trigger early at nearby
      // corners that are not yet reachable on the road.
      final bool hasPassedTurn =
          _routeProgressM > maneuverRouteDistance + _maneuverPassBufferM;

      if (hasPassedTurn && _currentStepIndex < _osrmSteps.length - 1) {
        // Step completed! Advance to the next step
        _advanceToStep(_currentStepIndex + 1, distToDest);
      } else {
        // Approaching target maneuver: Live update distance count-down
        setState(() {
          _distanceToNextManeuverM = distToTarget;
          _updateRemainingRoadDistanceAndDuration(curLat, curLng);
        });

        // Advance notice when 65m - 250m away from the upcoming turn
        if (distToTarget <= 250 &&
            distToTarget > 65 &&
            !_hasSpokenAdvanceNotice) {
          _hasSpokenAdvanceNotice = true;
          final distStr = _formatDistanceSpeech(distToTarget);
          _speakVoiceInstruction('In $distStr, ${currentStep['instruction']}');
        }

        // Timely pre-turn prompt when approaching 15m - 60m away (gives driver time to turn)
        if (distToTarget <= 60 && distToTarget > 15 && !_hasSpokenTurnPrompt) {
          _hasSpokenTurnPrompt = true;
          _speakVoiceInstruction(currentStep['instruction'] ?? 'Turn');
        }
      }
    }

    // Auto recalculate route if staff drifts significantly off route (> 80m for consecutive readings)
    _checkAndRecalculateRouteIfOffTrack(curLat, curLng);
  }

  void _checkAndRecalculateRouteIfOffTrack(double curLat, double curLng) {
    if (_routePoints.isEmpty || _isRecalculatingRoute) return;

    // Do NOT recalculate driving route if already within 150m of destination!
    final distToDest = Geolocator.distanceBetween(
      curLat,
      curLng,
      _destLat,
      _destLng,
    );
    if (distToDest < 150) return;

    final now = DateTime.now();
    if (_lastRouteRecalcTime != null &&
        now.difference(_lastRouteRecalcTime!).inSeconds < 20) {
      return; // Rate limit recalculation to at most once every 20 seconds
    }

    double minDistance = double.infinity;
    for (final pt in _routePoints) {
      final d = Geolocator.distanceBetween(curLat, curLng, pt[0], pt[1]);
      if (d < minDistance) {
        minDistance = d;
      }
    }

    // Require off-track distance > 80m for at least 4 consecutive GPS checks (~8 seconds)
    // to filter out transient GPS jitter or GPS drift under bridges/overpasses
    if (minDistance > 80) {
      _offRouteConsecutiveCount++;
      if (_offRouteConsecutiveCount >= 4) {
        _lastRouteRecalcTime = now;
        _offRouteConsecutiveCount = 0;
        debugPrint(
          'Vehicle confirmed off-route by ${minDistance.toStringAsFixed(1)}m, recalculating via OSRM...',
        );
        _loadOsrmRoute(isRecalculating: true);
      }
    } else {
      _offRouteConsecutiveCount = 0;
    }
  }

  IconData _getManeuverIcon(String modifier) {
    final lower = modifier.toLowerCase();
    if (lower.contains('slight left')) {
      return Icons.turn_slight_left;
    } else if (lower.contains('slight right')) {
      return Icons.turn_slight_right;
    } else if (lower.contains('sharp left')) {
      return Icons.turn_sharp_left;
    } else if (lower.contains('sharp right')) {
      return Icons.turn_sharp_right;
    } else if (lower.contains('left')) {
      return Icons.turn_left;
    } else if (lower.contains('right')) {
      return Icons.turn_right;
    } else if (lower.contains('uturn')) {
      return Icons.u_turn_left;
    } else if (lower.contains('roundabout') || lower.contains('rotary')) {
      return Icons.roundabout_left;
    } else if (lower.contains('arrive')) {
      return Icons.place;
    }
    return Icons.straight;
  }

  /// Verify staff live GPS is at customer destination
  Future<bool> _verifyStaffAtDestination() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please enable GPS / Location services to complete delivery.',
            ),
          ),
        );
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission is required to verify destination arrival.',
              ),
            ),
          );
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission permanently denied. Please allow in app settings.',
            ),
          ),
        );
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final distanceMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _destLat,
        _destLng,
      );

      // GPS Verification: Must be within 65m of customer delivery destination
      if (distanceMeters <= 65) {
        return true;
      } else {
        if (!mounted) return false;

        // Accurate road distance matching the navigation overview (e.g. 3.4 km instead of straight line air distance)
        double displayDistanceM;
        if (_routeCumulativeDistancesM.isNotEmpty && _routeCumulativeDistancesM.last > 0) {
          final remainingRoadM = math.max(0.0, _routeCumulativeDistancesM.last - _routeProgressM);
          displayDistanceM = remainingRoadM >= distanceMeters ? remainingRoadM : distanceMeters;
        } else if (_estDistanceKm > 0) {
          displayDistanceM = _estDistanceKm * 1000;
        } else {
          displayDistanceM = distanceMeters * 1.25;
        }

        final distStr = displayDistanceM >= 1000
            ? '${(displayDistanceM / 1000).toStringAsFixed(1)} km'
            : '${displayDistanceM.round()} meters';

        final String actionText = _isInspectTask
            ? 'start this inspection'
            : (_isCollectTask ? 'complete this collection' : 'complete this delivery');
        final String instructionText = _isInspectTask
            ? 'Please proceed along the route and arrive within 65 meters of the destination before starting the inspection.'
            : (_isCollectTask
                ? 'Please proceed along the route and arrive within 65 meters of the destination before recording proof of collection and completing the task.'
                : 'Please proceed along the route and arrive within 65 meters of the destination before recording proof of delivery and completing the order.');

        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: const [
                Icon(
                  Icons.location_off_rounded,
                  color: Color(0xFFDC2626),
                  size: 24,
                ),
                SizedBox(width: 8),
                Text(
                  'Location Mismatch',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'You cannot $actionText yet because your current GPS location is $distStr away from the customer destination.',
                  textAlign: TextAlign.justify,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  instructionText,
                  textAlign: TextAlign.justify,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0C5AD2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
        return false;
      }
    } catch (e) {
      debugPrint('Geolocator verification error: $e');
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to read live GPS location: $e')),
      );
      return false;
    }
  }

  Future<void> _handleCompleteDelivery() async {
    setState(() => _isActionLoading = true);

    final isAtLocation = await _verifyStaffAtDestination();
    if (!isAtLocation) {
      setState(() => _isActionLoading = false);
      return;
    }

    setState(() => _isActionLoading = false);

    // Prompt Proof of Delivery Dialog asking staff to take a photo of the package
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProofOfDeliveryDialog(
        orderID: _orderID,
        taskID: _taskID,
        scheduleID: _scheduleID,
        customerName: _customerName,
        deliveryAddress: _address,
      ),
    );

    if (result != null && result['success'] == true && mounted) {
      _stopLiveGpsTracking();
      _socketService.emitDeliveryCompleted(
        orderID: _orderID,
        proofOfDeliveryUrl: result['proofOfDeliveryUrl']?.toString(),
      );
      _socketService.leaveRoom(_orderID);
      _socketService.dispose();
      widget.onTaskUpdated?.call();
      Navigator.pop(context, 'Delivery completed with proof recorded!');
    }
  }

  bool get _isInspectTask {
    final t = (_task['taskType']?.toString() ?? _task['type']?.toString() ?? '').toLowerCase();
    return t.contains('inspect');
  }

  bool get _isCollectTask {
    final t = (_task['taskType']?.toString() ?? _task['type']?.toString() ?? '').toLowerCase();
    return t.contains('collect');
  }

  Future<void> _handleStartInspection() async {
    setState(() => _isActionLoading = true);
    final isAtLocation = await _verifyStaffAtDestination();
    if (!isAtLocation) {
      if (mounted) setState(() => _isActionLoading = false);
      return;
    }
    if (mounted) setState(() => _isActionLoading = false);

    _stopLiveGpsTracking();
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PerformDeviceInspectionPage(
          task: _task,
          onTaskUpdated: widget.onTaskUpdated,
        ),
      ),
    );
    if (res != null && mounted) {
      widget.onTaskUpdated?.call();
      Navigator.pop(context, res);
    }
  }

  Future<void> _handleCompleteCollection() async {
    setState(() => _isActionLoading = true);
    final isAtLocation = await _verifyStaffAtDestination();
    if (!isAtLocation) {
      if (mounted) setState(() => _isActionLoading = false);
      return;
    }
    if (mounted) setState(() => _isActionLoading = false);

    // Prompt Proof of Collection Dialog asking staff to take a photo of the collected device
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProofOfDeliveryDialog(
        orderID: _orderID,
        taskID: _taskID,
        scheduleID: _scheduleID,
        customerName: _customerName,
        deliveryAddress: _address,
        isCollect: true,
      ),
    );

    if (result != null && result['success'] == true && mounted) {
      _stopLiveGpsTracking();
      widget.onTaskUpdated?.call();
      Navigator.pop(context, 'Collection completed with proof recorded!');
    }
  }

  void _onBottomNavTapped(int index) {
    _stopLiveGpsTracking();
    if (index == 2) {
      // Already on Tasks module
      Navigator.pop(context);
    } else {
      // Navigate to StaffHomePage with initialIndex
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => StaffHomePage(initialIndex: index)),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = _address.split(',');
    final addressLine1 = parts.isNotEmpty ? parts[0].trim() : _address;
    final addressLine2 = parts.length > 1
        ? parts.sublist(1).join(',').trim()
        : '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _isNavigating
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              centerTitle: false,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
                onPressed: () {
                  _stopLiveGpsTracking();
                  Navigator.pop(context);
                },
              ),
              title: const Text(
                'Task Details',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
      body: Stack(
        children: [
          // 1. Full height interactive Route Map
          Positioned.fill(
            child: Stack(
              children: [
                InAppWebView(
                  initialData: InAppWebViewInitialData(
                    data: _buildNavigationMapHtml(
                      _staffOriginLat,
                      _staffOriginLng,
                      _destLat,
                      _destLng,
                    ),
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    supportZoom: true,
                    disableHorizontalScroll: false,
                    disableVerticalScroll: false,
                  ),
                  onWebViewCreated: (controller) {
                    _webViewController = controller;
                  },
                  onLoadStop: (controller, url) {
                    setState(() => _isMapLoading = false);
                    _updateMapRoute();
                  },
                ),
                if (_isMapLoading)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF0C5AD2),
                      strokeWidth: 2.5,
                    ),
                  ),
              ],
            ),
          ),

          // 2. Turn-by-Turn Instruction Banner (Active while Navigating)
          if (_isNavigating)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Maneuver Icon + Distance Countdown Badge + Action Controls (Voice Toggle & Exit Nav)
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C5AD2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _getManeuverIcon(_currentManeuverModifier),
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _distanceToNextManeuverM > 1000
                                ? 'In ${(_distanceToNextManeuverM / 1000).toStringAsFixed(1)} km'
                                : 'In ${_distanceToNextManeuverM.toStringAsFixed(0)} m',
                            style: const TextStyle(
                              color: Color(0xFF93C5FD),
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        // Voice Guidance Mute / Unmute Button
                        InkWell(
                          onTap: () {
                            setState(() {
                              _voiceGuidanceEnabled = !_voiceGuidanceEnabled;
                            });
                            if (_voiceGuidanceEnabled) {
                              _speakVoiceInstruction(
                                _currentInstruction,
                                force: true,
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _voiceGuidanceEnabled
                                  ? const Color(
                                      0xFF0C5AD2,
                                    ).withValues(alpha: 0.35)
                                  : const Color(
                                      0xFF475569,
                                    ).withValues(alpha: 0.4),
                              border: Border.all(
                                color: _voiceGuidanceEnabled
                                    ? const Color(
                                        0xFF60A5FA,
                                      ).withValues(alpha: 0.4)
                                    : const Color(
                                        0xFF94A3B8,
                                      ).withValues(alpha: 0.3),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _voiceGuidanceEnabled
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_off_rounded,
                              color: _voiceGuidanceEnabled
                                  ? const Color(0xFF93C5FD)
                                  : const Color(0xFF94A3B8),
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Quick Exit Nav button
                        InkWell(
                          onTap: _stopInAppNavigation,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFEF4444,
                              ).withValues(alpha: 0.18),
                              border: Border.all(
                                color: const Color(
                                  0xFFFCA5A5,
                                ).withValues(alpha: 0.4),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.close,
                                  color: Color(0xFFFCA5A5),
                                  size: 15,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'Exit',
                                  style: TextStyle(
                                    color: Color(0xFFFCA5A5),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Row 2: Full-Width Instruction Text (100% visible, fully readable without truncation)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _currentInstruction,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          height: 1.3,
                          letterSpacing: 0.1,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Map Control Floating Buttons (Recenter & Fit Overview) - Positioned comfortably above the bottom sheet
          Positioned(
            right: 16,
            bottom: 255,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'recenter_gps',
                  tooltip: 'Center on my location',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0C5AD2),
                  elevation: 4,
                  onPressed: () {
                    _webViewController?.evaluateJavascript(
                      source: 'centerOnStaff(18);',
                    );
                  },
                  child: const Icon(Icons.my_location, size: 20),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'fit_route',
                  tooltip: 'View entire route',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0F172A),
                  elevation: 4,
                  onPressed: () {
                    _webViewController?.evaluateJavascript(
                      source: 'fitFullRoute();',
                    );
                  },
                  child: const Icon(Icons.zoom_out_map, size: 20),
                ),
              ],
            ),
          ),

          // 3. Bottom Sliding Destination & Controls Card
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pull Pill indicator
                    Center(
                      child: Container(
                        width: 44,
                        height: 4.5,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),

                    // Destination Title & ETA Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_customerName.isNotEmpty &&
                                  _customerName != 'Customer') ...[
                                Text(
                                  _customerName,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0C5AD2),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                addressLine1,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                  height: 1.2,
                                ),
                              ),
                              if (addressLine2.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  addressLine2,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                  maxLines: 3,
                                  softWrap: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _estDurationMinutes == 0
                                    ? const Color(0xFFDCFCE7)
                                    : (_estDurationMinutes <= 1
                                          ? const Color(0xFFFEF3C7)
                                          : const Color(0xFFDBEAFE)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _estDurationMinutes == 0
                                    ? 'ARRIVED'
                                    : (_estDurationMinutes <= 1
                                          ? '< 1 MIN'
                                          : '$_estDurationMinutes MINS'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: _estDurationMinutes == 0
                                      ? const Color(0xFF16A34A)
                                      : (_estDurationMinutes <= 1
                                            ? const Color(0xFFB45309)
                                            : const Color(0xFF1D4ED8)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _estDistanceKm < 0.1
                                  ? '${(_estDistanceKm * 1000).round()} m'
                                  : '$_estDistanceKm km',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _estDurationMinutes == 0
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Action Buttons Row: [In-App Start/Stop Navigation] and [Complete Delivery]
                    Row(
                      children: [
                        // In-App Navigation Toggle Button (OSRM directly inside app)
                        Expanded(
                          flex: 1,
                          child: OutlinedButton.icon(
                            onPressed: _isNavigating
                                ? _stopInAppNavigation
                                : _startInAppNavigation,
                            icon: Icon(
                              _isNavigating
                                  ? Icons.pause_circle_outline
                                  : Icons.navigation_rounded,
                              color: _isNavigating
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF0C5AD2),
                              size: 18,
                            ),
                            label: Text(
                              _isNavigating
                                  ? 'Stop Navigation'
                                  : 'Start Navigation',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: _isNavigating
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF0C5AD2),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(
                                color: _isNavigating
                                    ? const Color(0xFFFCA5A5)
                                    : const Color(0xFF0C5AD2),
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Complete Deliver / Start Inspection / Complete Collect Button
                        Expanded(
                          flex: 1,
                          child: ElevatedButton(
                            onPressed: _isActionLoading
                                ? null
                                : () {
                                    if (_isInspectTask) {
                                      _handleStartInspection();
                                    } else if (_isCollectTask) {
                                      _handleCompleteCollection();
                                    } else {
                                      _handleCompleteDelivery();
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0C5AD2),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isActionLoading)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  Icon(
                                    _isInspectTask
                                        ? Icons.assignment_turned_in_outlined
                                        : Icons.check_circle_outline,
                                    color: Colors.white,
                                    size: 17,
                                  ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    _isInspectTask
                                        ? 'Start Inspection'
                                        : _isCollectTask
                                            ? 'Complete Collect'
                                            : 'Complete Deliver',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
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
      ),
      bottomNavigationBar: _isNavigating
          ? null
          : Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                currentIndex: 2, // Highlight Tasks tab
                onTap: _onBottomNavTapped,
                selectedItemColor: const Color(0xFF0C5AD2),
                unselectedItemColor: const Color(0xFF64748B),
                selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.grid_view_rounded, size: 24),
                    label: 'Dashboard',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.calendar_today_rounded, size: 24),
                    label: 'Schedule',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.assignment_outlined, size: 24),
                    label: 'Tasks',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline, size: 24),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
    );
  }

  String _buildNavigationMapHtml(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng,
  ) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    body, html { margin: 0; padding: 0; width: 100%; height: 100%; background: #F8FAFC; overflow: hidden; }
    #map { width: 100%; height: 100%; }

    /* Modern Vehicle / Staff Marker with directional arrow */
    .vehicle-marker-container {
      width: 42px;
      height: 42px;
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: transform 0.25s ease-out;
    }
    .vehicle-pulse {
      position: absolute;
      width: 38px;
      height: 38px;
      border-radius: 50%;
      background: rgba(12, 90, 210, 0.25);
      animation: pulse 1.8s infinite ease-out;
    }
    .vehicle-core {
      position: relative;
      width: 28px;
      height: 28px;
      background: #0C5AD2;
      border: 3px solid #FFFFFF;
      border-radius: 50%;
      box-shadow: 0 4px 10px rgba(0, 0, 0, 0.35);
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .vehicle-arrow {
      width: 0;
      height: 0;
      border-left: 5px solid transparent;
      border-right: 5px solid transparent;
      border-bottom: 9px solid #FFFFFF;
      margin-top: -2px;
    }

    /* Destination Pin */
    .dest-pin {
      width: 32px;
      height: 32px;
      background: #E11D48;
      border: 3px solid #FFFFFF;
      border-radius: 50% 50% 50% 0;
      transform: rotate(-45deg);
      box-shadow: 0 4px 10px rgba(0,0,0,0.3);
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .dest-pin::after {
      content: '';
      width: 10px;
      height: 10px;
      background: #FFFFFF;
      border-radius: 50%;
      position: absolute;
      transform: rotate(45deg);
    }

    @keyframes pulse {
      0% { transform: scale(0.8); opacity: 0.9; }
      100% { transform: scale(1.6); opacity: 0; }
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var map = L.map('map', {
      zoomControl: false,
      attributionControl: false
    });

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19
    }).addTo(map);

    var vehicleHeading = 0;
    var currentStaffLat = $fromLat;
    var currentStaffLng = $fromLng;

    var staffIcon = L.divIcon({
      className: '',
      html: '<div id="vehiclePin" class="vehicle-marker-container" style="transform: rotate(0deg);"><div class="vehicle-pulse"></div><div class="vehicle-core"><div class="vehicle-arrow"></div></div></div>',
      iconSize: [42, 42],
      iconAnchor: [21, 21]
    });

    var destIcon = L.divIcon({
      className: '',
      html: '<div class="dest-pin"></div>',
      iconSize: [32, 32],
      iconAnchor: [16, 32]
    });

    var staffMarker = L.marker([$fromLat, $fromLng], { icon: staffIcon }).addTo(map).bindPopup('Your Location');
    var destMarker = L.marker([$toLat, $toLng], { icon: destIcon }).addTo(map).bindPopup('Customer Destination');

    var routePolyline = null;
    var currentRoutePoints = [];
    var allBounds = L.latLngBounds([[$fromLat, $fromLng], [$toLat, $toLng]]);
    map.fitBounds(allBounds, { padding: [60, 60] });

    function updateRoute(points, fromLat, fromLng, toLat, toLng, fromLabel, heading) {
      currentStaffLat = fromLat;
      currentStaffLng = fromLng;
      if (heading !== undefined) vehicleHeading = heading;

      if (staffMarker) {
        staffMarker.setLatLng([fromLat, fromLng]);
        staffMarker.bindPopup(fromLabel || 'Your Location');
      }
      if (destMarker) {
        destMarker.setLatLng([toLat, toLng]);
      }
      if (routePolyline) {
        map.removeLayer(routePolyline);
      }
      if (points && points.length > 0) {
        currentRoutePoints = points.slice();
        routePolyline = L.polyline(currentRoutePoints, {
          color: '#0066FF',
          weight: 6,
          opacity: 0.85,
          lineCap: 'round',
          lineJoin: 'round'
        }).addTo(map);

        allBounds = routePolyline.getBounds();
        map.fitBounds(allBounds, { padding: [70, 70] });
      }

      applyVehicleRotation(vehicleHeading);
    }

    // Dynamic Route Trimming: remove the blue path that the vehicle has already gone through
    function trimTraveledRoute(lat, lng) {
      if (!currentRoutePoints || currentRoutePoints.length < 2) return;

      var bestSegmentIdx = -1;
      var minDistanceSq = Infinity;
      var cosLat = Math.cos(lat * Math.PI / 180);

      // Search up to the next 35 segments to detect current vehicle progression
      var maxSegments = Math.min(currentRoutePoints.length - 1, 35);
      for (var i = 0; i < maxSegments; i++) {
        var p1 = currentRoutePoints[i];
        var p2 = currentRoutePoints[i + 1];

        var dx = (p2[1] - p1[1]) * cosLat;
        var dy = p2[0] - p1[0];
        var segLenSq = dx * dx + dy * dy;

        var px = (lng - p1[1]) * cosLat;
        var py = lat - p1[0];

        var t = 0;
        if (segLenSq > 0) {
          t = (px * dx + py * dy) / segLenSq;
          if (t < 0) t = 0;
          else if (t > 1) t = 1;
        }

        var projX = p1[1] * cosLat + t * dx;
        var projY = p1[0] + t * dy;

        var curX = lng * cosLat;
        var curY = lat;

        var distSq = (curX - projX) * (curX - projX) + (curY - projY) * (curY - projY);
        if (distSq < minDistanceSq) {
          minDistanceSq = distSq;
          bestSegmentIdx = i;
        }
      }

      // If vehicle is within proximity of the active route (~150m):
      if (bestSegmentIdx >= 0 && minDistanceSq < 0.00003) {
        // Remove traveled segments before bestSegmentIdx + 1 and start path at current vehicle position
        var remaining = [[lat, lng]].concat(currentRoutePoints.slice(bestSegmentIdx + 1));
        currentRoutePoints = remaining;
        if (routePolyline) {
          routePolyline.setLatLngs(remaining);
        }
      }
    }

    function setVehiclePosition(lat, lng, heading, followCamera, isNavigating) {
      currentStaffLat = lat;
      currentStaffLng = lng;
      vehicleHeading = heading || 0;

      if (staffMarker) {
        staffMarker.setLatLng([lat, lng]);
      }

      applyVehicleRotation(vehicleHeading);

      // Remove the blue path that has already been gone through
      if (routePolyline && currentRoutePoints && currentRoutePoints.length > 1) {
        trimTraveledRoute(lat, lng);
      }

      if (followCamera) {
        map.setView([lat, lng], map.getZoom(), { animate: false });
      }
    }

    function applyVehicleRotation(deg) {
      var pin = document.getElementById('vehiclePin');
      if (pin) {
        pin.style.transform = 'rotate(' + (deg || 0) + 'deg)';
      }
    }

    function centerOnStaff(zoomLevel) {
      if (currentStaffLat && currentStaffLng) {
        map.setView([currentStaffLat, currentStaffLng], zoomLevel || 18, { animate: true });
      }
    }

    function fitFullRoute() {
      if (allBounds) {
        map.fitBounds(allBounds, { padding: [80, 80], animate: true });
      }
    }

    function zoomIn() {
      map.zoomIn();
    }

    function zoomOut() {
      map.zoomOut();
    }
  </script>
</body>
</html>
''';
  }
}
