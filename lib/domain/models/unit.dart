import 'photo_record.dart';

class Unit {
  const Unit({
    required this.unitId,
    required this.type,
    required this.name,
    required this.unitFolderName,
    required this.isComplete,
    required this.photosBefore,
    required this.photosAfter,
    this.completedAt,
  });

  final String unitId;
  final String type; // 'hood' | 'fan' | 'misc'
  final String name;
  final String unitFolderName;
  final bool isComplete;
  final String? completedAt;
  final List<PhotoRecord> photosBefore;
  final List<PhotoRecord> photosAfter;

  int get visibleBeforeCount =>
      photosBefore.where((p) => p.isActive).length;

  int get visibleAfterCount =>
      photosAfter.where((p) => p.isActive).length;

  /// Returns the visible (active) photo count for a given phase and optional sub-phase.
  /// When [subPhase] is null, returns the total active count for the phase.
  int visibleCount({required String phase, String? subPhase}) {
    final photos = phase == 'before' ? photosBefore : photosAfter;
    if (subPhase == null) return photos.where((p) => p.isActive).length;
    return photos
        .where((p) => p.isActive && p.subPhase == subPhase)
        .length;
  }

  factory Unit.fromJson(Map<String, dynamic> json) {
    final beforeList = (json['photosBefore'] as List<dynamic>? ?? [])
        .map((e) => PhotoRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    final afterList = (json['photosAfter'] as List<dynamic>? ?? [])
        .map((e) => PhotoRecord.fromJson(e as Map<String, dynamic>))
        .toList();

    return Unit(
      unitId: (json['unitId'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      unitFolderName: (json['unitFolderName'] ?? '').toString(),
      isComplete: (json['isComplete'] as bool?) ?? false,
      completedAt: json['completedAt'] as String?,
      photosBefore: beforeList,
      photosAfter: afterList,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'unitId': unitId,
      'type': type,
      'name': name,
      'unitFolderName': unitFolderName,
      'isComplete': isComplete,
      if (completedAt != null) 'completedAt': completedAt,
      'photosBefore': photosBefore.map((p) => p.toJson()).toList(),
      'photosAfter': photosAfter.map((p) => p.toJson()).toList(),
    };
  }

  Unit copyWith({
    String? unitId,
    String? type,
    String? name,
    String? unitFolderName,
    bool? isComplete,
    String? completedAt,
    List<PhotoRecord>? photosBefore,
    List<PhotoRecord>? photosAfter,
  }) {
    return Unit(
      unitId: unitId ?? this.unitId,
      type: type ?? this.type,
      name: name ?? this.name,
      unitFolderName: unitFolderName ?? this.unitFolderName,
      isComplete: isComplete ?? this.isComplete,
      completedAt: completedAt ?? this.completedAt,
      photosBefore: photosBefore ?? this.photosBefore,
      photosAfter: photosAfter ?? this.photosAfter,
    );
  }
}
