import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 오늘 성공한 "폰 화면 잠금(Screen Pinning)" 실험 화면.
// 나중에 학생 미션 화면에 이 잠금 기능을 끼워넣을 것이라 부품으로 보관.
class LockTestPage extends StatefulWidget {
  const LockTestPage({super.key});

  @override
  State<LockTestPage> createState() => _LockTestPageState();
}

class _LockTestPageState extends State<LockTestPage> {
  static const _channel = MethodChannel('unolock/lock');

  String _status = '아직 잠그지 않았어요';

  Future<void> _lock() async {
    try {
      await _channel.invokeMethod('lock');
      setState(() => _status = '🔒 화면 고정을 요청했어요.\n이제 다른 앱으로 못 넘어가야 정상!');
    } on PlatformException catch (e) {
      setState(() => _status = '❌ 잠금 실패: ${e.message}');
    }
  }

  Future<void> _unlock() async {
    try {
      await _channel.invokeMethod('unlock');
      setState(() => _status = '🔓 잠금을 해제했어요.');
    } on PlatformException catch (e) {
      setState(() => _status = '❌ 해제 실패: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('화면 잠금 실험')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 72),
              const SizedBox(height: 24),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _lock,
                  icon: const Icon(Icons.lock),
                  label: const Text('🔒 화면 잠그기'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _unlock,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('🔓 잠금 풀기'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(fontSize: 18),
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
