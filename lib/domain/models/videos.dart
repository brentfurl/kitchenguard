import 'video_record.dart';

class Videos {
  const Videos({
    required this.exit,
    required this.other,
  });

  const Videos.empty()
      : exit = const [],
        other = const [];

  final List<VideoRecord> exit;
  final List<VideoRecord> other;

  factory Videos.fromJson(Map<String, dynamic> json) {
    final exitList = (json['exit'] as List<dynamic>? ?? [])
        .map((e) => VideoRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    final otherList = (json['other'] as List<dynamic>? ?? [])
        .map((e) => VideoRecord.fromJson(e as Map<String, dynamic>))
        .toList();

    return Videos(exit: exitList, other: otherList);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'exit': exit.map((v) => v.toJson()).toList(),
      'other': other.map((v) => v.toJson()).toList(),
    };
  }

  Videos copyWith({
    List<VideoRecord>? exit,
    List<VideoRecord>? other,
  }) {
    return Videos(
      exit: exit ?? this.exit,
      other: other ?? this.other,
    );
  }
}
