import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard_photo_organizer/app.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(const KitchenGuardApp());
    await tester.pump(); // allow first frame
    // If it gets here without throwing, test passes.
    expect(true, isTrue);
  });
}