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
    bool clearSourcePath = false,
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
    );
  }
}
