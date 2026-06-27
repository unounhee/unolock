import 'package:flutter/material.dart';
import 'login_page.dart';
import 'student_auth_page.dart';

// 첫 화면(로그인 안 된 상태): 누구인지 고르기.
// 학부모는 다음 단계에서 추가.
class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('UnoLock',
                  style:
                      TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('어떤 분이신가요?',
                  style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 40),
              _bigButton(
                context,
                icon: Icons.backpack_outlined,
                label: '학생',
                subtitle: '미션 풀고 폰 열기',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StudentAuthPage()),
                ),
              ),
              const SizedBox(height: 16),
              _bigButton(
                context,
                icon: Icons.school_outlined,
                label: '출제자 (선생님)',
                subtitle: '반 만들고 교재 올리기',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bigButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 36),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style:
                        const TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
