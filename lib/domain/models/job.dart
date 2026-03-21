import 'job_note.dart';
import 'photo_record.dart';
import 'unit.dart';
import 'videos.dart';

class Job {
  const Job({
    required this.jobId,
    required this.restaurantName,
    required this.shiftStartDate,
    required this.createdAt,
    required this.schemaVersion,
    required this.units,
    required this.notes,
    required this.preCleanLayoutPhotos,
    required this.videos,
    this.updatedAt,
    this.scheduledDate,
    this.sortOrder,
  });

  final String jobId;
  final String restaurantName;
  final String shiftStartDate;
  final String createdAt;
  final String? updatedAt;
  final int schemaVersion;
  final String? scheduledDate;
  final int? sortOrder;
  final List<Unit> units;
  final List<JobNote> notes;
  final List<PhotoRecord> preCleanLayoutPhotos;
  final Videos videos;

  factory Job.fromJson(Map<String, dynamic> json) {
    final unitList = (json['units'] as List<dynamic>? ?? [])
        .map((e) => Unit.fromJson(e as Map<String, dynamic>))
        .toList();
    final noteList = (json['notes'] as List<dynamic>? ?? [])
        .map((e) => JobNote.fromJson(e as Map<String, dynamic>))
        .toList();
    final layoutPhotos =
        (json['preCleanLayoutPhotos'] as List<dynamic>? ?? [])
            .map((e) => PhotoRecord.fromJson(e as Map<String, dynamic>))
            .toList();
    final videosObj = json['videos'] != null
        ? Videos.fromJson(json['videos'] as Map<String, dynamic>)
        : const Videos.empty();

    return Job(
      jobId: (json['jobId'] ?? '').toString(),
      restaurantName: (json['restaurantName'] ?? '').toString(),
      shiftStartDate: (json['shiftStartDate'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      updatedAt: json['updatedAt'] as String?,
      schemaVersion: (json['schemaVersion'] as int?) ?? 1,
      scheduledDate: json['scheduledDate'] as String?,
      sortOrder: json['sortOrder'] as int?,
      units: unitList,
      notes: noteList,
      preCleanLayoutPhotos: layoutPhotos,
      videos: videosObj,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'jobId': jobId,
      'restaurantName': restaurantName,
      'shiftStartDate': shiftStartDate,
      'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (scheduledDate != null) 'scheduledDate': scheduledDate,
      if (sortOrder != null) 'sortOrder': sortOrder,
      'schemaVersion': schemaVersion,
      'units': units.map((u) => u.toJson()).toList(),
      'notes': notes.map((n) => n.toJson()).toList(),
      'preCleanLayoutPhotos':
          preCleanLayoutPhotos.map((p) => p.toJson()).toList(),
      'videos': videos.toJson(),
    };
  }

  Job copyWith({
    String? jobId,
    String? restaurantName,
    String? shiftStartDate,
    String? createdAt,
    String? updatedAt,
    String? scheduledDate,
    int? schemaVersion,
    int? sortOrder,
    List<Unit>? units,
    List<JobNote>? notes,
    List<PhotoRecord>? preCleanLayoutPhotos,
    Videos? videos,
  }) {
    return Job(
      jobId: jobId ?? this.jobId,
      restaurantName: restaurantName ?? this.restaurantName,
      shiftStartDate: shiftStartDate ?? this.shiftStartDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      sortOrder: sortOrder ?? this.sortOrder,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      units: units ?? this.units,
      notes: notes ?? this.notes,
      preCleanLayoutPhotos: preCleanLayoutPhotos ?? this.preCleanLayoutPhotos,
      videos: videos ?? this.videos,
    );
  }
}
