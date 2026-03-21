class ManagerJobNote {
  const ManagerJobNote({
    required this.noteId,
    required this.text,
    required this.createdAt,
    required this.status,
  });

  final String noteId;
  final String text;
  final String createdAt;
  final String status; // 'active' | 'deleted'

  bool get isActive => status == 'active';
  bool get isDeleted => status == 'deleted';

  factory ManagerJobNote.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? 'active').toString();
    final normalizedStatus =
        rawStatus == 'deleted' ? 'deleted' : 'active';

    return ManagerJobNote(
      noteId: (json['noteId'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      status: normalizedStatus,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'noteId': noteId,
      'text': text,
      'createdAt': createdAt,
      'status': status,
    };
  }

  ManagerJobNote copyWith({
    String? noteId,
    String? text,
    String? createdAt,
    String? status,
  }) {
    return ManagerJobNote(
      noteId: noteId ?? this.noteId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }
}
