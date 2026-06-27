import 'package:flutter_test/flutter_test.dart';

import 'package:unolock_app/main.dart';

void main() {
  // 테스트 환경에는 연결값이 없으므로 NoKeysPage 안내가 보여야 한다.
  testWidgets('연결값 없으면 안내 화면이 보인다', (WidgetTester tester) async {
    await tester.pumpWidget(const UnoLockApp());

    expect(find.textContaining('연결값이 비어 있어요'), findsOneWidget);
  });
}
