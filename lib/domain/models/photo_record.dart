class PhotoRecord {
  const PhotoRecord({
    required this.photoId,
    required this.fileName,
    required this.relativePath,
    required this.capturedAt,
    required this.status,
    required this.missingLocal,
    required this.recovered,
    this.deletedAt,
    this.subPhase,
    this.syncStatus,
    this.cloudUrl,
    this.uploadedBy,
    this.sourcePath,
  });

  final String photoId;
  final String fileName;
  final String relativePath;
  final String capturedAt;
  final String status; // 'local' | 'deleted' | 'missing_local'
  final bool missingLocal;
  final bool recovered;
  final String? deletedAt;
  final String? subPhase; // 'filters-on'/'filters-off' (hood), 'closed'/'open' (fan), null (misc)

  /// Cloud sync status: 'pending' | 'uploading' | 'synced' | 'error'.
  /// Null for photos that predate cloud sync (treated as 'pending').
  final String? syncStatus;

  /// Firebase Storage download URL, set after successful upload.
  final String? cloudUrl;

  /// UID of the user who uploaded this photo to Storage.
  final String? uploadedBy;

  /// Original capture path used as a best-effort local fallback until upload succeeds.
  final String? sourcePath;

  bool get isActive => status == 'local' && !missingLocal;
  bool get isDeleted => status == 'deleted';
  bool get isMissing => status == 'missing_local' || missingLocal;

  factory PhotoRecord.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? 'local').toString();
    final validStatuses = {'local', 'deleted', 'missing_local'};
    final normalizedStatus =
        validStatuses.contains(rawStatus) ? rawStatus : 'local';

    return PhotoRecord(
      photoId: (json['photoId'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      relativePath: (json['relativePath'] ?? '').toString(),
      capturedAt: (json['capturedAt'] ?? '').toString(),
      status: normalizedStatus,
      missingLocal: (json['missingLocal'] as bool?) ?? false,
      recovered: (json['recovered'] as bool?) ?? false,
      deletedAt: json['deletedAt'] as String?,
      subPhase: json['subPhase'] as String?,
      syncStatus: json['syncStatus'] as String?,
      cloudUrl: json['cloudUrl'] as String?,
      uploadedBy: json['uploadedBy'] as String?,
      sourcePath: json['sourcePath'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'photoId': photoId,
      'fileName': fileName,
      'relativePath': relativePath,
      'capturedAt': capturedAt,
      'status': status,
      'missingLocal': missingLocal,
      'recovered': recovered,
      if (deletedAt != null) 'deletedAt': deletedAt,
      if (subPhase != null) 'subPhase': subPhase,
      if (syncStatus != null) 'syncStatus': syncStatus,
      if (cloudUrl != null) 'cloudUrl': cloudUrl,
      if (uploadedBy != null) 'uploadedBy': uploadedBy,
      if (sourcePath != null) 'sourcePath': sourcePath,
    };
  }

  bool get isSynced => syncStatus == 'synced';
  bool get needsUpload =>
      isActive && syncStatus != 'synced' && syncStatus != 'uploading';

  PhotoRecord copyWith({
    String? photoId,
    String? fileName,
    String? relativePath,
    String? capturedAt,
    String? status,
    bool? missingLocal,
    bool? recovered,
    String? deletedAt,
    String? subPhase,
    String? syncStatus,
    String? cloudUrl,
    String? uploadedBy,
    String? sourcePath,
    bool clearSourcePath = false,
  }) {
    return PhotoRecord(
      photoId: photoId ?? this.photoId,
      fileName: fileName ?? this.fileName,
      relativePath: relativePath ?? this.relativePath,
      capturedAt: capturedAt ?? this.capturedAt,
      status: status ?? this.status,
      missingLocal: missingLocal ?? this.missingLocal,
      recovered: recovered ?? this.recovered,
      deletedAt: deletedAt ?? this.deletedAt,
      subPhase: subPhase ?? this.subPhase,
      syncStatus: syncStatus ?? this.syncStatus,
      cloudUrl: cloudUrl ?? this.cloudUrl,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      sourcePath: clearSourcePath ? null : (sourcePath ?? this.sourcePath),
    );
  }
}
