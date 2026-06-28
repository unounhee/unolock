import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'supabase_client.dart';
import 'math_text.dart';

// 학생 "오늘 미션": 폰을 잠그고(화면 고정) 문제를 푼다.
// 80% 미만이면 비슷한 새 문제로 재출제(결국 통과시키는 루프). 통과하면 잠금 해제.
class StudentMissionPage extends StatefulWidget {
  final String classId;
  final String className;

  const StudentMissionPage({
    super.key,
    required this.classId,
    required this.className,
  });

  @override
  State<StudentMissionPage> createState() => _StudentMissionPageState();
}

enum _Phase { loading, error, noBatch, intro, solving, passed, failed }

class _StudentMissionPageState extends State<StudentMissionPage> {
  static const _lockChannel = MethodChannel('unolock/lock');

  _Phase _phase = _Phase.loading;
  String? _error;
  String? _batchId;
  List<Map<String, dynamic>> _questions = [];

  // 풀이 상태
  int _index = 0;
  int? _selected; // 객관식 선택
  final _shortCtrl = TextEditingController();
  bool _answered = false;
  bool _lastCorrect = false;
  int _correctCount = 0;
  bool _locked = false;
  bool _busy = false; // 재출제 중
  int _attemptNo = 1; // 재출제 회차
  final List<String> _given = []; // 각 문제에 학생이 낸 답(기록용)

  @override
  void initState() {
    super.initState();
    _loadMission();
  }

  @override
  void dispose() {
    _shortCtrl.dispose();
    // 안전: 화면을 떠날 때 잠금이 남아있지 않게.
    if (_locked) _lockChannel.invokeMethod('unlock').catchError((_) => null);
    super.dispose();
  }

  Future<void> _loadMission({List<Map<String, dynamic>>? previous}) async {
    setState(() {
      if (previous == null) _phase = _Phase.loading;
      _busy = true;
      _error = null;
    });
    try {
      // 최신 수업 묶음 찾기
      if (_batchId == null) {
        final batches = await supabase
            .from('lesson_batches')
            .select('id')
            .eq('class_id', widget.classId)
            .order('created_at', ascending: false)
            .limit(1);
        if (batches.isEmpty) {
          setState(() {
            _phase = _Phase.noBatch;
            _busy = false;
          });
          return;
        }
        _batchId = batches.first['id'] as String;
      }

      final body = <String, dynamic>{'batch_id': _batchId};
      if (previous != null) body['previous'] = previous;
      final res =
          await supabase.functions.invoke('generate-questions', body: body);
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw data['error'];
      }
      final qs = List<Map<String, dynamic>>.from(
          (data['questions'] as List?) ?? const []);
      if (qs.isEmpty) throw '문제를 만들지 못했어요. 다시 시도해 주세요.';

      setState(() {
        _questions = qs;
        _index = 0;
        _selected = null;
        _shortCtrl.clear();
        _answered = false;
        _correctCount = 0;
        _given.clear();
        _busy = false;
        // previous가 있으면(재출제) 잠금 유지한 채 바로 풀이로.
        _phase = previous != null ? _Phase.solving : _Phase.intro;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _phase = _Phase.error;
        _busy = false;
      });
      // 풀이 중 오류면 갇히지 않게 잠금 해제.
      if (_locked) await _unlock();
    }
  }

  Future<void> _lock() async {
    try {
      await _lockChannel.invokeMethod('lock');
      _locked = true;
    } catch (_) {}
  }

  Future<void> _unlock() async {
    try {
      await _lockChannel.invokeMethod('unlock');
      _locked = false;
    } catch (_) {}
  }

  Future<void> _startMission() async {
    await _lock();
    setState(() => _phase = _Phase.solving);
  }

  String _norm(String s) =>
      s.replaceAll('\$', '').replaceAll(RegExp(r'\s+'), '').toLowerCase();

  Map<String, dynamic> get _q => _questions[_index];
  bool get _isShort => _q['type'] == 'short';

  void _checkAnswer() {
    final correct = (_q['correct_answer'] ?? '').toString();
    final choices = List<dynamic>.from(_q['choices'] ?? const []);
    // 학생이 낸 답(문자열) — 기록용
    final given = _isShort
        ? _shortCtrl.text.trim()
        : (_selected != null && _selected! < choices.length
            ? choices[_selected!].toString()
            : '');
    final ok = _norm(given).isNotEmpty && _norm(given) == _norm(correct);
    setState(() {
      _given.add(given);
      _answered = true;
      _lastCorrect = ok;
      if (ok) _correctCount++;
    });
  }

  void _next() {
    if (_index < _questions.length - 1) {
      setState(() {
        _index++;
        _selected = null;
        _shortCtrl.clear();
        _answered = false;
      });
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final total = _questions.length;
    final pass = _correctCount * 5 >= total * 4; // 80%
    // 서버에 결과 기록(실패해도 학생 화면은 막지 않음).
    _recordMission(pass);
    if (pass) {
      await _unlock();
      // 통과 보상: 30분간 자유 시간(차단 모드일 때 풀림)
      try {
        await _lockChannel.invokeMethod('startReward', {'minutes': 30});
      } catch (_) {}
      setState(() => _phase = _Phase.passed);
    } else {
      setState(() => _phase = _Phase.failed);
    }
  }

  // 풀이 결과를 서버가 재채점해 student_id 로 기록.
  Future<void> _recordMission(bool passed) async {
    try {
      final items = [
        for (var i = 0; i < _questions.length; i++)
          {
            'type': _questions[i]['type'],
            'body': _questions[i]['body'],
            'choices': _questions[i]['choices'],
            'correct_answer': _questions[i]['correct_answer'],
            'explanation': _questions[i]['explanation'],
            'student_answer': i < _given.length ? _given[i] : '',
          }
      ];
      await supabase.functions.invoke('record-mission', body: {
        'batch_id': _batchId,
        'attempt_no': _attemptNo,
        'items': items,
      });
    } catch (_) {
      // 기록 실패는 무시(학생 경험 우선).
    }
  }

  // 미달 → 비슷한 새 문제로 다시(잠금 유지). 회차 증가.
  Future<void> _retry() async {
    _attemptNo++;
    await _loadMission(previous: _questions);
  }

  Future<void> _leave() async {
    if (_locked) await _unlock();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // 풀이 중에는 시스템 뒤로가기로 못 빠져나가게(화면 고정과 별개로 UX 일관).
    return PopScope(
      canPop: _phase != _Phase.solving,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.className} · 오늘 미션'),
          automaticallyImplyLeading: _phase != _Phase.solving,
        ),
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.error:
        return _centerMsg('❌ $_error', action: ('돌아가기', _leave));
      case _Phase.noBatch:
        return _centerMsg('아직 오늘 수업이 없어요.\n선생님이 수업을 올리면 미션이 생겨요.',
            action: ('돌아가기', _leave));
      case _Phase.intro:
        return _introView();
      case _Phase.solving:
        return _solveView();
      case _Phase.passed:
        return _passView();
      case _Phase.failed:
        return _failView();
    }
  }

  Widget _centerMsg(String msg, {(String, VoidCallback)? action}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.6)),
            if (action != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(onPressed: action.$2, child: Text(action.$1)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _introView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_clock, size: 72),
            const SizedBox(height: 20),
            Text('오늘 미션 ${_questions.length}문제',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text(
              '시작하면 폰이 잠겨요.\n미션을 통과해야 폰이 다시 열립니다.\n(통과 기준 80%)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.6),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startMission,
                icon: const Icon(Icons.lock),
                label: const Text('미션 시작 (폰 잠금)'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _leave, child: const Text('나중에 하기')),
          ],
        ),
      ),
    );
  }

  Widget _solveView() {
    final choices = List<dynamic>.from(_q['choices'] ?? const []);
    final total = _questions.length;
    return Column(
      children: [
        // 진행 표시
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Text('문제 ${_index + 1} / $total',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              const Icon(Icons.lock, size: 16, color: Colors.redAccent),
              const SizedBox(width: 4),
              const Text('미션 끝내야 폰이 열려요',
                  style: TextStyle(fontSize: 12, color: Colors.redAccent)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MathText('${_q['body'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),
              if (_isShort)
                TextField(
                  controller: _shortCtrl,
                  enabled: !_answered,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '답 입력 (숫자)',
                    border: OutlineInputBorder(),
                  ),
                )
              else
                for (var i = 0; i < choices.length; i++)
                  _choiceTile(i, choices[i].toString()),
              if (_answered) _feedback(),
            ],
          ),
        ),
        _bottomBar(),
      ],
    );
  }

  Widget _choiceTile(int i, String text) {
    final correct = _norm(text) == _norm((_q['correct_answer'] ?? '').toString());
    Color? border;
    Color? bg;
    if (_answered) {
      if (correct) {
        border = Colors.green;
        bg = Colors.green.withValues(alpha: 0.08);
      } else if (_selected == i) {
        border = Colors.redAccent;
        bg = Colors.red.withValues(alpha: 0.06);
      }
    } else if (_selected == i) {
      border = Theme.of(context).colorScheme.primary;
      bg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.06);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: _answered ? null : () => setState(() => _selected = i),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
                color: border ?? Colors.grey.shade300, width: 2),
            borderRadius: BorderRadius.circular(12),
            color: bg,
          ),
          child: Row(
            children: [
              Text('${i + 1})  ',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Expanded(child: MathText(text)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feedback() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _lastCorrect
            ? Colors.green.withValues(alpha: 0.08)
            : Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _lastCorrect ? Colors.green : Colors.redAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_lastCorrect ? '정답이에요 ✓' : '다시 볼까요',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _lastCorrect ? Colors.green.shade800 : Colors.red)),
          const SizedBox(height: 6),
          MathText('정답: ${_q['correct_answer'] ?? ''}'),
          if (_q['explanation'] != null) ...[
            const SizedBox(height: 4),
            MathText('해설: ${_q['explanation']}',
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar() {
    final canCheck = _isShort ? _shortCtrl.text.trim().isNotEmpty : _selected != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: !_answered
              ? (canCheck ? _checkAnswer : null)
              : _next,
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
          child: Text(!_answered
              ? '정답 확인'
              : (_index < _questions.length - 1 ? '다음 문제' : '결과 보기')),
        ),
      ),
    );
  }

  Widget _passView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🏆', style: TextStyle(fontSize: 80)),
            const SizedBox(height: 12),
            Text('$_correctCount / ${_questions.length}',
                style: const TextStyle(
                    fontSize: 40, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('미션 통과! 폰이 열렸어요 🔓',
                style: TextStyle(fontSize: 20)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _leave,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('완료'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _failView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📘', style: TextStyle(fontSize: 72)),
            const SizedBox(height: 12),
            Text('$_correctCount / ${_questions.length}',
                style: const TextStyle(
                    fontSize: 36, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              '조금만 더! 통과 기준은 80%예요.\n비슷한 새 문제로 다시 풀어볼까요?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _retry,
                icon: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh),
                label: Text(_busy ? '새 문제 준비 중...' : '비슷한 문제로 다시 도전'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
