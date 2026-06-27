import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';
import 'math_text.dart';

// 한 반의 "오늘 수업" 화면.
// 사진 여러 장을 모아 한 번에 올리면 = 새 수업 묶음(lesson_batch) 1개.
// 그 묶음으로 AI 출제를 호출한다. (웹 ClassLesson 과 같은 규칙)
class ClassLessonPage extends StatefulWidget {
  final String academyId;
  final String classId;
  final String className;

  const ClassLessonPage({
    super.key,
    required this.academyId,
    required this.classId,
    required this.className,
  });

  @override
  State<ClassLessonPage> createState() => _ClassLessonPageState();
}

class _ClassLessonPageState extends State<ClassLessonPage> {
  final _picker = ImagePicker();

  bool _loading = true;
  String? _batchId; // 가장 최근 수업 묶음
  int _materialCount = 0; // 그 묶음에 담긴 사진 수
  final List<XFile> _picked = []; // 올리려고 고른 사진들

  bool _uploading = false;
  bool _generating = false;
  String? _error;

  Map<String, dynamic>? _quiz; // { title, questions }

  String get _userId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 이 반의 가장 최근 묶음 + 사진 수 불러오기.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final batches = await supabase
          .from('lesson_batches')
          .select('id, created_at')
          .eq('class_id', widget.classId)
          .order('created_at', ascending: false)
          .limit(1);
      if (batches.isNotEmpty) {
        _batchId = batches.first['id'] as String;
        final mats = await supabase
            .from('materials')
            .select('id')
            .eq('batch_id', _batchId!);
        _materialCount = mats.length;
      } else {
        _batchId = null;
        _materialCount = 0;
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (shot != null) setState(() => _picked.add(shot));
    } catch (e) {
      setState(() => _error = '촬영 실패: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final shots = await _picker.pickMultiImage(imageQuality: 85);
      if (shots.isNotEmpty) setState(() => _picked.addAll(shots));
    } catch (e) {
      setState(() => _error = '갤러리 선택 실패: $e');
    }
  }

  String _contentType(XFile f) {
    final mime = f.mimeType;
    if (mime != null && mime.isNotEmpty) return mime;
    final name = f.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  // 고른 사진들로 새 수업 묶음 1개를 만들고 모두 업로드.
  Future<void> _upload() async {
    if (_picked.isEmpty) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      // 1) 새 수업 묶음
      final b = await supabase
          .from('lesson_batches')
          .insert({
            'class_id': widget.classId,
            'academy_id': widget.academyId,
            'created_by': _userId,
          })
          .select('id')
          .single();
      final batchId = b['id'] as String;

      // 2) 사진 업로드 + materials 기록 (경로 첫 폴더 = 학원id, 권한 규칙)
      for (final f in _picked) {
        final bytes = await f.readAsBytes();
        final safe = f.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
        final path =
            '${widget.academyId}/$batchId/${DateTime.now().millisecondsSinceEpoch}_$safe';
        await supabase.storage.from('materials').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: _contentType(f)),
            );
        await supabase.from('materials').insert({
          'academy_id': widget.academyId,
          'class_id': widget.classId,
          'batch_id': batchId,
          'uploaded_by': _userId,
          'title': f.name,
          'storage_path': path,
          'file_type': 'image',
        });
      }
      setState(() {
        _picked.clear();
        _quiz = null;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('업로드 완료 — 오늘 수업이 새로 만들어졌어요.')),
        );
      }
    } catch (e) {
      setState(() => _error = '업로드 실패: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // 현재 묶음으로 AI 출제 호출.
  Future<void> _generate() async {
    if (_batchId == null) return;
    setState(() {
      _generating = true;
      _error = null;
      _quiz = null;
    });
    try {
      final res = await supabase.functions.invoke(
        'generate-questions',
        body: {'batch_id': _batchId},
      );
      final data = res.data;
      if (data is Map && data['error'] != null) {
        setState(() => _error = 'AI 출제 실패: ${data['error']}');
      } else if (data is Map) {
        setState(() => _quiz = Map<String, dynamic>.from(data));
      }
    } on FunctionException catch (e) {
      setState(() => _error = 'AI 출제 실패: ${e.details ?? e.reasonPhrase}');
    } catch (e) {
      setState(() => _error = 'AI 출제 실패: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.className)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _todayCard(),
                const SizedBox(height: 16),
                _pickButtons(),
                if (_picked.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _pickedPreview(),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _uploading ? null : _upload,
                      icon: _uploading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(_uploading
                          ? '올리는 중...'
                          : '이 사진 ${_picked.length}장으로 오늘 수업 올리기'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _generateButton(),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text('❌ $_error',
                      style: const TextStyle(color: Colors.red)),
                ],
                if (_quiz != null) ...[
                  const SizedBox(height: 20),
                  _quizPreview(),
                ],
              ],
            ),
    );
  }

  Widget _todayCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.collections_outlined, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _batchId == null
                    ? '아직 오늘 수업이 없어요.\n사진을 올리면 만들어져요.'
                    : '오늘 수업: 사진 $_materialCount장',
                style: const TextStyle(fontSize: 16, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : _takePhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('촬영'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _uploading ? null : _pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('갤러리'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pickedPreview() {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _picked.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Image.file(File(_picked[i].path),
                    width: 92, height: 92, fit: BoxFit.cover),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => setState(() => _picked.removeAt(i)),
                    child: const CircleAvatar(
                      radius: 11,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _generateButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: (_batchId == null || _generating) ? null : _generate,
        icon: _generating
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_awesome),
        label: Text(_generating ? 'AI가 문제 만드는 중...' : '✨ AI 출제'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF6C5CE7),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Widget _quizPreview() {
    final questions = List<Map<String, dynamic>>.from(
        (_quiz!['questions'] as List?) ?? const []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '✨ ${_quiz!['title'] ?? '생성된 문제'} · ${questions.length}문제',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < questions.length; i++) _questionCard(i, questions[i]),
      ],
    );
  }

  Widget _questionCard(int i, Map<String, dynamic> q) {
    // 함수가 주는 실제 이름: body(문제), choices(보기), correct_answer(정답), explanation(해설).
    final choices = List<dynamic>.from(q['choices'] ?? const []);
    final typeLabel = q['type'] == 'short' ? '주관식' : '객관식';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Q${i + 1} · $typeLabel',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            MathText('${q['body'] ?? ''}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            if (choices.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (var j = 0; j < choices.length; j++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: MathText('${j + 1}) ${choices[j]}'),
                ),
            ],
            const SizedBox(height: 8),
            MathText('정답: ${q['correct_answer'] ?? ''}',
                style: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.w600)),
            if (q['explanation'] != null) ...[
              const SizedBox(height: 4),
              MathText('해설: ${q['explanation']}',
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}
