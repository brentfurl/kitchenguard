import 'job_note.dart';
import 'manager_job_note.dart';
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
    this.completedAt,
    this.managerNotes = const [],
    this.address,
    this.city,
    this.accessType,
    this.accessNotes,
    this.hasAlarm,
    this.alarmCode,
    this.hoodCount,
    this.fanCount,
    this.clientId,
  });

  final String jobId;
  final String restaurantName;
  final String shiftStartDate;
  final String createdAt;
  final String? updatedAt;
  final int schemaVersion;
  final String? scheduledDate;
  final int? sortOrder;
  final String? completedAt;
  final String? address;
  final String? city;
  final String? accessType;
  final String? accessNotes;
  final bool? hasAlarm;
  final String? alarmCode;
  final int? hoodCount;
  final int? fanCount;
  final String? clientId;
  final List<Unit> units;
  final List<JobNote> notes;
  final List<ManagerJobNote> managerNotes;
  final List<PhotoRecord> preCleanLayoutPhotos;
  final Videos videos;

  bool get isComplete => completedAt != null;

  factory Job.fromJson(Map<String, dynamic> json) {
    final unitList = (json['units'] as List<dynamic>? ?? [])
        .map((e) => Unit.fromJson(e as Map<String, dynamic>))
        .toList();
    final noteList = (json['notes'] as List<dynamic>? ?? [])
        .map((e) => JobNote.fromJson(e as Map<String, dynamic>))
        .toList();
    final managerNoteList = (json['managerNotes'] as List<dynamic>? ?? [])
        .map((e) => ManagerJobNote.fromJson(e as Map<String, dynamic>))
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
      completedAt: json['completedAt'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      accessType: json['accessType'] as String?,
      accessNotes: json['accessNotes'] as String?,
      hasAlarm: json['hasAlarm'] as bool?,
      alarmCode: json['alarmCode'] as String?,
      hoodCount: json['hoodCount'] as int?,
      fanCount: json['fanCount'] as int?,
      clientId: json['clientId'] as String?,
      units: unitList,
      notes: noteList,
      managerNotes: managerNoteList,
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
      if (completedAt != null) 'completedAt': completedAt,
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (accessType != null) 'accessType': accessType,
      if (accessNotes != null) 'accessNotes': accessNotes,
      if (hasAlarm != null) 'hasAlarm': hasAlarm,
      if (alarmCode != null) 'alarmCode': alarmCode,
      if (hoodCount != null) 'hoodCount': hoodCount,
      if (fanCount != null) 'fanCount': fanCount,
      if (clientId != null) 'clientId': clientId,
      'schemaVersion': schemaVersion,
      'units': units.map((u) => u.toJson()).toList(),
      'notes': notes.map((n) => n.toJson()).toList(),
      'managerNotes': managerNotes.map((n) => n.toJson()).toList(),
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
    String? completedAt,
    String? address,
    String? city,
    String? accessType,
    String? accessNotes,
    bool? hasAlarm,
    String? alarmCode,
    int? schemaVersion,
    int? sortOrder,
    int? hoodCount,
    int? fanCount,
    String? clientId,
    List<Unit>? units,
    List<JobNote>? notes,
    List<ManagerJobNote>? managerNotes,
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
      completedAt: completedAt ?? this.completedAt,
      address: address ?? this.address,
      city: city ?? this.city,
      accessType: accessType ?? this.accessType,
      accessNotes: accessNotes ?? this.accessNotes,
      hasAlarm: hasAlarm ?? this.hasAlarm,
      alarmCode: alarmCode ?? this.alarmCode,
      hoodCount: hoodCount ?? this.hoodCount,
      fanCount: fanCount ?? this.fanCount,
      clientId: clientId ?? this.clientId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      units: units ?? this.units,
      notes: notes ?? this.notes,
      managerNotes: managerNotes ?? this.managerNotes,
      preCleanLayoutPhotos: preCleanLayoutPhotos ?? this.preCleanLayoutPhotos,
      videos: videos ?? this.videos,
    );
  }
}
