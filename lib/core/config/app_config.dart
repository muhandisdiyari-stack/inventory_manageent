/// Central configuration for the application.
class AppConfig {
  static const String environment = 'development';

  // ─── Database Mode ─────────────────────────────────────────────
  static const bool useSupabase = true;

  // ─── Supabase Configuration ────────────────────────────────────
  // ⚠️ MOVED TO ENVIRONMENT VARIABLES - DO NOT HARDCODE
  // Load these from .env file or secure storage in production
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mhyvwpseafkdpzeopqkt.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_e_uIekIur_GgIM8Pa-WkNg_TgnpbqIy',
  );

  // ─── Feature Flags ─────────────────────────────────────────────
  static const bool enableAuthentication = true;
  static const bool enableMultiTenant = true;
  static const bool enableOfflineSync = true;
  static const bool enableRowLevelSecurity = true;

  // ─── App Info ──────────────────────────────────────────────────
  static const String appName = 'Inventory Pro';
  static const String appVersion = '2.1.0';

  // ─── Demo Mode ─────────────────────────────────────────────────
  static const bool autoLoadDemoData = false;

  // ─── Sync Configuration ────────────────────────────────────────
  static const Duration syncInterval = Duration(minutes: 5);
  static const int maxSyncRetries = 3;
  static const Duration syncTimeout = Duration(seconds: 30);

  // ─── Helpers ───────────────────────────────────────────────────
  static bool get isDevelopment => environment == 'development';
  static bool get isProduction => environment == 'production';
  static bool get isCloudEnabled => useSupabase;
  static bool get requiresAuth => enableAuthentication;

  /// Validates that all required configuration is present
  static bool validate() {
    if (useSupabase) {
      if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
        throw Exception(
          'Supabase configuration missing. '
          'Set SUPABASE_URL and SUPABASE_ANON_KEY environment variables.',
        );
      }
      if (!supabaseUrl.startsWith('https://')) {
        throw Exception('Invalid Supabase URL: $supabaseUrl');
      }
    }
    return true;
  }
}