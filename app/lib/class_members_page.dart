import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'supabase_client.dart';

// 선생님: 한 반의 학생 신청 승인/거절 + 내보내기.
class ClassMembersPage extends StatefulWidget {
  final String classId;
  final String className;
  final String joinCode;

  const ClassMembersPage({
    super.key,
    required this.classId,
    required this.className,
    required this.joinCode,
  });

  @override
  State<ClassMembersPage> createState() => _ClassMembersPageState();
}

class _ClassMembersPageState extends State<ClassMembersPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _members = [];

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
          .from('memberships')
          .select('id, status, student_id, profiles(full_name)')
          .eq('class_id', widget.classId)
          .order('created_at');
      setState(() {
        _members = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(String membershipId, String status) async {
    try {
      await supabase
          .from('memberships')
          .update({'status': status})
          .eq('id', membershipId);
      await _load();
    } catch (e) {
      _showError('$e');
    }
  }

  Future<void> _remove(String membershipId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('학생 내보내기'),
        content: Text('$name 학생을 이 반에서 내보낼까요?\n내보내면 이 반의 미션에 접근할 수 없게 됩니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('내보내기')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from('memberships').delete().eq('id', membershipId);
      await _load();
    } catch (e) {
      _showError('$e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('❌ $msg')));
  }

  String _nameOf(Map<String, dynamic> m) {
    final p = m['profiles'];
    if (p is Map && p['full_name'] != null) return p['full_name'] as String;
    return '(이름 없음)';
  }

  @override
  Widget build(BuildContext context) {
    final pending =
        _members.where((m) => m['status'] == 'pending').toList();
    final approved =
        _members.where((m) => m['status'] == 'approved').toList();

    return Scaffold(
      appBar: AppBar(title: Text('${widget.className} · 학생 관리')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('❌ $_error',
                        style: const TextStyle(color: Colors.red)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _codeCard(),
                      const SizedBox(height: 12),
                      _sectionTitle('승인 대기 (${pending.length})'),
                      if (pending.isEmpty)
                        _emptyHint('대기 중인 신청이 없어요.')
                      else
                        for (final m in pending) _pendingTile(m),
                      const SizedBox(height: 16),
                      _sectionTitle('우리 반 학생 (${approved.length})'),
                      if (approved.isEmpty)
                        _emptyHint('아직 승인된 학생이 없어요.')
                      else
                        for (final m in approved) _approvedTile(m),
                    ],
                  ),
                ),
    );
  }

  Widget _codeCard() {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Text('참가 코드  ', style: TextStyle(fontSize: 13)),
            SelectableText(widget.joinCode,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2)),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.joinCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('참가 코드를 복사했어요.')),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('복사'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(t,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      );

  Widget _emptyHint(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(t, style: const TextStyle(color: Colors.grey)),
      );

  Widget _pendingTile(Map<String, dynamic> m) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.hourglass_empty),
        title: Text(_nameOf(m)),
        subtitle: const Text('승인 대기'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '승인',
              icon: const Icon(Icons.check_circle, color: Colors.green),
              onPressed: () => _setStatus(m['id'] as String, 'approved'),
            ),
            IconButton(
              tooltip: '거절',
              icon: const Icon(Icons.cancel, color: Colors.redAccent),
              onPressed: () => _setStatus(m['id'] as String, 'rejected'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _approvedTile(Map<String, dynamic> m) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person, color: Colors.indigo),
        title: Text(_nameOf(m)),
        subtitle: const Text('우리 반'),
        trailing: TextButton.icon(
          onPressed: () => _remove(m['id'] as String, _nameOf(m)),
          icon: const Icon(Icons.exit_to_app, size: 18, color: Colors.redAccent),
          label: const Text('내보내기', style: TextStyle(color: Colors.redAccent)),
        ),
      ),
    );
  }
}
