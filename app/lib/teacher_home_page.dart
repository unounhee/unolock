import 'package:flutter/material.dart';
import 'supabase_client.dart';

// 출제자 홈 (로그인 후). 내 학원별 반 목록을 두뇌에서 불러와 보여줌.
// 다음 단계: 반을 누르면 "촬영·업로드 → AI 출제"로 들어감.
class TeacherHomePage extends StatefulWidget {
  const TeacherHomePage({super.key});

  @override
  State<TeacherHomePage> createState() => _TeacherHomePageState();
}

class _TeacherHomePageState extends State<TeacherHomePage> {
  bool _loading = true;
  String? _error;
  // 학원 목록 (각 학원 안에 classes 배열)
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
      // 학원 + 그 안의 반을 한 번에. RLS가 "내 것"만 걸러줌.
      final data = await supabase
          .from('academies')
          .select('id, name, classes(id, name)')
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
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
            Text(
              academy['name'] ?? '(이름 없음)',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
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
        for (final c in classes) _classTile(academy, c),
      const SizedBox(height: 8),
    ];
  }

  Widget _classTile(Map<String, dynamic> academy, Map<String, dynamic> c) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.groups_outlined),
        title: Text(c['name'] ?? '(이름 없음)'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // 다음 단계에서 여기에 "촬영·업로드 → AI 출제" 화면을 연결합니다.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '"${c['name']}" 반 — 다음 단계에서 사진 촬영·업로드를 만듭니다.'),
            ),
          );
        },
      ),
    );
  }
}
