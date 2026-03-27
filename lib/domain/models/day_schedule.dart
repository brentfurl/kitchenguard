/// Day-level shift timing: shop meetup and first restaurant arrival.
///
/// One [DaySchedule] per date (not a list). Stored in `day_schedules.json`.
class DaySchedule {
  const DaySchedule({
    required this.date,
    this.shopMeetupTime,
    this.firstRestaurantName,
    this.firstArrivalTime,
    this.published,
    this.publishedAt,
    this.publishedBy,
  });

  final String date; // YYYY-MM-DD
  final String? shopMeetupTime; // HH:mm
  final String? firstRestaurantName;
  final String? firstArrivalTime; // HH:mm
  final bool? published; // null/false = draft
  final String? publishedAt; // ISO 8601 UTC
  final String? publishedBy; // Firebase UID

  bool get isPublished => published == true;

  /// Whether this schedule carries no scheduling data. Publish fields are
  /// intentionally excluded — a day that is only published (no times set)
  /// still counts as non-empty so it isn't pruned from storage.
  bool get isEmpty =>
      shopMeetupTime == null &&
      firstRestaurantName == null &&
      firstArrivalTime == null &&
      published != true;

  factory DaySchedule.fromJson(Map<String, dynamic> json) {
    return DaySchedule(
      date: (json['date'] ?? '').toString(),
      shopMeetupTime: json['shopMeetupTime'] as String?,
      firstRestaurantName: json['firstRestaurantName'] as String?,
      firstArrivalTime: json['firstArrivalTime'] as String?,
      published: json['published'] as bool?,
      publishedAt: json['publishedAt'] as String?,
      publishedBy: json['publishedBy'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'date': date,
      if (shopMeetupTime != null) 'shopMeetupTime': shopMeetupTime,
      if (firstRestaurantName != null)
        'firstRestaurantName': firstRestaurantName,
      if (firstArrivalTime != null) 'firstArrivalTime': firstArrivalTime,
      if (published != null) 'published': published,
      if (publishedAt != null) 'publishedAt': publishedAt,
      if (publishedBy != null) 'publishedBy': publishedBy,
    };
  }

  DaySchedule copyWith({
    String? date,
    String? shopMeetupTime,
    String? firstRestaurantName,
    String? firstArrivalTime,
    bool? published,
    String? publishedAt,
    String? publishedBy,
  }) {
    return DaySchedule(
      date: date ?? this.date,
      shopMeetupTime: shopMeetupTime ?? this.shopMeetupTime,
      firstRestaurantName: firstRestaurantName ?? this.firstRestaurantName,
      firstArrivalTime: firstArrivalTime ?? this.firstArrivalTime,
      published: published ?? this.published,
      publishedAt: publishedAt ?? this.publishedAt,
      publishedBy: publishedBy ?? this.publishedBy,
    );
  }
}
