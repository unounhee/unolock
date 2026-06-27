import 'package:flutter_test/flutter_test.dart';

import 'package:unolock_app/main.dart';

void main() {
  testWidgets('두뇌 연결 확인 화면이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const UnoLockApp());

    expect(find.text('두뇌 연결 테스트'), findsOneWidget);
    expect(find.text('화면 잠금 실험 열기'), findsOneWidget);
  });
}
