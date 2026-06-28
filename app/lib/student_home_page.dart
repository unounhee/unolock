import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'supabase_client.dart';
import 'student_mission_page.dart';

// 학생 홈: 반 코드로 신청 + 내가 신청/소속한 반들의 상태 보기.
// 다음 단계(S3): 승인된 반의 "오늘 미션"으로 들어가기.
class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key});

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  final _code = TextEditingController();
  bool _loading = true;
  bool _joining = false;
  String? _error;
  String? _linkCode; // 부모님 연결 코드
  List<Map<String, dynamic>> _memberships = [];

  String get _name =>
      supabase.auth.currentUser?.userMetadata?['full_name'] as String? ?? '학생';

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
      final id = supabase.auth.currentUser!.id;
      final data = await supabase
          .from('memberships')
          .select('class_id, status, classes(name)')
          .eq('student_id', id)
          .order('created_at');
      // 부모님 연결 코드(내 프로필)
      String? linkCode;
      try {
        final prof = await supabase
            .from('profiles')
            .select('link_code')
            .eq('id', id)
            .single();
        linkCode = prof['link_code'] as String?;
      } catch (_) {
        linkCode = null; // 0014 SQL 전이면 없을 수 있음
      }
      setState(() {
        _memberships = List<Map<String, dynamic>>.from(data);
        _linkCode = linkCode;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final res = await supabase
          .rpc('join_class_by_code', params: {'p_code': code});
      // 함수가 표를 돌려주므로 결과는 목록. 첫 줄에 반 이름/상태.
      final rows = List<Map<String, dynamic>>.from(res as List);
      final className =
          rows.isNotEmpty ? rows.first['class_name'] as String? : null;
      _code.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(className != null
                ? '"$className" 반에 신청했어요. 선생님 승인을 기다려요.'
                : '신청했어요.'),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = _prettyError('$e'));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  String _prettyError(String raw) {
    if (raw.contains('no such class code') || raw.contains('반 코드')) {
      return '반 코드를 찾을 수 없어요. 코드를 다시 확인해 주세요.';
    }
    return raw;
  }

  String _statusLabel(String? s) {
    switch (s) {
      case 'approved':
        return '✅ 승인됨';
      case 'pending':
        return '⏳ 승인 대기';
      case 'rejected':
        return '❌ 거절됨';
      default:
        return s ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('학생'),
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
            Text('$_name님, 환영해요!',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // 부모님 연결 코드
            if (_linkCode != null)
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.family_restroom, size: 20),
                      const SizedBox(width: 8),
                      const Text('부모님 연결 코드  ',
                          style: TextStyle(fontSize: 13)),
                      SelectableText(_linkCode!,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2)),
                      const Spacer(),
                      IconButton(
                        tooltip: '복사',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _linkCode!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('연결 코드를 복사했어요.')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (_linkCode != null) const SizedBox(height: 16),
            // 반 코드 입력
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('반 코드로 들어가기',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('선생님이 알려준 6자리 코드를 입력하세요.',
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
                          onPressed: _joining ? null : _join,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 18, horizontal: 18),
                          ),
                          child: _joining
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Text('신청'),
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
            const Text('내 반',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_memberships.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('아직 신청한 반이 없어요. 위에서 코드를 입력해 보세요.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              for (final m in _memberships) _membershipTile(m),
          ],
        ),
      ),
    );
  }

  Widget _membershipTile(Map<String, dynamic> m) {
    final cls = m['classes'];
    final className =
        (cls is Map ? cls['name'] as String? : null) ?? '(반)';
    final status = m['status'] as String?;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.groups_outlined),
        title: Text(className),
        subtitle: Text(_statusLabel(status)),
        // 승인된 반이면 "오늘 미션 풀기"(잠금+풀이)로 들어간다.
        trailing: status == 'approved'
            ? const Icon(Icons.chevron_right)
            : null,
        onTap: status == 'approved'
            ? () {
                final cls = m['classes'];
                final className =
                    (cls is Map ? cls['name'] as String? : null) ?? '미션';
                final classId = m['class_id'] as String?;
                if (classId == null) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StudentMissionPage(
                      classId: classId,
                      className: className,
                    ),
                  ),
                );
              }
            : null,
      ),
    );
  }
}
