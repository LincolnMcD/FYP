import '../models/device_model.dart';
import '../upload_device_images_page.dart';

/// In-memory manager for the active trade-in flow.
/// Keeps current trade-in request state while the user is navigating within
/// the trade-in flow (Pages 2, 3, 4).
///
/// If the user leaves the flow completely (e.g. Navigates to Profile, Shop,
/// or goes back to Page 1 Landing Page), this session is cleared from memory.
class TradeInFlowSession {
  static String? _currentTradeInRequestId;
  static String? _currentDeviceId;
  static DeviceModel? _currentDevice;
  static List<ImageSlotItem>? _savedSlots;
  static final Map<String, String> _uploadedImagePaths = {};
  static final Set<String> _pendingRemovedImageViews = {};
  static Future<void>? _backgroundUploadFuture;

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
  }

  /// Sets the active device ID
  static void setDeviceId(String? id) {
    _currentDeviceId = id;
  }

  /// Sets current device specifications
  static void setCurrentDevice(DeviceModel? device) {
    _currentDevice = device;
    if (device != null && device.deviceID.isNotEmpty) {
      _currentDeviceId = device.deviceID;
    }
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
  }

  /// Clears the active trade-in session from app memory.
  /// Used when leaving the trade-in flow completely (going to Profile/Shop/Home,
  /// popping back to Page 1, or after Final Submit).
  /// Note: The Firestore Pending record remains intact in the cloud.
  static void clear() {
    _currentTradeInRequestId = null;
    _currentDeviceId = null;
    _currentDevice = null;
    _savedSlots = null;
    _uploadedImagePaths.clear();
    _pendingRemovedImageViews.clear();
    _backgroundUploadFuture = null;
  }
}
