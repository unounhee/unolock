import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 허용목록 차단: "차단 모드"가 켜지면 체크한 앱만 통과, 나머지는 막힌다.
// (홈·설정·UnoLock은 항상 통과 — 폰이 잠겨버리지 않게)
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
  bool _blockMode = false;
  Set<String> _allowed = {};
  List<Map<String, dynamic>> _apps = [];
  int _rewardMs = 0;
  int _lockHour = -1; // 매일 잠금 시각. -1 = 아직 설정 안 함.
  int _lockMinute = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _pollReward());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _pollReward() async {
    try {
      final ms = await _channel.invokeMethod('getRewardRemaining') as int;
      if (mounted && ms != _rewardMs) setState(() => _rewardMs = ms);
    } catch (_) {}
  }

  Future<void> _startReward(int minutes) async {
    await _channel.invokeMethod('startReward', {'minutes': minutes});
    _pollReward();
  }

  Future<void> _endReward() async {
    await _channel.invokeMethod('endReward');
    _pollReward();
  }

  String _fmt(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final on = await _channel.invokeMethod('isAccessibilityEnabled') as bool;
      final mode = await _channel.invokeMethod('getBlockMode') as bool;
      final allowedRaw = await _channel.invokeMethod('getAllowedPackages');
      final allowed = (allowedRaw as List).map((e) => e.toString()).toSet();
      final raw = await _channel.invokeMethod('listApps');
      final apps = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final lt = await _channel.invokeMethod('getLockTime');
      final lock = Map<String, dynamic>.from(lt as Map);
      setState(() {
        _accessibilityOn = on;
        _blockMode = mode;
        _allowed = allowed;
        _apps = apps;
        _lockHour = (lock['hour'] as num?)?.toInt() ?? -1;
        _lockMinute = (lock['minute'] as num?)?.toInt() ?? 0;
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

  Future<void> _toggleBlockMode(bool on) async {
    await _channel.invokeMethod('setBlockMode', {'on': on});
    setState(() => _blockMode = on);
  }

  // 매일 잠금 시각 고르기(지금은 부모 대역으로 학생 폰에서 직접 선택).
  Future<void> _pickLockTime() async {
    final init = _lockHour >= 0
        ? TimeOfDay(hour: _lockHour, minute: _lockMinute)
        : const TimeOfDay(hour: 23, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: init);
    if (picked == null) return;
    await _channel.invokeMethod(
        'setLockTime', {'hour': picked.hour, 'minute': picked.minute});
    setState(() {
      _lockHour = picked.hour;
      _lockMinute = picked.minute;
    });
  }

  // 테스트: "오늘 모든 미션 완료" 가정 → 오늘 잠금 시각까지 자유.
  // (17-6b에서 미션 통과 시 자동 호출되게 연결. 지금은 손으로 확인.)
  Future<void> _freeUntilLockTime() async {
    if (_lockHour < 0) return;
    final now = DateTime.now();
    final target =
        DateTime(now.year, now.month, now.day, _lockHour, _lockMinute);
    if (!target.isAfter(now)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('잠금 시각이 이미 지났어요. 미래 시각으로 정해야 자유 시간이 생겨요.')),
        );
      }
      return;
    }
    await _channel.invokeMethod(
        'startRewardUntil', {'until': target.millisecondsSinceEpoch});
    _pollReward();
  }

  String _lockTimeLabel() {
    if (_lockHour < 0) return '아직 설정 안 함';
    final h = _lockHour.toString().padLeft(2, '0');
    final m = _lockMinute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _toggleAllowed(String pkg, bool allow) async {
    setState(() {
      if (allow) {
        _allowed.add(pkg);
      } else {
        _allowed.remove(pkg);
      }
    });
    await _channel
        .invokeMethod('setAllowedPackages', {'packages': _allowed.toList()});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('허용 앱 설정 (실험)'),
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
                const SizedBox(height: 12),
                _blockModeCard(),
                const SizedBox(height: 12),
                _lockTimeCard(),
                const SizedBox(height: 12),
                _rewardCard(),
                const SizedBox(height: 16),
                Text('허용할 앱 (${_allowed.length}개 선택됨)',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('체크한 앱만 쓸 수 있어요. 홈·설정·UnoLock은 항상 됩니다.',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
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

  Widget _blockModeCard() {
    return Card(
      child: SwitchListTile(
        title: const Text('차단 모드',
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(_blockMode
            ? '켜짐 — 허용한 앱만 쓸 수 있어요'
            : '꺼짐 — 모든 앱 자유'),
        value: _blockMode,
        onChanged: _accessibilityOn ? _toggleBlockMode : null,
        secondary: Icon(_blockMode ? Icons.lock : Icons.lock_open,
            color: _blockMode ? Colors.redAccent : null),
      ),
    );
  }

  // 매일 잠금 시각 카드 — "모든 미션 완료 시 이 시각까지 자유".
  // (부모가 정하는 값. 지금은 학생 폰에서 직접 고르고, 17-7에서 서버 동기화.)
  Widget _lockTimeCard() {
    final set = _lockHour >= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.nightlight_round),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('매일 잠금 시각',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Text(_lockTimeLabel(),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: set ? Colors.indigo : Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '오늘 미션을 모두 통과하면 이 시각까지 자유롭게 쓰고, 그 시각에 다시 잠겨요.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickLockTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(set ? '시각 바꾸기' : '시각 정하기'),
                ),
                const SizedBox(width: 8),
                if (set)
                  FilledButton.icon(
                    onPressed: _freeUntilLockTime,
                    icon: const Icon(Icons.celebration),
                    label: const Text('모든 미션 완료 (테스트)'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _rewardCard() {
    final active = _rewardMs > 0;
    return Card(
      color: active ? Colors.indigo.withValues(alpha: 0.10) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(active ? Icons.timer : Icons.timer_outlined,
                    color: active ? Colors.indigo : null),
                const SizedBox(width: 8),
                Text(
                  active ? '자유 시간  ${_fmt(_rewardMs)}' : '보상 시간 (테스트)',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              active
                  ? '지금은 차단이 풀려 모든 앱을 쓸 수 있어요. 시간이 끝나면 다시 잠겨요.'
                  : '통과하면 받는 자유 시간을 흉내내는 버튼이에요.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () => _startReward(1),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('보상 1분 받기'),
                ),
                const SizedBox(width: 8),
                if (active)
                  OutlinedButton(
                    onPressed: _endReward,
                    child: const Text('지금 종료'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _appTile(Map<String, dynamic> a) {
    final pkg = a['package']?.toString() ?? '';
    final allowed = _allowed.contains(pkg);
    return Card(
      child: CheckboxListTile(
        value: allowed,
        onChanged: (v) => _toggleAllowed(pkg, v ?? false),
        title: Text(a['name']?.toString() ?? '(이름 없음)'),
        subtitle: Text(pkg, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}
