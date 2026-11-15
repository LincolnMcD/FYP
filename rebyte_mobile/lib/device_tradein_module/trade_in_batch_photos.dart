import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import '../account_management_module/services/app_route_observer.dart';
import 'models/image_slot_item.dart';
import 'services/trade_in_service.dart';

mixin TradeInBatchPhotos<Page extends StatefulWidget> on State<Page>
    implements RouteAware {
  List<ImageSlotItem> get photoSlots;
  set photoSlots(List<ImageSlotItem> slots);
  void onSharedPhotosChanged();
  bool get photoEditsBlocked => false;
  final _batchImagePicker = ImagePicker();

  @override
  void dispose() {
    appPageRouteObserver.unsubscribe(this);
    _cancelBulkProcessing();
    _dismissErrorToast();
    super.dispose();
  }

  @override
  void didPush() {}

  @override
  void didPop() => _cancelBulkProcessing();

  @override
  void didPopNext() {}

  Completer<void>? _bulkCancellation;
  PageRoute<dynamic>? _observedRoute;
  bool get bulkPhotoBusy => _bulkCancellation != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _observedRoute) return;
    appPageRouteObserver.unsubscribe(this);
    _observedRoute = route is PageRoute<dynamic> ? route : null;
    if (_observedRoute != null) {
      appPageRouteObserver.subscribe(this, _observedRoute!);
    }
  }

  @override
  void didPushNext() {
    if (bulkPhotoBusy) setState(_cancelBulkProcessing);
  }

  void _cancelBulkProcessing() {
    _bulkCancellation?.complete();
    _bulkCancellation = null;
  }

  OverlayEntry? _errorToast;
  Timer? _toastTimer;
  bool get canPickMultiplePhotos =>
      !photoEditsBlocked &&
      !bulkPhotoBusy &&
      !photoSlots.any((slot) => slot.status == ImageSlotStatus.uploading) &&
      photoSlots.any((slot) => slot.status != ImageSlotStatus.success);

  Widget _photoPreviewImage(
    String path, {
    required ImageErrorWidgetBuilder errorBuilder,
  }) {
    return path.startsWith('https://') || path.startsWith('http://')
        ? Image.network(path, fit: BoxFit.contain, errorBuilder: errorBuilder)
        : Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: errorBuilder,
          );
  }

  static const _partSlots = {
    'mobile-phone-back-view': 'back',
    'mobile-phone-bottom-view': 'frame_bottom',
    'mobile-phone-camera-view': 'camera_area',
    'mobile-phone-right-view': 'frame_right',
    'mobile-phone-top-view': 'frame_top',
    'mobile-phone-left-view': 'any_angles',
  };

  Future<List<XFile>> _pickGalleryPhotos(int limit) async {
    final platform = ImagePickerPlatform.instance;
    if (platform is! ImagePickerAndroid) {
      return _batchImagePicker.pickMultiImage(limit: limit);
    }
    final previousSetting = platform.useAndroidPhotoPicker;
    platform.useAndroidPhotoPicker = true;
    try {
      return await _batchImagePicker.pickMultiImage(limit: limit);
    } finally {
      platform.useAndroidPhotoPicker = previousSetting;
    }
  }

  void _dismissErrorToast() {
    _toastTimer?.cancel();
    _errorToast?.remove();
    _errorToast?.dispose();
    _errorToast = null;
  }

  void _showErrorToast(String message) {
    _dismissErrorToast();
    final top = MediaQuery.paddingOf(context).top + 8;
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: top,
        left: 16,
        right: 16,
        child: Material(
          color: const Color(0xFFE11D48),
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    _errorToast = entry;
    _toastTimer = Timer(const Duration(seconds: 3), _dismissErrorToast);
  }

  Future<void> _pickMultipleImages() async {
    if (!canPickMultiplePhotos) return;
    final cancellation = Completer<void>();
    setState(() => _bulkCancellation = cancellation);
    bool isActive() => mounted && identical(_bulkCancellation, cancellation);
    try {
      final staged = List<ImageSlotItem>.of(photoSlots);
      final remaining = staged
          .where((slot) => slot.status != ImageSlotStatus.success)
          .length;
      final photos = await _pickGalleryPhotos(remaining);
      if (!isActive() || photos.isEmpty) return;
      if (photos.length > remaining) {
        _showErrorToast(
          'Select up to $remaining more photos. '
          'The limit is 8, including existing photos.',
        );
        return;
      }

      final groups = <int, List<XFile>>{};
      final rejected = <({XFile photo, String reason})>[];
      for (final photo in photos) {
        final String issue;
        if (!RegExp(
              r'\.(jpe?g|png)$',
              caseSensitive: false,
            ).hasMatch(photo.name) &&
            !RegExp(
              r'\.(jpe?g|png)$',
              caseSensitive: false,
            ).hasMatch(photo.path)) {
          issue = 'Only JPG, JPEG, and PNG are supported.';
        } else if (await photo.length() > 5 * 1024 * 1024) {
          issue = 'Photo exceeds 5 MB.';
        } else {
          if (!isActive()) return;
          final result = await TradeInService.detectPhone(
            photo.path,
            maxRetries: 1,
            abortTrigger: cancellation.future,
          );
          if (!isActive()) return;
          if (result['success'] != true) {
            issue = 'Phone verification failed. Please try again.';
          } else if (result['isPhone'] != true) {
            issue = 'No smartphone detected.';
          } else {
            final detections =
                (result['detections'] as List<dynamic>)
                    .cast<Map<String, dynamic>>()
                    .toList()
                  ..sort(
                    (a, b) => (b['confidence'] as num).compareTo(
                      a['confidence'] as num,
                    ),
                  );
            int? preferredSlot;
            int? availableSlot;
            bool removed = false;
            for (final detection in detections) {
              final category = detection['class'];
              String? key = _partSlots[category];
              if (category == 'mobile-phone-front-view') {
                key = await _choosePhotoOption<String>(
                  title: 'Was the screen on or off?',
                  previewPath: photo.path,
                  options: const [
                    (
                      value: 'front_screen_open',
                      label: 'Screen On',
                      path: null,
                    ),
                    (
                      value: 'front_screen_closed',
                      label: 'Screen Off',
                      path: null,
                    ),
                  ],
                );
                if (!isActive()) return;
                if (key == null) {
                  removed = true;
                  break;
                }
              }
              final index = staged.indexWhere((slot) => slot.keyName == key);
              if (index < 0) continue;
              preferredSlot ??= index;
              if (staged[index].status != ImageSlotStatus.success &&
                  !groups.containsKey(index)) {
                availableSlot = index;
                break;
              }
            }
            if (removed) continue;
            final index = availableSlot ?? preferredSlot;
            if (index != null) {
              groups.putIfAbsent(index, () => []).add(photo);
              continue;
            }
            issue = 'No smartphone part detected.';
          }
        }
        rejected.add((photo: photo, reason: issue));
      }

      final extras = <XFile>[];
      for (final entry in groups.entries) {
        final slot = staged[entry.key];
        final existing = slot.status == ImageSlotStatus.success
            ? XFile(slot.localFilePath!, name: slot.fileName)
            : null;
        final candidates = [?existing, ...entry.value];
        final chosen = candidates.length == 1
            ? candidates.single
            : await _choosePhotoOption<XFile>(
                title: 'Which photo should be used for ${slot.label}?',
                options: [
                  for (final (index, photo) in candidates.indexed)
                    (
                      value: photo,
                      label: photo == existing
                          ? 'Current photo'
                          : 'Photo ${index + 1}',
                      path: photo.path,
                    ),
                ],
                allowRemove: false,
              );
        if (!isActive() || chosen == null) return;
        staged[entry.key] = _verifiedPhoto(slot, chosen);
        extras.addAll(candidates.where((photo) => photo != chosen));
      }

      for (final photo in extras) {
        final index = await _choosePhotoOption<int>(
          title: 'Choose a part for the remaining photo',
          previewPath: photo.path,
          options: [
            for (final (index, slot) in staged.indexed)
              if (slot.status != ImageSlotStatus.success)
                (value: index, label: slot.label, path: null),
          ],
        );
        if (!isActive()) return;
        if (index != null) staged[index] = _verifiedPhoto(staged[index], photo);
      }

      setState(() => photoSlots = staged);
      onSharedPhotosChanged();
      if (rejected.isNotEmpty) {
        await _choosePhotoOption<int>(
          title: 'Photos that couldn’t be added',
          options: [
            for (final item in rejected)
              (value: 0, label: item.reason, path: item.photo.path),
          ],
          dismissOnly: true,
        );
      }
    } catch (_) {
      if (!isActive()) return;
      _showErrorToast('Could not process the selected photos.');
    } finally {
      if (isActive()) setState(_cancelBulkProcessing);
    }
  }

  ImageSlotItem _verifiedPhoto(ImageSlotItem slot, XFile photo) =>
      slot.reset().copyWith(
        localFilePath: photo.path,
        fileName: photo.name,
        status: ImageSlotStatus.success,
        uploadProgress: 1,
      );

  bool get canCancelAllPhotos =>
      !photoEditsBlocked &&
      !bulkPhotoBusy &&
      !photoSlots.any((slot) => slot.status == ImageSlotStatus.uploading);

  Future<void> _confirmCancelAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Remove all photos?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: Color(0xFF64748B),
                    ),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'All uploaded photos will be removed. You can upload new photos afterward.',
                style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'CANCEL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFFB91C1C),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'REMOVE ALL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
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
    );
    if (!mounted || confirmed != true || !canCancelAllPhotos) return;
    setState(
      () => photoSlots = photoSlots.map((slot) => slot.reset()).toList(),
    );
    onSharedPhotosChanged();
  }

  static const photoDialogBlue = Color(0xFF003799);

  Widget _expandablePhoto(BuildContext context, String path, double height) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: const Color(0xFFEFF4FA),
        child: InkWell(
          onTap: () => _openPhotoPreview(context, path),
          child: Semantics(
            button: true,
            label: 'Enlarge photo',
            child: SizedBox(
              width: double.infinity,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _photoPreviewImage(
                    path,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
                  const Positioned(
                    right: 8,
                    bottom: 8,
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: Colors.white,
                      foregroundColor: photoDialogBlue,
                      child: Icon(Icons.zoom_in, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPhotoPreview(BuildContext context, String path) =>
      showDialog<void>(
        context: context,
        useSafeArea: false,
        builder: (previewContext) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            leading: IconButton(
              tooltip: 'Close photo preview',
              onPressed: () => Navigator.pop(previewContext),
              icon: const Icon(Icons.close),
            ),
            title: const Text('Photo preview'),
          ),
          body: SafeArea(
            child: SizedBox.expand(
              child: InteractiveViewer(
                maxScale: 5,
                child: _photoPreviewImage(
                  path,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Future<T?> _choosePhotoOption<T>({
    required String title,
    required List<({T value, String label, String? path})> options,
    String? previewPath,
    bool allowRemove = true,
    bool dismissOnly = false,
  }) => showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        scrollable: true,
        content: SizedBox(
          width: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (previewPath != null) ...[
                _expandablePhoto(dialogContext, previewPath, 170),
                const SizedBox(height: 12),
              ],
              for (final option in options)
                Card(
                  elevation: 0,
                  color: const Color(0xFFF8F9FB),
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      if (option.path != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: _expandablePhoto(
                            dialogContext,
                            option.path!,
                            126,
                          ),
                        ),
                      ListTile(
                        title: Text(option.label),
                        trailing: dismissOnly
                            ? null
                            : const Icon(
                                Icons.chevron_right,
                                color: photoDialogBlue,
                              ),
                        onTap: dismissOnly
                            ? null
                            : () => Navigator.pop(dialogContext, option.value),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (dismissOnly)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: photoDialogBlue),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            )
          else if (allowRemove)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
              ),
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove photo'),
            ),
        ],
      ),
    ),
  );

  Widget buildBatchPhotoControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: canPickMultiplePhotos ? _pickMultipleImages : null,
        icon: bulkPhotoBusy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.photo_library_outlined),
        label: Text(
          bulkPhotoBusy
              ? 'Checking photos…'
              : 'Select Multiple Photos (${photoSlots.where((slot) => slot.status == ImageSlotStatus.success).length}/8)',
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Press and hold a photo, then drag it to another slot to move or swap it.',
        style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
      ),
      const SizedBox(height: 8),
      if (photoSlots
              .where((slot) => slot.status == ImageSlotStatus.success)
              .length >
          1)
        TextButton.icon(
          onPressed: canCancelAllPhotos ? _confirmCancelAll : null,
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFB91C1C)),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Cancel All'),
        ),
    ],
  );

  bool _canMovePhoto(int from, int to) =>
      !photoEditsBlocked &&
      !bulkPhotoBusy &&
      from != to &&
      photoSlots[from].status == ImageSlotStatus.success &&
      photoSlots[to].status != ImageSlotStatus.uploading;

  void _movePhoto(int from, int to) {
    if (!_canMovePhoto(from, to)) return;
    final source = photoSlots[from];
    final destination = photoSlots[to];
    setState(() {
      photoSlots[to] = _slotWithPhoto(destination, source);
      photoSlots[from] = destination.status == ImageSlotStatus.success
          ? _slotWithPhoto(source, destination)
          : source.reset();
    });
    onSharedPhotosChanged();
  }

  ImageSlotItem _slotWithPhoto(ImageSlotItem slot, ImageSlotItem photo) =>
      slot.reset().copyWith(
        localFilePath: photo.localFilePath,
        previewBase64: photo.previewBase64,
        fileName: photo.fileName,
        status: ImageSlotStatus.success,
        uploadProgress: 1,
      );

  Widget buildMovablePhotoSlot(
    int index,
    double width,
    double height,
    Widget card,
  ) {
    final Widget draggable =
        !photoEditsBlocked &&
            !bulkPhotoBusy &&
            photoSlots[index].status == ImageSlotStatus.success
        ? LongPressDraggable<int>(
            data: index,
            maxSimultaneousDrags: 1,
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(width: width, height: height, child: card),
            ),
            childWhenDragging: Opacity(opacity: 0.4, child: card),
            child: card,
          )
        : card;

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => _canMovePhoto(details.data, index),
      onAcceptWithDetails: (details) => _movePhoto(details.data, index),
      builder: (_, candidates, _) => candidates.isEmpty
          ? draggable
          : DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF003799), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: draggable,
            ),
    );
  }
}
