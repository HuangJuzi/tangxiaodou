import 'package:flutter_test/flutter_test.dart';
import 'package:bella/main.dart';

void main() {
  testWidgets('App renders with top bar', (WidgetTester tester) async {
    await tester.pumpWidget(const BellaApp());
    expect(find.text('豆豆'), findsOneWidget);
  });
}
