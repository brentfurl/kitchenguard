class VideoRecord {
  const VideoRecord({
    required this.videoId,
    required this.fileName,
    required this.relativePath,
    required this.capturedAt,
    required this.status,
    this.deletedAt,
  });

  final String videoId;
  final String fileName;
  final String relativePath;
  final String capturedAt;
  final String status; // 'local' | 'deleted'
  final String? deletedAt;

  bool get isActive => status == 'local';
  bool get isDeleted => status == 'deleted';

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
    };
  }

  VideoRecord copyWith({
    String? videoId,
    String? fileName,
    String? relativePath,
    String? capturedAt,
    String? status,
    String? deletedAt,
  }) {
    return VideoRecord(
      videoId: videoId ?? this.videoId,
      fileName: fileName ?? this.fileName,
      relativePath: relativePath ?? this.relativePath,
      capturedAt: capturedAt ?? this.capturedAt,
      status: status ?? this.status,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
