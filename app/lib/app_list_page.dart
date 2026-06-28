import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 실험: 이 폰에 깔린 "실행 가능한 앱" 목록을 읽어서 보여준다.
// (나중에 부모가 허용 앱을 고르는 화면의 토대)
class AppListPage extends StatefulWidget {
  const AppListPage({super.key});

  @override
  State<AppListPage> createState() => _AppListPageState();
}

class _AppListPageState extends State<AppListPage> {
  static const _channel = MethodChannel('unolock/lock');

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _apps = [];

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
      final raw = await _channel.invokeMethod('listApps');
      final apps = (raw as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _apps = apps;
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
        title: const Text('깔린 앱 목록 (실험)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
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
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('이 폰에서 ${_apps.length}개 앱을 찾았어요',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _apps.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final a = _apps[i];
                          return ListTile(
                            leading: const Icon(Icons.android),
                            title: Text(a['name']?.toString() ?? '(이름 없음)'),
                            subtitle: Text(a['package']?.toString() ?? '',
                                style: const TextStyle(fontSize: 11)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
