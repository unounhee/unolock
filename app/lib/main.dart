import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';
import 'login_page.dart';
import 'teacher_home_page.dart';

Future<void> main() async {
  // 앱이 화면을 그리기 전에 두뇌(Supabase) 연결을 먼저 켭니다.
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const UnoLockApp());
}

class UnoLockApp extends StatelessWidget {
  const UnoLockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UnoLock',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      // 연결값이 없으면 안내, 있으면 로그인 상태에 따라 화면 분기.
      home: hasSupabaseKeys ? const AuthGate() : const NoKeysPage(),
    );
  }
}

// 로그인 상태를 지켜보다가, 로그인됐으면 출제자 홈 / 아니면 로그인 화면.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;
        if (session != null) {
          return const TeacherHomePage();
        }
        return const LoginPage();
      },
    );
  }
}

// 연결값(env.json)이 비어 있을 때 보여주는 안내.
class NoKeysPage extends StatelessWidget {
  const NoKeysPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UnoLock')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '⚠️ 연결값이 비어 있어요.\n\nenv.json 에 SUPABASE_URL·SUPABASE_ANON_KEY 를 넣고\n--dart-define-from-file=env.json 으로 실행해주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.6),
          ),
        ),
      ),
    );
  }
}
