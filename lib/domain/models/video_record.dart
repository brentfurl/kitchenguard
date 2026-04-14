class VideoRecord {
  const VideoRecord({
    required this.videoId,
    required this.fileName,
    required this.relativePath,
    required this.capturedAt,
    required this.status,
    this.deletedAt,
    this.syncStatus,
    this.cloudUrl,
    this.uploadedBy,
    this.sourcePath,
    this.thumbnailPath,
    this.thumbnailCloudUrl,
  });

  final String videoId;
  final String fileName;
  final String relativePath;
  final String capturedAt;
  final String status; // 'local' | 'deleted'
  final String? deletedAt;

  /// Cloud sync status: 'pending' | 'uploading' | 'synced' | 'error'.
  /// Null for videos that predate cloud sync (treated as 'pending').
  final String? syncStatus;

  /// Firebase Storage download URL, set after successful upload.
  final String? cloudUrl;

  /// UID of the user who uploaded this video to Storage.
  final String? uploadedBy;

  /// Original capture path used as a best-effort local fallback until upload succeeds.
  final String? sourcePath;

  /// Relative path to the generated thumbnail image on local disk.
  final String? thumbnailPath;

  /// Firebase Storage download URL for the generated thumbnail image.
  final String? thumbnailCloudUrl;

  bool get isActive => status == 'local';
  bool get isDeleted => status == 'deleted';
  bool get isSynced => syncStatus == 'synced';
  bool get needsUpload =>
      isActive && syncStatus != 'synced' && syncStatus != 'uploading';

  factory VideoRecord.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? 'local').toString();
    final normalizedStatus = rawStatus == 'deleted' ? 'deleted' : 'local';

    return VideoRecord(
      videoId: (json['videoId'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      relativePath: (json['relativePath'] ?? '').toString(),
      capturedAt: (json['capturedAt'] ?? '').toString(),
      status: normalizedStatus,
      deletedAt: json['deletedAt'] as String?,
      syncStatus: json['syncStatus'] as String?,
      cloudUrl: json['cloudUrl'] as String?,
      uploadedBy: json['uploadedBy'] as String?,
      sourcePath: json['sourcePath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      thumbnailCloudUrl: json['thumbnailCloudUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'videoId': videoId,
      'fileName': fileName,
      'relativePath': relativePath,
      'capturedAt': capturedAt,
      'status': status,
      if (deletedAt != null) 'deletedAt': deletedAt,
      if (syncStatus != null) 'syncStatus': syncStatus,
      if (cloudUrl != null) 'cloudUrl': cloudUrl,
      if (uploadedBy != null) 'uploadedBy': uploadedBy,
      if (sourcePath != null) 'sourcePath': sourcePath,
      if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
      if (thumbnailCloudUrl != null) 'thumbnailCloudUrl': thumbnailCloudUrl,
    };
  }

  VideoRecord copyWith({
    String? videoId,
    String? fileName,
    String? relativePath,
    String? capturedAt,
    String? status,
    String? deletedAt,
    String? syncStatus,
    String? cloudUrl,
    String? uploadedBy,
    String? sourcePath,
    String? thumbnailPath,
    String? thumbnailCloudUrl,
    bool clearSourcePath = false,
    bool clearThumbnailCloudUrl = false,
  }) {
    return VideoRecord(
      videoId: videoId ?? this.videoId,
      fileName: fileName ?? this.fileName,
      relativePath: relativePath ?? this.relativePath,
      capturedAt: capturedAt ?? this.capturedAt,
      status: status ?? this.status,
      deletedAt: deletedAt ?? this.deletedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      cloudUrl: cloudUrl ?? this.cloudUrl,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      sourcePath: clearSourcePath ? null : (sourcePath ?? this.sourcePath),
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      thumbnailCloudUrl: clearThumbnailCloudUrl
          ? null
          : (thumbnailCloudUrl ?? this.thumbnailCloudUrl),
    );
  }
}
