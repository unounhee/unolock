import 'package:supabase_flutter/supabase_flutter.dart';

// 앱을 실행할 때 --dart-define-from-file=env.json 으로 넣어주는 값들.
// (env.json 은 git에 안 올라가는 비밀 파일. 값은 대표님이 직접 입력.)
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// 두 값이 채워져 있는지.
bool get hasSupabaseKeys =>
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

// 앱 시작 시 한 번 호출. 값이 없으면 조용히 건너뜀(연결 안 함).
Future<void> initSupabase() async {
  if (!hasSupabaseKeys) return;
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
}

// 어디서든 두뇌(Supabase)에 접근할 때 쓰는 손잡이.
SupabaseClient get supabase => Supabase.instance.client;
