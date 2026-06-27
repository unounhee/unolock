import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';

// 학생 가입/로그인. 학생은 앱에서 직접 가입(role=student).
class StudentAuthPage extends StatefulWidget {
  const StudentAuthPage({super.key});

  @override
  State<StudentAuthPage> createState() => _StudentAuthPageState();
}

class _StudentAuthPageState extends State<StudentAuthPage> {
  bool _signUp = false; // false=로그인, true=가입
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_signUp) {
        if (_name.text.trim().isEmpty) {
          setState(() => _error = '이름을 입력해 주세요.');
          return;
        }
        await supabase.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          // 트리거가 이 role을 읽어 student 프로필을 만든다.
          data: {'role': 'student', 'full_name': _name.text.trim()},
        );
      } else {
        await supabase.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      // 성공 → 첫 화면으로 돌아가면 AuthGate가 학생 홈으로 보내줌.
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '알 수 없는 오류: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_signUp ? '학생 가입' : '학생 로그인')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.backpack_outlined, size: 56),
              const SizedBox(height: 20),
              if (_signUp) ...[
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '이름',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: '이메일',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '비밀번호',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text('❌ $_error',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 17),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_signUp ? '가입하기' : '로그인'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => setState(() {
                          _signUp = !_signUp;
                          _error = null;
                        }),
                child: Text(_signUp
                    ? '이미 계정이 있어요 — 로그인'
                    : '처음이에요 — 가입하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
