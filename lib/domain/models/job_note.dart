class JobNote {
  const JobNote({
    required this.noteId,
    required this.text,
    required this.createdAt,
    required this.status,
    this.updatedAt,
  });

  final String noteId;
  final String text;
  final String createdAt;
  final String status; // 'active' | 'deleted'
  final String? updatedAt; // ISO 8601, null = never edited

  bool get isActive => status == 'active';
  bool get isDeleted => status == 'deleted';

  factory JobNote.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? 'active').toString();
    final normalizedStatus =
        rawStatus == 'deleted' ? 'deleted' : 'active';

    return JobNote(
      noteId: (json['noteId'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      status: normalizedStatus,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'noteId': noteId,
      'text': text,
      'createdAt': createdAt,
      'status': status,
      if (updatedAt != null) 'updatedAt': updatedAt,
    };
  }

  JobNote copyWith({
    String? noteId,
    String? text,
    String? createdAt,
    String? status,
    String? updatedAt,
  }) {
    return JobNote(
      noteId: noteId ?? this.noteId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
