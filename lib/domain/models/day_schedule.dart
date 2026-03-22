/// Day-level shift timing: shop meetup and first restaurant arrival.
///
/// One [DaySchedule] per date (not a list). Stored in `day_schedules.json`.
class DaySchedule {
  const DaySchedule({
    required this.date,
    this.shopMeetupTime,
    this.firstRestaurantName,
    this.firstArrivalTime,
  });

  final String date; // YYYY-MM-DD
  final String? shopMeetupTime; // HH:mm
  final String? firstRestaurantName;
  final String? firstArrivalTime; // HH:mm

  bool get isEmpty =>
      shopMeetupTime == null &&
      firstRestaurantName == null &&
      firstArrivalTime == null;

  factory DaySchedule.fromJson(Map<String, dynamic> json) {
    return DaySchedule(
      date: (json['date'] ?? '').toString(),
      shopMeetupTime: json['shopMeetupTime'] as String?,
      firstRestaurantName: json['firstRestaurantName'] as String?,
      firstArrivalTime: json['firstArrivalTime'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'date': date,
      if (shopMeetupTime != null) 'shopMeetupTime': shopMeetupTime,
      if (firstRestaurantName != null)
        'firstRestaurantName': firstRestaurantName,
      if (firstArrivalTime != null) 'firstArrivalTime': firstArrivalTime,
    };
  }

  DaySchedule copyWith({
    String? date,
    String? shopMeetupTime,
    String? firstRestaurantName,
    String? firstArrivalTime,
  }) {
    return DaySchedule(
      date: date ?? this.date,
      shopMeetupTime: shopMeetupTime ?? this.shopMeetupTime,
      firstRestaurantName: firstRestaurantName ?? this.firstRestaurantName,
      firstArrivalTime: firstArrivalTime ?? this.firstArrivalTime,
    );
  }
}
