import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';
import 'landing_page.dart';
import 'teacher_home_page.dart';
import 'student_home_page.dart';
import 'parent_home_page.dart';

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

// 로그인 상태를 지켜보다가: 로그인 안 됐으면 유형 선택, 됐으면 역할에 맞는 홈.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;
        if (session == null) return const LandingPage();
        return const RoleRouter();
      },
    );
  }
}

// 로그인된 사용자의 role(profiles)을 읽어 학생/출제자 홈으로 보냄.
class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  bool _loading = true;
  String? _role;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = supabase.auth.currentUser!.id;
      final p =
          await supabase.from('profiles').select('role').eq('id', id).single();
      setState(() {
        _role = p['role'] as String?;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('❌ 역할 확인 실패:\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => supabase.auth.signOut(),
                  child: const Text('로그아웃'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    switch (_role) {
      case 'student':
        return const StudentHomePage();
      case 'teacher':
        return const TeacherHomePage();
      case 'parent':
        return const ParentHomePage();
      default:
        // 아직 안 만든 역할
        return Scaffold(
          appBar: AppBar(title: const Text('UnoLock')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('이 역할($_role)의 화면은 준비 중이에요.'),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => supabase.auth.signOut(),
                    child: const Text('로그아웃'),
                  ),
                ],
              ),
            ),
          ),
        );
    }
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
