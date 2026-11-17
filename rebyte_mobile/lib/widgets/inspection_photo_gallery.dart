import 'dart:io';

import 'package:flutter/material.dart';

class InspectionPhotoGallery extends StatefulWidget {
  final List<({String? url, String? filePath, String caption})> photos;
  final int initialIndex;

  const InspectionPhotoGallery({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<InspectionPhotoGallery> createState() => _InspectionPhotoGalleryState();
}

class _InspectionPhotoGalleryState extends State<InspectionPhotoGallery> {
  late int _index = widget.initialIndex;
  late final _pages = PageController(initialPage: _index);
  late final _transforms = List.generate(
    widget.photos.length,
    (_) => TransformationController(),
  );
  bool _zoomed = false;

  void _updateZoom(int index) {
    if (index != _index) return;
    final zoomed = _transforms[index].value.getMaxScaleOnAxis() > 1.01;
    if (_zoomed != zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final transform in _transforms) {
      transform.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 600,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.photos[_index].caption,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF334155)),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                itemCount: widget.photos.length,
                onPageChanged: (index) => setState(() {
                  _index = index;
                  _zoomed = false;
                }),
                itemBuilder: (context, index) {
                  final photo = widget.photos[index];
                  final url = photo.url;
                  final filePath = photo.filePath;
                  const unavailable = Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 48,
                  );
                  return InteractiveViewer(
                    transformationController: _transforms[index],
                    panEnabled: _zoomed && index == _index,
                    maxScale: 4,
                    onInteractionUpdate: (_) => _updateZoom(index),
                    onInteractionEnd: (_) => _updateZoom(index),
                    child: Center(
                      child: url != null && url.isNotEmpty
                          ? Image.network(
                              url,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => unavailable,
                            )
                          : filePath != null
                          ? Image.file(
                              File(filePath),
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) => unavailable,
                            )
                          : unavailable,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.photos.length > 1
                    ? '${_index + 1} / ${widget.photos.length} · Swipe to browse · Pinch to zoom'
                    : 'Pinch to zoom',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
