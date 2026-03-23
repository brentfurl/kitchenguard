/// A single item in the persistent upload queue.
///
/// Tracks which media file needs to be uploaded to Firebase Storage,
/// along with retry state and status.
class UploadQueueEntry {
  const UploadQueueEntry({
    required this.id,
    required this.jobId,
    required this.jobDirPath,
    required this.mediaId,
    required this.mediaType,
    required this.status,
    required this.retryCount,
    required this.createdAt,
    this.lastAttempt,
  });

  /// Unique queue entry ID (UUID v4).
  final String id;

  /// The job this media belongs to.
  final String jobId;

  /// Absolute path to the job directory on the local filesystem.
  final String jobDirPath;

  /// The photoId or videoId of the media to upload.
  final String mediaId;

  /// 'photo' or 'video'.
  final String mediaType;

  /// 'pending' | 'uploading' | 'completed' | 'failed'.
  final String status;

  final int retryCount;
  final String createdAt;
  final String? lastAttempt;

  bool get isPending => status == 'pending';
  bool get isUploading => status == 'uploading';
  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isPhoto => mediaType == 'photo';
  bool get isVideo => mediaType == 'video';

  factory UploadQueueEntry.fromJson(Map<String, dynamic> json) {
    return UploadQueueEntry(
      id: (json['id'] ?? '').toString(),
      jobId: (json['jobId'] ?? '').toString(),
      jobDirPath: (json['jobDirPath'] ?? '').toString(),
      mediaId: (json['mediaId'] ?? '').toString(),
      mediaType: (json['mediaType'] ?? 'photo').toString(),
      status: (json['status'] ?? 'pending').toString(),
      retryCount: (json['retryCount'] as int?) ?? 0,
      createdAt: (json['createdAt'] ?? '').toString(),
      lastAttempt: json['lastAttempt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'jobId': jobId,
      'jobDirPath': jobDirPath,
      'mediaId': mediaId,
      'mediaType': mediaType,
      'status': status,
      'retryCount': retryCount,
      'createdAt': createdAt,
      if (lastAttempt != null) 'lastAttempt': lastAttempt,
    };
  }

  UploadQueueEntry copyWith({
    String? id,
    String? jobId,
    String? jobDirPath,
    String? mediaId,
    String? mediaType,
    String? status,
    int? retryCount,
    String? createdAt,
    String? lastAttempt,
  }) {
    return UploadQueueEntry(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      jobDirPath: jobDirPath ?? this.jobDirPath,
      mediaId: mediaId ?? this.mediaId,
      mediaType: mediaType ?? this.mediaType,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      lastAttempt: lastAttempt ?? this.lastAttempt,
    );
  }
}
