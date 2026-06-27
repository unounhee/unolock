import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'supabase_client.dart';
import 'class_lesson_page.dart';
import 'class_members_page.dart';

// 출제자 홈 (로그인 후). 내 학원별 반 목록 + 각 반의 참가 코드/관리.
class TeacherHomePage extends StatefulWidget {
  const TeacherHomePage({super.key});

  @override
  State<TeacherHomePage> createState() => _TeacherHomePageState();
}

class _TeacherHomePageState extends State<TeacherHomePage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _academies = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await supabase
          .from('academies')
          .select('id, name, classes(id, name, join_code)')
          .order('created_at');
      setState(() {
        _academies = List<Map<String, dynamic>>.from(data);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 반'),
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('❌ 불러오기 실패:\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_academies.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '아직 학원이 없어요.\n웹(unolock.pages.dev)에서 학원·반을 먼저 만들어주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.6),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final academy in _academies) ..._academySection(academy),
        ],
      ),
    );
  }

  List<Widget> _academySection(Map<String, dynamic> academy) {
    final classes =
        List<Map<String, dynamic>>.from(academy['classes'] ?? const []);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4),
        child: Row(
          children: [
            const Icon(Icons.school_outlined, size: 20),
            const SizedBox(width: 8),
            Text(academy['name'] ?? '(이름 없음)',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      if (classes.isEmpty)
        const Padding(
          padding: EdgeInsets.only(left: 8, bottom: 12),
          child: Text('이 학원엔 아직 반이 없어요.',
              style: TextStyle(color: Colors.grey)),
        )
      else
        for (final c in classes) _classCard(academy, c),
      const SizedBox(height: 8),
    ];
  }

  Widget _classCard(Map<String, dynamic> academy, Map<String, dynamic> c) {
    final code = c['join_code'] as String? ?? '------';
    final className = c['name'] as String? ?? '(이름 없음)';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.groups_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(className,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 참가 코드 (학생에게 알려줄 코드)
            Row(
              children: [
                const Text('참가 코드  ',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                SelectableText(
                  code,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                IconButton(
                  tooltip: '코드 복사',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('참가 코드를 복사했어요.')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ClassLessonPage(
                          academyId: academy['id'] as String,
                          classId: c['id'] as String,
                          className: className,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.collections_outlined, size: 18),
                    label: const Text('오늘 수업'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ClassMembersPage(
                          classId: c['id'] as String,
                          className: className,
                          joinCode: code,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.people_outline, size: 18),
                    label: const Text('학생 관리'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
