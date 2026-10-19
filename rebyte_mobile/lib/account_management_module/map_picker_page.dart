import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'services/address_service.dart';

class MapPickerPage extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? initialAddress;

  const MapPickerPage({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialAddress,
  });

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  InAppWebViewController? _webViewController;
  bool _isLocating = true;
  bool _isLoading = true;
  bool _isFetchingDetails = false;
  String? _errorMessage;

  // Initial center default
  double _currentLat = 3.1390;
  double _currentLng = 101.6869;

  late String _pickedAddressSummary = widget.initialAddress?.isNotEmpty == true
      ? widget.initialAddress!
      : 'Tap or drag map to point delivery location';

  @override
  void initState() {
    super.initState();
    _loadInitialLocation();
  }

  Future<void> _loadInitialLocation() async {
    // If a selected location was passed in (e.g. from existing profile/staff work location), use it directly
    if (widget.initialLat != null && widget.initialLng != null) {
      final lat = widget.initialLat!;
      final lng = widget.initialLng!;
      if (mounted) {
        setState(() {
          _currentLat = lat;
          _currentLng = lng;
          _isLocating = false;
        });
        _onLocationReceived(lat, lng);
      }
      return;
    }

    final loc = await AddressService.getCurrentLocation();
    double lat = 3.1390;
    double lng = 101.6869;
    if (loc['success'] == true && loc['lat'] != null && loc['lng'] != null) {
      lat = (loc['lat'] as num).toDouble();
      lng = (loc['lng'] as num).toDouble();
    }
    if (mounted) {
      setState(() {
        _currentLat = lat;
        _currentLng = lng;
        _isLocating = false;
      });
      _onLocationReceived(lat, lng);
    }
  }

  Future<void> _recenterToGps() async {
    setState(() => _isFetchingDetails = true);
    final loc = await AddressService.getCurrentLocation();
    if (loc['success'] == true && loc['lat'] != null && loc['lng'] != null) {
      final lat = (loc['lat'] as num).toDouble();
      final lng = (loc['lng'] as num).toDouble();
      _webViewController?.evaluateJavascript(source: 'if (window.moveToPosition) { window.moveToPosition($lat, $lng, 16); }');
      _onLocationReceived(lat, lng);
    } else {
      setState(() => _isFetchingDetails = false);
    }
  }

  String _buildLeafletHtml() {
    final startLat = _currentLat;
    final startLng = _currentLng;

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    html, body, #map {
      height: 100%;
      width: 100%;
      margin: 0;
      padding: 0;
    }
    .leaflet-control-attribution {
      font-size: 9px;
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var startLat = $startLat;
    var startLng = $startLng;

    var map = L.map('map', {
      zoomControl: false,
      attributionControl: false
    }).setView([startLat, startLng], 16);

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19
    }).addTo(map);

    L.control.zoom({ position: 'topright' }).addTo(map);

    // Initial marker at detected location
    var marker = L.marker([startLat, startLng], { draggable: true }).addTo(map);

    function notifyPosition(lat, lng) {
      if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('onLocationPicked', { lat: lat, lng: lng });
      }
    }

    // Allow Flutter to smoothly reposition without destroying/reloading webview
    window.moveToPosition = function(lat, lng, zoom) {
      if (marker) {
        marker.setLatLng([lat, lng]);
      }
      if (map) {
        map.setView([lat, lng], zoom || map.getZoom());
      }
    };

    marker.on('dragend', function(e) {
      var coord = marker.getLatLng();
      notifyPosition(coord.lat, coord.lng);
    });

    map.on('click', function(e) {
      marker.setLatLng(e.latlng);
      notifyPosition(e.latlng.lat, e.latlng.lng);
    });

    // Notify initial coordinates provided directly by Flutter
    setTimeout(function() {
      notifyPosition(startLat, startLng);
    }, 150);
  </script>
</body>
</html>
''';
  }

  Future<void> _onLocationReceived(double lat, double lng) async {
    setState(() {
      _currentLat = lat;
      _currentLng = lng;
      _isFetchingDetails = true;
      _errorMessage = null;
    });

    final res = await AddressService.reverseGeocode(lat, lng);

    if (!mounted) return;

    if (res['success'] == true && res['isMalaysia'] == true) {
      final addr = res['address'] as Map<String, dynamic>? ?? {};
      final line = addr['addressLine']?.toString() ?? '';
      final post = addr['postcode']?.toString() ?? '';
      final city = addr['city']?.toString() ?? '';
      final state = addr['state']?.toString() ?? '';

      final parts = [line, post, city, state].where((s) => s.trim().isNotEmpty).toList();
      setState(() {
        _isFetchingDetails = false;
        _pickedAddressSummary = parts.isNotEmpty ? parts.join(', ') : 'Location pointed inside Malaysia';
      });
    } else {
      final err = res['error']?.toString() ?? 'Sorry, only able to select Malaysia region';
      setState(() {
        _isFetchingDetails = false;
        _errorMessage = err;
        _pickedAddressSummary = 'Non-Malaysia location selected';
      });
    }
  }

  void _confirmSelection() async {
    if (_errorMessage != null) {
      _showErrorDialog(_errorMessage!);
      return;
    }

    setState(() => _isFetchingDetails = true);
    final res = await AddressService.reverseGeocode(_currentLat, _currentLng);
    if (!mounted) return;
    setState(() => _isFetchingDetails = false);

    if (res['success'] == true && res['isMalaysia'] == true) {
      final addr = Map<String, dynamic>.from(res['address'] as Map? ?? {});
      addr['lat'] = _currentLat;
      addr['lng'] = _currentLng;
      Navigator.pop(context, addr);
    } else {
      final err = res['error']?.toString() ?? 'Sorry, only able to select Malaysia region';
      _showErrorDialog(err);
    }
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Color(0xFFE11D48), size: 24),
            SizedBox(width: 8),
            Text(
              'Location Error',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5, color: Color(0xFF0F254B)),
            ),
          ],
        ),
        content: Text(
          msg,
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0C5AD2),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A), size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Point Location on Map',
          style: TextStyle(
            color: Color(0xFF0F254B),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location, color: Color(0xFF0C5AD2)),
            tooltip: 'Re-center to my location',
            onPressed: _recenterToGps,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_isLocating)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF0C5AD2)),
                  SizedBox(height: 14),
                  Text(
                    'Detecting current GPS location...',
                    style: TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Leaflet Interactive OpenStreetMap WebView
            InAppWebView(
              key: const ValueKey('map_picker_webview'),
              initialData: InAppWebViewInitialData(data: _buildLeafletHtml()),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                transparentBackground: false,
                supportMultipleWindows: false,
                geolocationEnabled: true,
              ),
              onGeolocationPermissionsShowPrompt: (controller, origin) async {
                return GeolocationPermissionShowPromptResponse(
                  origin: origin,
                  allow: true,
                  retain: true,
                );
              },
              onWebViewCreated: (controller) {
                _webViewController = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'onLocationPicked',
                  callback: (args) {
                    if (args.isNotEmpty && args[0] is Map) {
                      final lat = (args[0]['lat'] as num?)?.toDouble() ?? _currentLat;
                      final lng = (args[0]['lng'] as num?)?.toDouble() ?? _currentLng;
                      _onLocationReceived(lat, lng);
                    }
                  },
                );
              },
              onLoadStop: (controller, url) {
                setState(() => _isLoading = false);
              },
            ),

            // Loading overlay
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              ),
          ],

          // Instruction pill on top
          Positioned(
            top: 14,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F254B).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.touch_app_outlined, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap or drag pin to your delivery address in Malaysia',
                      style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom card showing resolved address details & Confirm Button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(context).padding.bottom + 18,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _errorMessage != null
                              ? const Color(0xFFFFE4E6)
                              : const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _errorMessage != null ? Icons.warning_amber_rounded : Icons.location_on,
                          color: _errorMessage != null ? const Color(0xFFE11D48) : const Color(0xFF0C5AD2),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage != null ? 'Invalid Location' : 'Selected Location',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _errorMessage != null ? const Color(0xFFE11D48) : const Color(0xFF0F254B),
                          ),
                        ),
                      ),
                      if (_isFetchingDetails)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Text(
                    _errorMessage ?? _pickedAddressSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: _errorMessage != null ? const Color(0xFFE11D48) : const Color(0xFF475569),
                      fontWeight: _errorMessage != null ? FontWeight.w600 : FontWeight.w400,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isFetchingDetails ? null : _confirmSelection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _errorMessage != null ? const Color(0xFF94A3B8) : const Color(0xFF0C5AD2),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'Confirm Location & Auto-Fill',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
