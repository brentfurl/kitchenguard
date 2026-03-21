class DayNote {
  const DayNote({
    required this.noteId,
    required this.date,
    required this.text,
    required this.createdAt,
    required this.status,
  });

  final String noteId;
  final String date; // YYYY-MM-DD
  final String text;
  final String createdAt; // ISO 8601
  final String status; // 'active' | 'deleted'

  bool get isActive => status == 'active';
  bool get isDeleted => status == 'deleted';

  factory DayNote.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? 'active').toString();
    final normalizedStatus = rawStatus == 'deleted' ? 'deleted' : 'active';

    return DayNote(
      noteId: (json['noteId'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      status: normalizedStatus,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'noteId': noteId,
      'date': date,
      'text': text,
      'createdAt': createdAt,
      'status': status,
    };
  }

  DayNote copyWith({
    String? noteId,
    String? date,
    String? text,
    String? createdAt,
    String? status,
  }) {
    return DayNote(
      noteId: noteId ?? this.noteId,
      date: date ?? this.date,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }
}
