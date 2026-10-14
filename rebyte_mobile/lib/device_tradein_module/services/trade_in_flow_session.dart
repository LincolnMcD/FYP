import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import '../upload_device_images_page.dart';

/// In-memory and persistent manager for the active trade-in flow.
/// Keeps current trade-in request state while the user is navigating within
/// the trade-in flow. Also persists active Page 5 state to SharedPreferences
/// so the Active Activity card remains present if the user closes and reopens the app.
class TradeInFlowSession {
  static const String _prefKeyReqId = 'active_tradein_req_id';
  static const String _prefKeyDeviceId = 'active_tradein_dev_id';
  static const String _prefKeyDeviceJson = 'active_tradein_device_json';
  static const String _prefKeyStep = 'active_tradein_step';
  static const String _prefKeyImei = 'active_tradein_imei';
  static const String _prefKeyUserEmail = 'active_tradein_user_email';

  static String? _currentTradeInRequestId;
  static String? _currentDeviceId;
  static DeviceModel? _currentDevice;
  static List<ImageSlotItem>? _savedSlots;
  static final Map<String, String> _uploadedImagePaths = {};
  static final Set<String> _pendingRemovedImageViews = {};
  static Future<void>? _backgroundUploadFuture;
  static int _currentStep = 1;
  static String? _lastEnteredImei;
  static String? _currentUserEmail;
  static bool _hasLoadedFromPrefs = false;

  /// Current session user email
  static String? get currentUserEmail => _currentUserEmail;
  static set currentUserEmail(String? email) {
    _currentUserEmail = email;
    _saveToPrefs();
  }

  /// The active step in the trade-in flow (1: Info, 2: Info form, 3: Images, 4: IMEI, 5: Improve Assessment, 6: Assessment Loading, 7: Assessment Result, 8: Quotation Offer)
  static int get currentStep => _currentStep;
  static set currentStep(int step) {
    _currentStep = step;
    _saveToPrefs();
  }

  /// Returns true if the user has reached Page 5 ("Improve Your Assessment") or beyond
  static bool get isAtPage5 => _currentStep >= 5;

  /// Returns true if the user has reached Page 7 ("Overall Condition / Assessment Result")
  static bool get isAtPage7 => _currentStep >= 7;

  /// Returns true if the user has reached Page 8 ("Preliminary Trade-In Quotation")
  static bool get isAtPage8 => _currentStep >= 8;

  /// Stored IMEI validated in Page 4
  static String? get lastEnteredImei => _lastEnteredImei;
  static set lastEnteredImei(String? imei) {
    _lastEnteredImei = imei;
    _saveToPrefs();
  }

  /// Background upload Future for asynchronous image sync
  static Future<void>? get backgroundUploadFuture => _backgroundUploadFuture;
  static void setBackgroundUploadFuture(Future<void>? future) {
    _backgroundUploadFuture = future;
  }

  /// The active in-memory trade-in request ID (e.g. TRYYMMDD00001)
  static String? get currentTradeInRequestId => _currentTradeInRequestId;

  /// The active in-memory device ID
  static String? get currentDeviceId => _currentDeviceId;

  /// Cached device specification values to preserve when user edits in Page 2
  static DeviceModel? get currentDevice => _currentDevice;

  /// Cached image slots to preserve image states when user returns to Page 3
  static List<ImageSlotItem>? get savedSlots => _savedSlots;

  /// Map of slot keyName -> localFilePath for already uploaded images
  static Map<String, String> get uploadedImagePaths => _uploadedImagePaths;

  /// List of imageView names that were deleted/cleared by the user
  static List<String> get pendingRemovedImageViews => _pendingRemovedImageViews.toList();

  /// Record an uploaded image's local path
  static void markImageUploaded(String keyName, String path) {
    _uploadedImagePaths[keyName] = path;
    _pendingRemovedImageViews.remove(keyName);
  }

  /// Remove an image from uploaded paths tracking when user deletes it
  static void removeUploadedImage(String keyName) {
    _uploadedImagePaths.remove(keyName);
    _pendingRemovedImageViews.add(keyName);
  }

  /// Clear pending removed list after successful backend sync
  static void clearPendingRemovedImages() {
    _pendingRemovedImageViews.clear();
  }

  /// Check if an image in slot keyName has changed since last upload
  static bool hasImageChanged(String keyName, String currentPath) {
    return _uploadedImagePaths[keyName] != currentPath;
  }

  /// Returns true if a trade-in flow is currently active in memory
  static bool get hasActiveFlow =>
      _currentTradeInRequestId != null && _currentTradeInRequestId!.isNotEmpty;

  /// Sets the active trade-in request ID
  static void setTradeInRequestId(String? id) {
    _currentTradeInRequestId = id;
    _saveToPrefs();
  }

  /// Sets the active device ID
  static void setDeviceId(String? id) {
    _currentDeviceId = id;
    _saveToPrefs();
  }

  /// Sets current device specifications
  static void setCurrentDevice(DeviceModel? device) {
    _currentDevice = device;
    if (device != null && device.deviceID.isNotEmpty) {
      _currentDeviceId = device.deviceID;
    }
    _saveToPrefs();
  }

  /// Saves the active image slots
  static void saveSlots(List<ImageSlotItem>? slots) {
    _savedSlots = slots;
  }

  /// Starts or resumes a flow session
  static void startOrResume({
    String? tradeInRequestId,
    DeviceModel? device,
    List<ImageSlotItem>? slots,
  }) {
    if (tradeInRequestId != null && tradeInRequestId.isNotEmpty) {
      _currentTradeInRequestId = tradeInRequestId;
    }
    if (device != null) {
      _currentDevice = device;
      _currentDeviceId = device.deviceID;
    }
    if (slots != null) {
      _savedSlots = slots;
    }
    _saveToPrefs();
  }

  /// Restore active session from persistent storage (SharedPreferences)
  static Future<void> loadFromPrefs({String? loggedInUserEmail}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? reqId = prefs.getString(_prefKeyReqId);
      final int step = prefs.getInt(_prefKeyStep) ?? 1;
      final String? savedEmail = prefs.getString(_prefKeyUserEmail);

      // If a specific loggedInUserEmail is provided and it doesn't match, don't load
      if (loggedInUserEmail != null && loggedInUserEmail.isNotEmpty && savedEmail != null && savedEmail.isNotEmpty) {
        if (savedEmail.toLowerCase() != loggedInUserEmail.toLowerCase()) {
          _hasLoadedFromPrefs = true;
          return;
        }
      }

      final String? devJsonStr = prefs.getString(_prefKeyDeviceJson);
      if (devJsonStr != null && devJsonStr.isNotEmpty) {
        try {
          final Map<String, dynamic> devMap = jsonDecode(devJsonStr);
          _currentDevice = DeviceModel.fromJson(devMap);
        } catch (_) {}
      }
      final String? savedDevId = prefs.getString(_prefKeyDeviceId);
      if (savedDevId != null && savedDevId.isNotEmpty) {
        _currentDeviceId = savedDevId;
      }

      if (reqId != null && reqId.isNotEmpty) {
        _currentTradeInRequestId = reqId;
      }
      _currentStep = step;
      _lastEnteredImei = prefs.getString(_prefKeyImei);
      _currentUserEmail = savedEmail;
      _hasLoadedFromPrefs = true;
    } catch (_) {}
  }

  static bool get hasLoadedFromPrefs => _hasLoadedFromPrefs;

  /// Save active Page 5 session to SharedPreferences
  static Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_currentDevice != null) {
        await prefs.setString(_prefKeyDeviceJson, jsonEncode(_currentDevice!.toJson()));
      }
      if (_currentDeviceId != null) {
        await prefs.setString(_prefKeyDeviceId, _currentDeviceId!);
      }
      if (_currentTradeInRequestId != null) {
        await prefs.setString(_prefKeyReqId, _currentTradeInRequestId!);
      }
      await prefs.setInt(_prefKeyStep, _currentStep);
      if (_lastEnteredImei != null) {
        await prefs.setString(_prefKeyImei, _lastEnteredImei!);
      }
      if (_currentUserEmail != null) {
        await prefs.setString(_prefKeyUserEmail, _currentUserEmail!);
      }
    } catch (_) {}
  }

  /// Clears the active trade-in session from app memory AND SharedPreferences.
  /// Called when the user starts a fresh trade-in or when the process completes.
  static void clear() {
    _currentTradeInRequestId = null;
    _currentDeviceId = null;
    _currentDevice = null;
    _savedSlots = null;
    _uploadedImagePaths.clear();
    _pendingRemovedImageViews.clear();
    _backgroundUploadFuture = null;
    _currentStep = 1;
    _lastEnteredImei = null;
    _currentUserEmail = null;
    _clearPrefs();
  }

  static Future<void> _clearPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyReqId);
      await prefs.remove(_prefKeyDeviceId);
      await prefs.remove(_prefKeyDeviceJson);
      await prefs.remove(_prefKeyStep);
      await prefs.remove(_prefKeyImei);
      await prefs.remove(_prefKeyUserEmail);
    } catch (_) {}
  }
}

