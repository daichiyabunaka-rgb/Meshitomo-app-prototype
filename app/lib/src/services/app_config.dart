/// アプリの実行時設定。
/// Supabase の接続情報は --dart-define で渡す:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
/// 未指定の場合はモックモード（端末内データ）で動作する。
/// anon key は公開鍵（RLS で保護される）なのでアプリに埋め込めるが、
/// サービスロールキーは絶対に埋め込まないこと。
class AppConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Supabase が設定されているか（false = モックモード）
  static bool get useSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
