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
  });

  final String photoId;
  final String fileName;
  final String relativePath;
  final String capturedAt;
  final String status; // 'local' | 'deleted' | 'missing_local'
  final bool missingLocal;
  final bool recovered;
  final String? deletedAt;

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
    };
  }

  PhotoRecord copyWith({
    String? photoId,
    String? fileName,
    String? relativePath,
    String? capturedAt,
    String? status,
    bool? missingLocal,
    bool? recovered,
    String? deletedAt,
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
    );
  }
}
