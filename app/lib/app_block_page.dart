import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 실험 2: 접근성으로 "막을 앱 하나"를 골라 차단.
// (안전 실험 — 전부 차단이 아니라, 고른 앱 하나만 막아 홈으로 튕김)
class AppBlockPage extends StatefulWidget {
  const AppBlockPage({super.key});

  @override
  State<AppBlockPage> createState() => _AppBlockPageState();
}

class _AppBlockPageState extends State<AppBlockPage>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('unolock/lock');

  bool _loading = true;
  bool _accessibilityOn = false;
  String? _blocked;
  List<Map<String, dynamic>> _apps = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 접근성 설정 다녀오면 상태 다시 확인
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final on = await _channel.invokeMethod('isAccessibilityEnabled') as bool;
      final blocked =
          await _channel.invokeMethod('getBlockedPackage') as String?;
      final raw = await _channel.invokeMethod('listApps');
      final apps = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _accessibilityOn = on;
        _blocked = blocked;
        _apps = apps;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final on = await _channel.invokeMethod('isAccessibilityEnabled') as bool;
      if (mounted) setState(() => _accessibilityOn = on);
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  Future<void> _setBlocked(String? pkg) async {
    await _channel.invokeMethod('setBlockedPackage', {'package': pkg});
    setState(() => _blocked = pkg);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(pkg == null ? '차단을 해제했어요.' : '이 앱을 막도록 설정했어요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('앱 막기 (실험)'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _statusCard(),
                const SizedBox(height: 16),
                const Text('막을 앱 고르기 (실험: 하나만)',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('하나 고르고 → 접근성 켠 뒤 → 그 앱을 열어보세요. 홈으로 튕기면 성공!',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                if (_blocked != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('지금 막는 앱: $_blocked',
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w600)),
                        ),
                        TextButton(
                          onPressed: () => _setBlocked(null),
                          child: const Text('차단 해제'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                for (final a in _apps) _appTile(a),
              ],
            ),
    );
  }

  Widget _statusCard() {
    final on = _accessibilityOn;
    return Card(
      color: on
          ? Colors.green.withValues(alpha: 0.10)
          : Colors.orange.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(on ? Icons.check_circle : Icons.warning_amber,
                    color: on ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                Text(on ? '접근성 켜짐' : '접근성 꺼짐',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              on
                  ? '차단이 작동할 수 있어요. 막을 앱을 골라 열어보세요.'
                  : '차단하려면 접근성에서 UnoLock을 켜야 해요.',
              style: const TextStyle(fontSize: 13),
            ),
            if (!on) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_accessibility),
                label: const Text('접근성 설정 열기'),
              ),
              const SizedBox(height: 4),
              const Text('설정 → 설치된 앱 → UnoLock 앱 차단 → 켜기',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _appTile(Map<String, dynamic> a) {
    final pkg = a['package']?.toString() ?? '';
    final selected = pkg == _blocked;
    return Card(
      child: ListTile(
        leading: Icon(selected ? Icons.block : Icons.android,
            color: selected ? Colors.redAccent : null),
        title: Text(a['name']?.toString() ?? '(이름 없음)'),
        subtitle: Text(pkg, style: const TextStyle(fontSize: 11)),
        trailing: selected
            ? const Text('막는 중',
                style: TextStyle(color: Colors.redAccent))
            : const Text('막기'),
        onTap: () => _setBlocked(pkg),
      ),
    );
  }
}
