import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../../account_management_module/services/auth_service.dart';

/// Real-time Socket.IO service for live delivery tracking between Delivery Staff and Customer
class DeliverySocketService {
  socket_io.Socket? _socket;
  String? _currentRoom;
  String? _currentOrderID;
  String? _role;

  bool get isConnected => _socket?.connected ?? false;
  String? get role => _role;

  /// Connect to Socket.IO server, join delivery room `delivery:<orderID>`, and register event callbacks
  void connect({
    required String orderID,
    required String role, // 'staff' or 'customer'
    String? tradeInRequestID,
    String? taskID,
    String? appointmentID,
    void Function(Map<String, dynamic> locationData)? onLocationUpdate,
    void Function(Map<String, dynamic> completionData)? onDeliveryCompleted,
    VoidCallback? onConnect,
    VoidCallback? onDisconnect,
  }) {
    final cleanOrderID = orderID.replaceAll('#', '').trim();
    _currentOrderID = cleanOrderID;
    _currentRoom = 'delivery:$cleanOrderID';
    _role = role;

    final serverUrl = AuthService.baseUrl;

    try {
      if (_socket != null) {
        _socket!.dispose();
        _socket = null;
      }

      debugPrint('[DeliverySocketService] Connecting to $serverUrl for room $_currentRoom ($role)...');

      _socket = socket_io.io(
        serverUrl,
        socket_io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionDelay(1000)
            .setReconnectionAttempts(10)
            .build(),
      );

      _socket!.onConnect((_) {
        debugPrint('[DeliverySocketService] Connected to Socket.IO server: ${_socket?.id}');
        // Join the delivery room
        _socket!.emit('join-delivery', {
          'orderID': cleanOrderID,
          if (tradeInRequestID != null) 'tradeInRequestID': tradeInRequestID.replaceAll('#', '').trim(),
          if (taskID != null) 'taskID': taskID.replaceAll('#', '').trim(),
          if (appointmentID != null) 'appointmentID': appointmentID.replaceAll('#', '').trim(),
          'role': role,
        });
        onConnect?.call();
      });

      _socket!.onDisconnect((_) {
        debugPrint('[DeliverySocketService] Disconnected from Socket.IO server');
        onDisconnect?.call();
      });

      _socket!.onConnectError((err) {
        debugPrint('[DeliverySocketService] Connection error: $err');
      });

      // Listen for staff live GPS location updates (for customer app)
      _socket!.on('staff-location-update', (data) {
        debugPrint('[DeliverySocketService] Received staff-location-update: $data');
        if (data is Map && onLocationUpdate != null) {
          onLocationUpdate(Map<String, dynamic>.from(data));
        }
      });

      // Listen for delivery completion event (for customer app)
      _socket!.on('delivery-completed', (data) {
        debugPrint('[DeliverySocketService] Received delivery-completed: $data');
        if (data is Map && onDeliveryCompleted != null) {
          onDeliveryCompleted(Map<String, dynamic>.from(data));
        }
      });
    } catch (e) {
      debugPrint('[DeliverySocketService] Exception initializing socket: $e');
    }
  }

  /// Staff emits live GPS coordinates, distance, and duration to the delivery room
  void sendLocation({
    required String orderID,
    String? tradeInRequestID,
    String? taskID,
    String? appointmentID,
    required double lat,
    required double lng,
    double heading = 0.0,
    double speed = 0.0,
    double? estimatedDistanceKm,
    int? estimatedDurationMinutes,
  }) {
    if (_socket == null || !_socket!.connected) return;

    final cleanOrderID = orderID.replaceAll('#', '').trim();
    _socket!.emit('send-location', {
      'orderID': cleanOrderID,
      if (tradeInRequestID != null) 'tradeInRequestID': tradeInRequestID.replaceAll('#', '').trim(),
      if (taskID != null) 'taskID': taskID.replaceAll('#', '').trim(),
      if (appointmentID != null) 'appointmentID': appointmentID.replaceAll('#', '').trim(),
      'lat': lat,
      'lng': lng,
      'heading': heading,
      'speed': speed,
      if (estimatedDistanceKm != null) 'estimatedDistanceKm': estimatedDistanceKm,
      if (estimatedDurationMinutes != null) 'estimatedDurationMinutes': estimatedDurationMinutes,
    });
  }

  /// Staff emits delivery completed event to the room
  void emitDeliveryCompleted({
    required String orderID,
    String? proofOfDeliveryUrl,
  }) {
    if (_socket == null || !_socket!.connected) return;

    final cleanOrderID = orderID.replaceAll('#', '').trim();
    _socket!.emit('delivery-completed', {
      'orderID': cleanOrderID,
      'proofOfDeliveryUrl': proofOfDeliveryUrl,
    });
  }


  /// Leave the delivery room
  void leaveRoom([String? orderID]) {
    final idToLeave = orderID?.replaceAll('#', '').trim() ?? _currentOrderID;
    if (_socket != null && _socket!.connected && idToLeave != null) {
      _socket!.emit('leave-delivery', {'orderID': idToLeave});
      debugPrint('[DeliverySocketService] Left room delivery:$idToLeave');
    }
  }

  /// Completely disconnect and dispose socket
  void dispose() {
    leaveRoom();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _currentRoom = null;
    _currentOrderID = null;
    _role = null;
    debugPrint('[DeliverySocketService] Disposed');
  }
}
