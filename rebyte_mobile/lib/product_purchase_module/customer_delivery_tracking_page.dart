import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../account_management_module/models/address_model.dart';
import '../task_assignment_module/services/task_assignment_service.dart';
import '../task_assignment_module/services/delivery_socket_service.dart';

class CustomerDeliveryTrackingPage extends StatefulWidget {
  final String orderID;
  final String? taskStatus;
  final String? orderStatus;
  final String? scheduleDate;
  final String? estimatedEndTime;
  final AddressModel? deliveryAddress;

  const CustomerDeliveryTrackingPage({
    super.key,
    required this.orderID,
    this.taskStatus,
    this.orderStatus,
    this.scheduleDate,
    this.estimatedEndTime,
    this.deliveryAddress,
  });

  @override
  State<CustomerDeliveryTrackingPage> createState() =>
      _CustomerDeliveryTrackingPageState();
}

class _CustomerDeliveryTrackingPageState
    extends State<CustomerDeliveryTrackingPage> {
  InAppWebViewController? _webViewController;
  bool _isMapLoading = true;

  // Fallback origin: ReByte Central Hub (Penang)
  static const double companyLat = 5.453240417145323;
  static const double companyLng = 100.2848625551094;

  // Pointer A: Staff GPS location
  double _staffLat = companyLat;
  double _staffLng = companyLng;
  double _staffHeading = 0.0;
  bool _hasLiveStaffGps = false;

  // Destination (Customer delivery address)
  double _destLat = 5.3911;
  double _destLng = 100.3237;
  String _addressText = 'Delivery Destination';
  String _recipientName = 'Customer';

  // Staff information
  String _staffName = 'Delivery Specialist';
  String _staffPhone = '';

  // Timing & distance
  String? _scheduleDate;
  String? _estimatedEndTime;
  int _estDurationMinutes = 18;
  double _estDistanceKm = 4.2;
  List<List<double>> _routePoints = [];
  List<double> _routeCumulativeDistancesM = [];
  double _totalRouteDistanceM = 0.0;
  double _totalRouteDurationSec = 0.0;
  double _routeProgressM = 0.0;
  double _routeSpeedMps = 7.5; // ~27 km/h urban speed

  // Dynamic ETA & route tracking
  DateTime? _lastRouteFetchTime;
  double _distanceSinceLastRouteFetch = 0.0;
  Timer? _etaTickerTimer;

  Timer? _liveTrackingTimer;
  bool _isFetchingLiveGps = false;

  final DeliverySocketService _socketService = DeliverySocketService();
  bool _isDeliveryCompleted = false;

  @override
  void initState() {
    super.initState();
    _scheduleDate = widget.scheduleDate;
    _estimatedEndTime = widget.estimatedEndTime;

    if (widget.deliveryAddress != null) {
      final addr = widget.deliveryAddress!;
      _addressText = addr.fullAddress.isNotEmpty ? addr.fullAddress : addr.addressLine;
      _recipientName = addr.recipientName.isNotEmpty ? addr.recipientName : 'Customer';
      if (addr.latitude != null && addr.longitude != null) {
        _destLat = addr.latitude!;
        _destLng = addr.longitude!;
      }
    }

    _loadInitialTrackingData();
    _initSocketTracking();
    _startEtaTicker();
  }

  @override
  void dispose() {
    _etaTickerTimer?.cancel();
    _etaTickerTimer = null;
    _socketService.leaveRoom(widget.orderID);
    _socketService.dispose();
    _liveTrackingTimer?.cancel();
    _liveTrackingTimer = null;
    super.dispose();
  }

  /// Ticker timer to keep the dynamic arrival clock & elapsed minutes updated in real time
  void _startEtaTicker() {
    _etaTickerTimer?.cancel();
    _etaTickerTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_isDeliveryCompleted) {
        setState(() {}); // Re-render dynamic arrival time with current DateTime.now()
      }
    });
  }

  /// Connect to Socket.IO and join delivery room for instant live tracking
  void _initSocketTracking() {
    _socketService.connect(
      orderID: widget.orderID,
      role: 'customer',
      onLocationUpdate: (data) {
        if (!mounted || _isDeliveryCompleted) return;
        final newLat = (data['lat'] as num?)?.toDouble();
        final newLng = (data['lng'] as num?)?.toDouble();
        final heading = (data['heading'] as num?)?.toDouble() ?? _staffHeading;
        final speed = (data['speed'] as num?)?.toDouble() ?? 0.0;
        final staffDistKm = (data['estimatedDistanceKm'] as num?)?.toDouble();
        final staffDurMins = (data['estimatedDurationMinutes'] as num?)?.toInt();

        if (newLat != null && newLng != null) {
          final movedDist = _calculateDistance(_staffLat, _staffLng, newLat, newLng);

          setState(() {
            _staffLat = newLat;
            _staffLng = newLng;
            _staffHeading = heading;
            _hasLiveStaffGps = true;
            // Directly mirror the exact distance and duration from the staff's turn-by-turn navigation
            if (staffDistKm != null && staffDurMins != null) {
              _estDistanceKm = staffDistKm;
              _estDurationMinutes = staffDurMins;
            }
          });

          // Move vehicle marker smoothly in real time
          _webViewController?.evaluateJavascript(
            source: '''
              setVehiclePosition($_staffLat, $_staffLng, $_staffHeading, false, false);
            ''',
          );

          // If staff didn't broadcast their active navigation ETA, calculate along road route
          if (staffDistKm == null || staffDurMins == null) {
            _handleDynamicEtaUpdate(movedDist, speed);
          }
        }
      },
      onDeliveryCompleted: (data) {
        if (!mounted) return;
        setState(() {
          _isDeliveryCompleted = true;
        });
        _socketService.leaveRoom(widget.orderID);
        _showDeliveryCompletedDialog(data);
      },
    );
  }

  /// Dynamically update distance, duration, and arrival time as staff moves along the road
  void _handleDynamicEtaUpdate(double movedDist, double speed) {
    _distanceSinceLastRouteFetch += movedDist;
    final now = DateTime.now();

    final directDistM = _calculateDistance(_staffLat, _staffLng, _destLat, _destLng);

    // If staff has reached destination (< 35m)
    if (directDistM < 35) {
      setState(() {
        _estDistanceKm = 0.0;
        _estDurationMinutes = 0;
      });
      return;
    }

    // Trigger full OSRM road recalculation if staff moved >= 80m or >= 15s elapsed
    final shouldRecalcRoute = _distanceSinceLastRouteFetch >= 80 ||
        _lastRouteFetchTime == null ||
        now.difference(_lastRouteFetchTime!).inSeconds >= 15;

    if (shouldRecalcRoute) {
      _lastRouteFetchTime = now;
      _distanceSinceLastRouteFetch = 0.0;
      _loadOsrmRoute();
      return;
    }

    // Dynamic micro-update along the true road polyline between OSRM calls
    if (_routePoints.isNotEmpty && _routeCumulativeDistancesM.isNotEmpty && _totalRouteDistanceM > 0) {
      _routeProgressM = _findProgressOnRoute(
        _staffLat,
        _staffLng,
        _routePoints,
        _routeCumulativeDistancesM,
        previousProgress: _routeProgressM,
      );

      final remainingRoadM = math.max(0.0, _totalRouteDistanceM - _routeProgressM);
      // Ensure remaining road distance doesn't fall below straight-line distance
      final effectiveRemainingM = math.max(directDistM, remainingRoadM);

      // Proportionate countdown of remaining route duration:
      // Uses the OSRM total road duration scaled by remaining road distance with .ceil()
      // so it never prematurely drops a full minute on slight movement.
      final remainingRatio = (effectiveRemainingM / _totalRouteDistanceM).clamp(0.0, 1.0);
      final remainingSec = _totalRouteDurationSec > 0
          ? (_totalRouteDurationSec * remainingRatio)
          : (effectiveRemainingM / (_routeSpeedMps > 2.0 ? _routeSpeedMps : 7.5));
      final dynamicMins = math.max(1, (remainingSec / 60).ceil());

      setState(() {
        _estDistanceKm = double.parse((effectiveRemainingM / 1000).toStringAsFixed(1));
        _estDurationMinutes = dynamicMins;
      });
    } else {
      // Fallback only if no route polyline is loaded yet
      final approxRoadKm = (directDistM / 1000) * 1.25;
      final effectiveSpeedKmH = 28.0;
      final dynamicMins = ((approxRoadKm / effectiveSpeedKmH) * 60).ceil().clamp(1, 999);
      setState(() {
        _estDistanceKm = double.parse(approxRoadKm.toStringAsFixed(1));
        _estDurationMinutes = dynamicMins;
      });
    }
  }

  void _showDeliveryCompletedDialog(Map<String, dynamic> data) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Package Delivered!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data['message']?.toString() ??
                  'Your order #${widget.orderID} has been successfully delivered by the specialist.',
              style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
            ),
            const SizedBox(height: 12),
            const Text(
              'Thank you for shopping with ReByte!',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop(true);
              },
              child: const Text(
                'Back to Order Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );

    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context); // Return to Order Detail page
    }
  }

  /// Initial load: fetch live delivery tracking data from backend and calculate route
  Future<void> _loadInitialTrackingData() async {
    await _fetchLiveDeliveryData();
    await _loadOsrmRoute();

    // Fallback heartbeat polling only if socket is disconnected (every 20s)
    _liveTrackingTimer?.cancel();
    _liveTrackingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_socketService.isConnected && !_isDeliveryCompleted) {
        _pollLiveStaffGps();
      }
    });
  }

  /// Fetch tracking details from backend
  Future<void> _fetchLiveDeliveryData() async {
    try {
      final data = await TaskAssignmentService.trackDelivery(
        orderID: widget.orderID,
      );
      if (data != null && mounted) {
        setState(() {
          if (data['destinationLat'] != null && data['destinationLng'] != null) {
            _destLat = (data['destinationLat'] as num).toDouble();
            _destLng = (data['destinationLng'] as num).toDouble();
          }
          if (data['deliveryAddress'] != null &&
              data['deliveryAddress'].toString().isNotEmpty) {
            _addressText = data['deliveryAddress'].toString();
          }
          if (data['recipientName'] != null &&
              data['recipientName'].toString().isNotEmpty) {
            _recipientName = data['recipientName'].toString();
          }
          if (data['staffName'] != null &&
              data['staffName'].toString().isNotEmpty) {
            _staffName = data['staffName'].toString();
          }
          if (data['staffPhone'] != null) {
            _staffPhone = data['staffPhone'].toString();
          }
          if (data['scheduleDate'] != null &&
              data['scheduleDate'].toString().isNotEmpty) {
            _scheduleDate = data['scheduleDate'].toString();
          }
          if (data['estimatedEndTime'] != null &&
              data['estimatedEndTime'].toString().isNotEmpty) {
            _estimatedEndTime = data['estimatedEndTime'].toString();
          }

          if (data['staffLat'] != null && data['staffLng'] != null) {
            _staffLat = (data['staffLat'] as num).toDouble();
            _staffLng = (data['staffLng'] as num).toDouble();
            _staffHeading = (data['staffHeading'] as num?)?.toDouble() ?? 0.0;
            _hasLiveStaffGps = data['isLiveGps'] == true;
            if (data['isLiveGps'] == true) {
              if (data['estimatedDistance'] != null) {
                _estDistanceKm = (data['estimatedDistance'] as num).toDouble();
              }
              if (data['estimatedDuration'] != null) {
                _estDurationMinutes = (data['estimatedDuration'] as num).toInt();
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Customer tracking fetch error: $e');
    }
  }

  /// Periodic poll to move Pointer A in real-time as staff drives
  Future<void> _pollLiveStaffGps() async {
    if (_isFetchingLiveGps) return;
    _isFetchingLiveGps = true;
    try {
      final data = await TaskAssignmentService.trackDelivery(
        orderID: widget.orderID,
      );
      if (data != null && mounted) {
        final newLat = (data['staffLat'] as num?)?.toDouble();
        final newLng = (data['staffLng'] as num?)?.toDouble();
        final heading = (data['staffHeading'] as num?)?.toDouble() ?? _staffHeading;
        final isLive = data['isLiveGps'] == true;
        final staffDist = (data['estimatedDistance'] as num?)?.toDouble();
        final staffDur = (data['estimatedDuration'] as num?)?.toInt();

        if (newLat != null && newLng != null) {
          final movedDist = _calculateDistance(_staffLat, _staffLng, newLat, newLng);

          setState(() {
            _staffLat = newLat;
            _staffLng = newLng;
            _staffHeading = heading;
            _hasLiveStaffGps = isLive;
            if (isLive && staffDist != null && staffDur != null) {
              _estDistanceKm = staffDist;
              _estDurationMinutes = staffDur;
            }
            if (data['scheduleDate'] != null) _scheduleDate = data['scheduleDate'].toString();
            if (data['estimatedEndTime'] != null) _estimatedEndTime = data['estimatedEndTime'].toString();
          });

          // Update Leaflet marker position & trim traveled path
          _webViewController?.evaluateJavascript(
            source: '''
              setVehiclePosition($_staffLat, $_staffLng, $_staffHeading, false, false);
            ''',
          );

          // If staff distance/duration not provided, calculate dynamic road ETA
          if (staffDist == null || staffDur == null) {
            _handleDynamicEtaUpdate(movedDist, 0.0);
          }
        }
      }
    } catch (_) {
    } finally {
      _isFetchingLiveGps = false;
    }
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lng2 - lng1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a)) * 1000; // Meters
  }

  List<double> _buildRouteCumulativeDistances(List<List<double>> points) {
    if (points.isEmpty) return const [];
    final distances = <double>[0];
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      distances.add(
        distances.last +
            _calculateDistance(
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

    final lowerBound = previousProgress == null
        ? 0.0
        : math.max(0.0, previousProgress - 25);
    final upperBound = previousProgress == null
        ? double.infinity
        : previousProgress + 300;
    var nearestDistance = double.infinity;
    var nearestProgress = previousProgress ?? 0.0;

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
      final distance = _calculateDistance(
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

  /// Load OSRM driving route connecting Pointer A (Staff GPS) to Customer Destination
  Future<void> _loadOsrmRoute() async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$_staffLng,$_staffLat;$_destLng,$_destLat?overview=full&geometries=geojson',
      );
      final res = await http
          .get(
            url,
            headers: {'User-Agent': 'ReByte-App/1.0 (Customer Delivery Tracking)'},
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

          final cumulativeDistances = _buildRouteCumulativeDistances(pts);
          final currentProgress = _findProgressOnRoute(
            _staffLat,
            _staffLng,
            pts,
            cumulativeDistances,
          );

          final remainingM = math.max(0.0, distM - currentProgress);
          final directDistM = _calculateDistance(_staffLat, _staffLng, _destLat, _destLng);
          final effectiveRemainingM = math.max(directDistM, remainingM);

          _totalRouteDistanceM = distM;
          _totalRouteDurationSec = durSec;
          _routeCumulativeDistancesM = cumulativeDistances;
          _routeProgressM = currentProgress;
          if (distM > 0 && durSec > 0) {
            _routeSpeedMps = distM / durSec;
          }

          final remainingRatio = distM > 0 ? (effectiveRemainingM / distM).clamp(0.0, 1.0) : 1.0;
          final remainingSec = durSec * remainingRatio;
          final calculatedMins = math.max(1, (remainingSec / 60).ceil());

          if (mounted) {
            _lastRouteFetchTime = DateTime.now();
            _distanceSinceLastRouteFetch = 0.0;
            setState(() {
              _routePoints = pts;
              _estDistanceKm = double.parse((effectiveRemainingM / 1000).toStringAsFixed(1));
              _estDurationMinutes = calculatedMins;
            });
            _updateMapRoute();
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('OSRM customer routing error: $e');
    }

    // Fallback: direct line if OSRM unavailable
    if (mounted && _routePoints.isEmpty) {
      final directDistM = _calculateDistance(_staffLat, _staffLng, _destLat, _destLng);
      final approxRoadKm = (directDistM / 1000) * 1.25;
      final fallbackMins = ((approxRoadKm / 28.0) * 60).round().clamp(1, 999);
      setState(() {
        _estDistanceKm = double.parse(approxRoadKm.toStringAsFixed(1));
        _estDurationMinutes = fallbackMins;
        _routePoints = [
          [_staffLat, _staffLng],
          [_destLat, _destLng],
        ];
      });
      _updateMapRoute();
    }
  }

  void _updateMapRoute() {
    if (_webViewController != null && _routePoints.isNotEmpty) {
      final jsonPoints = jsonEncode(_routePoints);
      final staffLabel = _hasLiveStaffGps
          ? '$_staffName (Pointer A)'
          : 'ReByte Central Hub (Pointer A)';
      _webViewController?.evaluateJavascript(
        source: '''
          updateRoute($jsonPoints, $_staffLat, $_staffLng, $_destLat, $_destLng, '$staffLabel', $_staffHeading);
        ''',
      );
    }
  }

  /// Format arrival time and date display dynamically calculated from current GPS
  Map<String, String> _getFormattedArrivalDetails() {
    final now = DateTime.now();

    // 1. Dynamic Arrival DateTime based on real-time calculated road duration
    DateTime dynamicArrival = now.add(Duration(minutes: _estDurationMinutes));

    // If staff has not started live GPS delivery yet, we can use the scheduled baseline
    if (!_hasLiveStaffGps && _estimatedEndTime != null && _estimatedEndTime!.isNotEmpty) {
      final rawEndTime = _estimatedEndTime!;
      final cleanTime = rawEndTime.contains('T')
          ? rawEndTime.split('T').last.split('.').first
          : (rawEndTime.length == 5 ? '$rawEndTime:00' : rawEndTime);
      final datePart = _scheduleDate ?? DateFormat('yyyy-MM-dd').format(now);
      final parsed = DateTime.tryParse('${datePart}T$cleanTime');
      if (parsed != null && parsed.isAfter(now)) {
        dynamicArrival = parsed;
      }
    }

    final dateStr = DateFormat('MMM dd, yyyy').format(dynamicArrival);
    final timeStr = DateFormat('h:mm a').format(dynamicArrival);

    // 2. Dynamic Duration & Distance text
    String durText;
    if (_estDistanceKm <= 0.05 || _estDurationMinutes <= 0) {
      durText = 'Arriving now';
    } else if (_estDurationMinutes <= 1) {
      durText = '< 1 min (${_estDistanceKm.toStringAsFixed(1)} km away)';
    } else if (_estDurationMinutes >= 60) {
      final hours = _estDurationMinutes ~/ 60;
      final mins = _estDurationMinutes % 60;
      durText = '$hours hr ${mins > 0 ? '$mins mins ' : ''}(${_estDistanceKm.toStringAsFixed(1)} km away)';
    } else {
      durText = '$_estDurationMinutes mins (${_estDistanceKm.toStringAsFixed(1)} km away)';
    }

    return {
      'date': dateStr,
      'time': timeStr,
      'duration': durText,
    };
  }

  Future<void> _makePhoneCall(String phone) async {
    if (phone.isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot make phone call to $phone')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final arrivalInfo = _getFormattedArrivalDetails();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Track Delivery',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              'Order #${widget.orderID.replaceAll('#', '')}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0C5AD2),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'Delivering',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0C5AD2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Interactive Leaflet Map via InAppWebView
          InAppWebView(
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: true,
              supportZoom: true,
              builtInZoomControls: false,
              displayZoomControls: false,
            ),
            initialData: InAppWebViewInitialData(
              data: _buildCustomerTrackingMapHtml(
                _staffLat,
                _staffLng,
                _destLat,
                _destLng,
              ),
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            onLoadStop: (controller, url) async {
              setState(() => _isMapLoading = false);
              _updateMapRoute();
            },
          ),

          // Loading Indicator
          if (_isMapLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF0C5AD2),
                ),
              ),
            ),

          // 2. Floating Map Action Buttons (Recenter on Staff Pointer A & Fit Full Route)
          Positioned(
            right: 16,
            bottom: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'recenter_staff',
                  tooltip: 'Center on Delivery Staff',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0C5AD2),
                  elevation: 4,
                  onPressed: () {
                    _webViewController?.evaluateJavascript(
                      source: 'centerOnStaff(17);',
                    );
                  },
                  child: const Icon(Icons.navigation_rounded, size: 20),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'fit_customer_route',
                  tooltip: 'View Entire Route',
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

          // 3. Pointer A & Destination Legend Tag
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0C5AD2),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Pointer A: Delivery Staff',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE11D48),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Destination',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 4. Bottom Delivery Information Card
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle pill
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Estimated Arrival Section (Time, Date, Duration)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C5AD2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.access_time_filled_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Estimated Arrival',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E3A8A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${arrivalInfo['date']} by ${arrivalInfo['time']}',
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0C5AD2),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                arrivalInfo['duration'] ?? '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Delivery Address Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          size: 18,
                          color: Color(0xFFE11D48),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _recipientName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _addressText,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 12),

                  // Staff Info Row with optional Call Button
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFF0C5AD2).withValues(alpha: 0.1),
                        child: const Icon(
                          Icons.person,
                          size: 20,
                          color: Color(0xFF0C5AD2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _staffName,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _hasLiveStaffGps
                                  ? 'Delivering your order • Live GPS'
                                  : 'Assigned Delivery Specialist',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _hasLiveStaffGps
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_staffPhone.isNotEmpty)
                        IconButton(
                          onPressed: () => _makePhoneCall(_staffPhone),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFF1F5F9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.phone_outlined,
                            size: 18,
                            color: Color(0xFF0C5AD2),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the complete Leaflet map HTML with Pointer A (staff GPS) and customer destination pin
  String _buildCustomerTrackingMapHtml(
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

    /* Modern Vehicle / Staff Pointer A with directional arrow & glowing pulse */
    .vehicle-marker-container {
      width: 44px;
      height: 44px;
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: transform 0.3s ease-out;
    }
    .vehicle-pulse {
      position: absolute;
      width: 40px;
      height: 40px;
      border-radius: 50%;
      background: rgba(12, 90, 210, 0.28);
      animation: pulse 1.8s infinite ease-out;
    }
    .vehicle-core {
      position: relative;
      width: 30px;
      height: 30px;
      background: #0C5AD2;
      border: 3px solid #FFFFFF;
      border-radius: 50%;
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.35);
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

    /* Customer Destination Pin */
    .dest-pin {
      width: 32px;
      height: 32px;
      background: #E11D48;
      border: 3px solid #FFFFFF;
      border-radius: 50% 50% 50% 0;
      transform: rotate(-45deg);
      box-shadow: 0 4px 12px rgba(0,0,0,0.3);
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
      0% { transform: scale(0.8); opacity: 0.95; }
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
      iconSize: [44, 44],
      iconAnchor: [22, 22]
    });

    var destIcon = L.divIcon({
      className: '',
      html: '<div class="dest-pin"></div>',
      iconSize: [32, 32],
      iconAnchor: [16, 32]
    });

    var staffMarker = L.marker([$fromLat, $fromLng], { icon: staffIcon }).addTo(map).bindPopup('Pointer A: Delivery Staff');
    var destMarker = L.marker([$toLat, $toLng], { icon: destIcon }).addTo(map).bindPopup('Delivery Destination');

    var routePolyline = null;
    var currentRoutePoints = [];
    var allBounds = L.latLngBounds([[$fromLat, $fromLng], [$toLat, $toLng]]);
    map.fitBounds(allBounds, {
      paddingTopLeft: [40, 80],
      paddingBottomRight: [40, 310]
    });

    function updateRoute(points, fromLat, fromLng, toLat, toLng, fromLabel, heading) {
      currentStaffLat = fromLat;
      currentStaffLng = fromLng;
      if (heading !== undefined) vehicleHeading = heading;

      if (staffMarker) {
        staffMarker.setLatLng([fromLat, fromLng]);
        staffMarker.bindPopup(fromLabel || 'Pointer A: Delivery Staff');
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
        map.fitBounds(allBounds, {
          paddingTopLeft: [40, 80],
          paddingBottomRight: [40, 310]
        });
      }

      applyVehicleRotation(vehicleHeading);
    }

    // Dynamic Route Trimming: remove the blue path that the staff vehicle has already passed
    function trimTraveledRoute(lat, lng) {
      if (!currentRoutePoints || currentRoutePoints.length < 2) return;

      var bestSegmentIdx = -1;
      var minDistanceSq = Infinity;
      var cosLat = Math.cos(lat * Math.PI / 180);

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

      if (bestSegmentIdx >= 0 && minDistanceSq < 0.00003) {
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

      if (routePolyline && currentRoutePoints && currentRoutePoints.length > 1) {
        trimTraveledRoute(lat, lng);
      }

      if (followCamera) {
        centerOnStaff(map.getZoom());
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
        var targetZoom = zoomLevel || map.getZoom() || 16;
        var targetPoint = map.project([currentStaffLat, currentStaffLng], targetZoom);
        // Offset point downwards by 130px so the marker itself is centered in the upper visible area above the bottom card
        var offsetPoint = L.point(targetPoint.x, targetPoint.y + 130);
        var offsetLatLng = map.unproject(offsetPoint, targetZoom);
        map.setView(offsetLatLng, targetZoom, { animate: true });
      }
    }

    function zoomInOnStaff() {
      var nextZoom = Math.min(19, map.getZoom() + 1);
      centerOnStaff(nextZoom);
    }

    function zoomOutOnStaff() {
      var nextZoom = Math.max(12, map.getZoom() - 1);
      centerOnStaff(nextZoom);
    }

    function fitFullRoute() {
      if (allBounds) {
        map.fitBounds(allBounds, {
          paddingTopLeft: [40, 80],
          paddingBottomRight: [40, 310],
          animate: true
        });
      }
    }

    map.on('zoomend', function() {
      if (currentStaffLat && currentStaffLng) {
        var centerPoint = map.project(map.getCenter(), map.getZoom());
        var staffPoint = map.project([currentStaffLat, currentStaffLng], map.getZoom());
        var mapSize = map.getSize();
        var staffScreenY = staffPoint.y - centerPoint.y + (mapSize.y / 2);
        // If staff marker falls into or behind the bottom section (covered by bottom card), nudge to center
        if (staffScreenY > (mapSize.y - 280)) {
          centerOnStaff(map.getZoom());
        }
      }
    });
  </script>
</body>
</html>
''';
  }
}
