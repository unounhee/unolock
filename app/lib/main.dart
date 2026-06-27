import 'package:flutter/material.dart';
import 'supabase_client.dart';
import 'lock_test_page.dart';

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
      home: const ConnectionTestPage(),
    );
  }
}

// 두뇌(Supabase) 연결이 잘 됐는지 확인하는 임시 화면.
// (나중에 진짜 첫 화면 = 유형 선택/로그인 으로 교체됩니다.)
class ConnectionTestPage extends StatefulWidget {
  const ConnectionTestPage({super.key});

  @override
  State<ConnectionTestPage> createState() => _ConnectionTestPageState();
}

class _ConnectionTestPageState extends State<ConnectionTestPage> {
  String _result = '아래 버튼으로 두뇌 연결을 확인해보세요.';
  bool _testing = false;

  Future<void> _testConnection() async {
    if (!hasSupabaseKeys) {
      setState(() => _result =
          '⚠️ 연결값이 비어 있어요.\nenv.json 에 URL·공개키를 넣고 다시 실행해주세요.');
      return;
    }
    setState(() {
      _testing = true;
      _result = '두뇌에 물어보는 중...';
    });
    try {
      // 아무 표에나 가볍게 한 줄 요청 → 응답이 오면(빈 목록이라도) 연결 성공.
      await supabase.from('academies').select('id').limit(1);
      setState(() => _result = '✅ 두뇌(Supabase) 연결 성공!\n앱이 웹과 같은 데이터에 닿았어요.');
    } catch (e) {
      setState(() => _result = '❌ 연결 실패:\n$e');
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyStatus = hasSupabaseKeys
        ? '🔑 연결값 들어옴 (URL·공개키 확인됨)'
        : '🔑 연결값 비어 있음 (env.json 입력 필요)';

    return Scaffold(
      appBar: AppBar(title: const Text('UnoLock — 두뇌 연결 확인')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_outlined, size: 64),
              const SizedBox(height: 16),
              Text(keyStatus, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 24),
              Text(
                _result,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('두뇌 연결 테스트'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 17),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LockTestPage()),
                  ),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('화면 잠금 실험 열기'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
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
