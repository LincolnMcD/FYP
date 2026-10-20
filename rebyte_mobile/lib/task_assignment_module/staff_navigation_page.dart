import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../staff_module/staff_home_page.dart';
import 'services/task_assignment_service.dart';

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

  // Fallback origin: ReByte Hub
  static const double companyLat = 5.453240417145323;
  static const double companyLng = 100.2848625551094;

  double _staffOriginLat = companyLat;
  double _staffOriginLng = companyLng;
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
  List<List<double>> _routePoints = [];

  @override
  void initState() {
    super.initState();
    _task = Map<String, dynamic>.from(widget.task);
    _destLat = (_task['destinationLat'] as num?)?.toDouble() ?? 5.4045;
    _destLng = (_task['destinationLng'] as num?)?.toDouble() ?? 100.3333;
    _address = _task['deliveryAddress']?.toString() ?? '123 Tech Lane, Kuala Lumpur';
    _customerName = _task['customerName']?.toString() ?? 'Customer';
    _orderID = _task['orderID']?.toString() ?? '';
    _taskID = _task['taskID']?.toString() ?? '';
    _scheduleID = _task['scheduleID']?.toString() ?? '';

    _initNavigationRoute();
  }

  /// 1. Acquire current Staff GPS location and calculate route to customer destination
  Future<void> _initNavigationRoute() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          _staffOriginLat = pos.latitude;
          _staffOriginLng = pos.longitude;
          _hasStaffGpsOrigin = true;
        }
      }
    } catch (e) {
      debugPrint('Staff origin GPS fetch error: $e');
    }

    // Load OSRM driving route from current staff location to destination
    await _loadOsrmRoute();
  }

  Future<void> _loadOsrmRoute() async {
    final fromLat = _staffOriginLat;
    final fromLng = _staffOriginLng;

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$fromLng,$fromLat;$_destLng,$_destLat?overview=full&geometries=geojson',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 7));
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

          if (mounted) {
            setState(() {
              _estDurationMinutes = (durSec / 60).ceil();
              _estDistanceKm = double.parse((distM / 1000).toStringAsFixed(1));
              _routePoints = pts;
            });
            _updateMapRoute();
          }
          return;
        }
      }
    } catch (_) {}

    // Fallback: direct line points
    if (mounted) {
      setState(() {
        _routePoints = [
          [fromLat, fromLng],
          [_destLat, _destLng],
        ];
      });
      _updateMapRoute();
    }
  }

  void _updateMapRoute() {
    if (_webViewController != null && _routePoints.isNotEmpty) {
      final jsonPoints = jsonEncode(_routePoints);
      _webViewController?.evaluateJavascript(source: '''
        updateRoute($jsonPoints, $_staffOriginLat, $_staffOriginLng, $_destLat, $_destLng, ${_hasStaffGpsOrigin ? "'Your Current Location'" : "'ReByte Central Hub'"});
      ''');
    }
  }

  /// 2. Launch Turn-by-Turn Navigation App or show in-app guidance modal
  Future<void> _handleDirectionsGuide() async {
    // Zoom map smoothly to full path overview
    _webViewController?.evaluateJavascript(source: 'fitFullRoute();');

    // Prompt user to launch native Turn-by-Turn GPS Navigation
    final googleMapsUrl = Uri.parse('google.navigation:q=$_destLat,$_destLng&mode=d');
    final webMapsUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&origin=$_staffOriginLat,$_staffOriginLng&destination=$_destLat,$_destLng&travelmode=driving');
    final wazeUrl = Uri.parse('waze://?ll=$_destLat,$_destLng&navigate=yes');

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Start Live Navigation',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Destination: $_address',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.navigation, color: Color(0xFF0C5AD2)),
                ),
                title: const Text('Google Maps Turn-by-Turn', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Live voice guidance & traffic routing', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF94A3B8)),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (await canLaunchUrl(googleMapsUrl)) {
                    await launchUrl(googleMapsUrl);
                  } else {
                    await launchUrl(webMapsUrl, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.alt_route, color: Color(0xFF16A34A)),
                ),
                title: const Text('Waze Navigation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Fastest route with community alerts', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF94A3B8)),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (await canLaunchUrl(wazeUrl)) {
                    await launchUrl(wazeUrl);
                  } else {
                    await launchUrl(webMapsUrl, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 3. Verify staff live GPS is at customer destination
  Future<bool> _verifyStaffAtDestination() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable GPS / Location services to complete delivery.')),
        );
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required to verify destination arrival.')),
          );
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission permanently denied. Please allow in app settings.')),
        );
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final distanceMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _destLat,
        _destLng,
      );

      // Within 200m radius of destination is considered arrived at the same location
      if (distanceMeters <= 200) {
        return true;
      } else {
        if (!mounted) return false;
        final distStr = distanceMeters >= 1000
            ? '${(distanceMeters / 1000).toStringAsFixed(2)} km'
            : '${distanceMeters.toStringAsFixed(0)} meters';

        final proceedAnyway = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Location Verification'),
            content: Text(
              'Your GPS shows you are $distStr away from the customer delivery address.\n\nAre you sure you have arrived at the destination?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0C5AD2)),
                child: const Text('Yes, Complete Delivery', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        return proceedAnyway == true;
      }
    } catch (e) {
      debugPrint('Geolocator verification error: $e');
      return true; // allow fallback if hardware error
    }
  }

  Future<void> _handleCompleteDelivery() async {
    setState(() => _isActionLoading = true);

    final isAtLocation = await _verifyStaffAtDestination();
    if (!isAtLocation) {
      setState(() => _isActionLoading = false);
      return;
    }

    final success = await TaskAssignmentService.updateTaskStatus(
      taskID: _taskID,
      orderID: _orderID,
      scheduleID: _scheduleID,
      status: 'Delivered',
    );

    if (!mounted) return;
    setState(() => _isActionLoading = false);

    if (success) {
      widget.onTaskUpdated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery completed successfully!'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update task status. Please try again.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }

  void _onBottomNavTapped(int index) {
    if (index == 2) {
      // Already on Tasks module
      Navigator.pop(context);
    } else {
      // Navigate to StaffHomePage with initialIndex
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => StaffHomePage(initialIndex: index),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = _address.split(',');
    final addressLine1 = parts.isNotEmpty ? parts[0].trim() : _address;
    final addressLine2 = parts.length > 1 ? parts.sublist(1).join(',').trim() : '';

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
                    data: _buildNavigationMapHtml(_staffOriginLat, _staffOriginLng, _destLat, _destLng),
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
                    child: CircularProgressIndicator(color: Color(0xFF0C5AD2), strokeWidth: 2.5),
                  ),
              ],
            ),
          ),

          // 2. Bottom Sliding Destination Card
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
                              if (_customerName.isNotEmpty && _customerName != 'Customer') ...[
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
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  color: Color(0xFF0F172A),
                                  height: 1.2,
                                ),
                              ),
                              if (addressLine2.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  addressLine2,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$_estDurationMinutes MINS',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1D4ED8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_estDistanceKm km',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Action Buttons Row: [Directions] and [Complete Delivery]
                    Row(
                      children: [
                        // Directions Button: guides user to destination via turn-by-turn navigation
                        Expanded(
                          flex: 1,
                          child: OutlinedButton.icon(
                            onPressed: _handleDirectionsGuide,
                            icon: const Icon(Icons.directions, color: Color(0xFF0C5AD2), size: 18),
                            label: const Text(
                              'Directions',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0C5AD2),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Complete Deliver Button: checks staff GPS matches destination
                        Expanded(
                          flex: 1,
                          child: ElevatedButton.icon(
                            onPressed: _isActionLoading ? null : _handleCompleteDelivery,
                            icon: _isActionLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                            label: const Text(
                              'Complete Deliver',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0C5AD2),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
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
          ),
        ],
      ),
      bottomNavigationBar: Container(
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
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded, size: 24), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_today_rounded, size: 24), label: 'Schedule'),
            BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined, size: 24), label: 'Tasks'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline, size: 24), label: 'Profile'),
          ],
        ),
      ),
    );
  }

  String _buildNavigationMapHtml(double fromLat, double fromLng, double toLat, double toLng) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    body, html { margin: 0; padding: 0; width: 100%; height: 100%; background: #F8FAFC; }
    #map { width: 100%; height: 100%; }
    .staff-pin {
      width: 32px;
      height: 32px;
      background: #0C5AD2;
      border: 3px solid #FFFFFF;
      border-radius: 50% 50% 50% 0;
      transform: rotate(-45deg);
      box-shadow: 0 4px 10px rgba(0,0,0,0.3);
      display: flex;
      align-items: center;
      justify-content: center;
    }
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

    var staffIcon = L.divIcon({
      className: '',
      html: '<div class="staff-pin"></div>',
      iconSize: [32, 32],
      iconAnchor: [16, 32]
    });

    var destIcon = L.divIcon({
      className: '',
      html: '<div class="dest-pin"></div>',
      iconSize: [32, 32],
      iconAnchor: [16, 32]
    });

    var staffMarker = L.marker([$fromLat, $fromLng], { icon: staffIcon }).addTo(map).bindPopup('Current Location');
    var destMarker = L.marker([$toLat, $toLng], { icon: destIcon }).addTo(map).bindPopup('Customer Destination');

    var routePolyline = null;
    var allBounds = L.latLngBounds([[$fromLat, $fromLng], [$toLat, $toLng]]);

    map.fitBounds(allBounds, { padding: [60, 60] });

    function updateRoute(points, fromLat, fromLng, toLat, toLng, fromLabel) {
      if (staffMarker) {
        staffMarker.setLatLng([fromLat, fromLng]);
        staffMarker.bindPopup(fromLabel || 'Current Location');
      }
      if (destMarker) {
        destMarker.setLatLng([toLat, toLng]);
      }
      if (routePolyline) {
        map.removeLayer(routePolyline);
      }
      if (points && points.length > 0) {
        routePolyline = L.polyline(points, {
          color: '#0066FF',
          weight: 6,
          opacity: 0.85,
          lineCap: 'round',
          lineJoin: 'round'
        }).addTo(map);

        allBounds = routePolyline.getBounds();
        map.fitBounds(allBounds, { padding: [70, 70] });
      }
    }

    function fitFullRoute() {
      if (allBounds) {
        map.fitBounds(allBounds, { padding: [80, 80], animate: true });
      }
    }
  </script>
</body>
</html>
''';
  }
}
