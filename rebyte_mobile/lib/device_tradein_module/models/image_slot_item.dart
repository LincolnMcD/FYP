enum ImageSlotStatus { empty, uploading, success, error, notPhoneDetected }

class ImageSlotItem {
  final String keyName;
  final String label;
  final String? localFilePath;
  final String? previewBase64;
  final String? fileName;
  final bool isOptional;
  final bool hasInfo;
  final String? infoTitle;
  final String? infoMessage;
  final ImageSlotStatus status;
  final double uploadProgress;
  final String? errorMessage;

  const ImageSlotItem({
    required this.keyName,
    required this.label,
    this.localFilePath,
    this.previewBase64,
    this.fileName,
    this.isOptional = false,
    this.hasInfo = false,
    this.infoTitle,
    this.infoMessage,
    this.status = ImageSlotStatus.empty,
    this.uploadProgress = 0.0,
    this.errorMessage,
  });

  ImageSlotItem copyWith({
    String? keyName,
    String? label,
    String? localFilePath,
    String? previewBase64,
    String? fileName,
    bool? isOptional,
    bool? hasInfo,
    String? infoTitle,
    String? infoMessage,
    ImageSlotStatus? status,
    double? uploadProgress,
    String? errorMessage,
  }) {
    return ImageSlotItem(
      keyName: keyName ?? this.keyName,
      label: label ?? this.label,
      localFilePath: localFilePath ?? this.localFilePath,
      previewBase64: previewBase64 ?? this.previewBase64,
      fileName: fileName ?? this.fileName,
      isOptional: isOptional ?? this.isOptional,
      hasInfo: hasInfo ?? this.hasInfo,
      infoTitle: infoTitle ?? this.infoTitle,
      infoMessage: infoMessage ?? this.infoMessage,
      status: status ?? this.status,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  /// Returns a clean empty slot item with all image paths, files, and errors cleared
  ImageSlotItem reset() {
    return ImageSlotItem(
      keyName: keyName,
      label: label,
      isOptional: isOptional,
      hasInfo: hasInfo,
      infoTitle: infoTitle,
      infoMessage: infoMessage,
      status: ImageSlotStatus.empty,
      localFilePath: null,
      previewBase64: null,
      fileName: null,
      uploadProgress: 0.0,
      errorMessage: null,
    );
  }
}
