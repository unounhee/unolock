import 'package:flutter_test/flutter_test.dart';

import 'package:unolock_app/main.dart';

void main() {
  testWidgets('잠금/풀기 버튼이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const LockTestApp());

    expect(find.text('🔒 화면 잠그기'), findsOneWidget);
    expect(find.text('🔓 잠금 풀기'), findsOneWidget);
  });
}
