import 'package:flutter/material.dart';
import 'supabase_client.dart';

// 학부모 홈: 자녀 연결(코드) + 자녀의 "통과한" 결과만 보기.
class ParentHomePage extends StatefulWidget {
  const ParentHomePage({super.key});

  @override
  State<ParentHomePage> createState() => _ParentHomePageState();
}

class _ParentHomePageState extends State<ParentHomePage> {
  final _code = TextEditingController();
  bool _loading = true;
  bool _linking = false;
  String? _error;
  // 자녀별: { student_id, name, passes: [ {score, created_at} ] }
  List<Map<String, dynamic>> _children = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await supabase
          .from('guardianships')
          .select('student_id, profiles!guardianships_student_id_fkey(full_name)')
          .eq('parent_id', supabase.auth.currentUser!.id)
          .eq('status', 'approved');
      final children = <Map<String, dynamic>>[];
      for (final g in List<Map<String, dynamic>>.from(links)) {
        final sid = g['student_id'] as String;
        final prof = g['profiles'];
        final name =
            (prof is Map ? prof['full_name'] as String? : null) ?? '자녀';
        // 통과한 풀이만 (정보 비대칭)
        final passes = await supabase
            .from('attempts')
            .select('score, created_at')
            .eq('student_id', sid)
            .eq('passed', true)
            .order('created_at', ascending: false)
            .limit(20);
        children.add({
          'id': sid,
          'name': name,
          'passes': List<Map<String, dynamic>>.from(passes),
        });
      }
      setState(() {
        _children = children;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _linkChild() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _linking = true;
      _error = null;
    });
    try {
      final res =
          await supabase.rpc('link_child_by_code', params: {'p_code': code});
      final rows = List<Map<String, dynamic>>.from(res as List);
      final name =
          rows.isNotEmpty ? rows.first['child_name'] as String? : null;
      _code.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  name != null ? '$name 자녀와 연결됐어요.' : '자녀와 연결됐어요.')),
        );
      }
    } catch (e) {
      setState(() => _error = _prettyError('$e'));
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  String _prettyError(String raw) {
    if (raw.contains('연결 코드') || raw.contains('not found')) {
      return '연결 코드를 찾을 수 없어요. 자녀 화면의 코드를 확인해 주세요.';
    }
    return raw;
  }

  String _dateLabel(String? iso) {
    if (iso == null) return '';
    // 2026-06-28T... → 2026-06-28
    final t = iso.split('T').first;
    return t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('학부모'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 자녀 연결
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('자녀 연결하기',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('자녀 앱에 뜬 "부모님 연결 코드"를 입력하세요.',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _code,
                            textCapitalization:
                                TextCapitalization.characters,
                            decoration: const InputDecoration(
                              hintText: '예: K7M2QX',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _linking ? null : _linkChild,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 18, horizontal: 18),
                          ),
                          child: _linking
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Text('연결'),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text('❌ $_error',
                          style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('자녀 소식',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_children.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('아직 연결된 자녀가 없어요. 위에서 코드로 연결해 보세요.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              for (final c in _children) _childCard(c),
          ],
        ),
      ),
    );
  }

  Widget _childCard(Map<String, dynamic> c) {
    final passes = List<Map<String, dynamic>>.from(c['passes'] ?? const []);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.child_care),
                const SizedBox(width: 8),
                Text(c['name'] as String,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            if (passes.isEmpty)
              const Text('아직 통과한 미션이 없어요.',
                  style: TextStyle(color: Colors.grey))
            else
              for (final p in passes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Text('🏆 ', style: TextStyle(fontSize: 16)),
                      Expanded(
                        child: Text(
                          '미션 통과! ${p['score']}점',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                      Text(_dateLabel(p['created_at'] as String?),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
