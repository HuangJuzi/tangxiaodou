import 'package:flutter_test/flutter_test.dart';
import 'package:bella/main.dart';

void main() {
  testWidgets('App renders chat screen', (WidgetTester tester) async {
    await tester.pumpWidget(const BellaApp());
    await tester.pumpAndSettle();
    expect(find.text('按住说话'), findsOneWidget);
  });
}
