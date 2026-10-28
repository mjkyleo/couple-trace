/// Trace · 同迹 — 全局配置。
/// 通过 --dart-define 注入真实值，例如：
///   flutter run --dart-define=TRACE_SUPABASE_URL=https://xxx.memfiredb.com \
///               --dart-define=TRACE_SUPABASE_ANON_KEY=xxx \
///               --dart-define=TRACE_STORAGE_FN_URL=https://xxx
class AppConfig {
  AppConfig._();

  /// MemFire / Supabase 项目地址
  static const String supabaseUrl = String.fromEnvironment(
    'TRACE_SUPABASE_URL',
    defaultValue: 'https://your-project.memfiredb.com',
  );

  /// MemFire anon key（仅具 RLS 约束的匿名权限，不包含任何秘密）
  static const String supabaseAnonKey = String.fromEnvironment(
    'TRACE_SUPABASE_ANON_KEY',
    defaultValue: 'your-anon-key',
  );

  /// 云函数入口地址（部署 storage-functions 后填写）
  static const String storageFnUrl = String.fromEnvironment(
    'TRACE_STORAGE_FN_URL',
    defaultValue: 'https://your-functions.example.com',
  );

  /// 签名有效期（与云函数保持一致）
  static const int uploadExpireSeconds = 900;
  static const int downloadExpireSeconds = 1800;
}
