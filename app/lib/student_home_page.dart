import 'package:flutter/material.dart';
import 'supabase_client.dart';

// 학생 홈 (로그인 후). 지금은 인사 + 로그아웃만.
// 다음 단계(S2~S4): 반 코드 입력 → 승인되면 → 오늘 미션 풀이(잠금).
class StudentHomePage extends StatelessWidget {
  const StudentHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final name =
        supabase.auth.currentUser?.userMetadata?['full_name'] as String? ??
            '학생';

    return Scaffold(
      appBar: AppBar(
        title: const Text('학생'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.backpack_outlined, size: 64),
              const SizedBox(height: 16),
              Text('$name님, 환영해요!',
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 24),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    '🔑 반 코드 입력 → 선생님 승인 → 오늘 미션\n— 다음 단계에서 여기에 만듭니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
