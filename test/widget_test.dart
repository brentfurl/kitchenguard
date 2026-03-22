import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard_photo_organizer/app.dart';

void main() {
  testWidgets('App boots', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: KitchenGuardApp()),
    );
    await tester.pump();
    expect(true, isTrue);
  });
}