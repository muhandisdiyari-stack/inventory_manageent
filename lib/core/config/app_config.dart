class AppConfig {
  static const String environment = 'development';

  // ─── Database Mode ─────────────────────────────────────────────
  static const bool useSupabase = true;

  // ─── Supabase Configuration ────────────────────────────────────
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

  // ─── REMOVED: autoLoadDemoData ─────────────────────────────────
  // Demo data is no longer used in this multi-tenant workflow

  // ─── Helpers ───────────────────────────────────────────────────
  static bool get isDevelopment => environment == 'development';
  static bool get isProduction => environment == 'production';
  static bool get isCloudEnabled => useSupabase;
  static bool get requiresAuth => enableAuthentication;

  static bool validate() {
    if (useSupabase) {
      if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
        throw Exception('Supabase configuration missing.');
      }
    }
    return true;
  }
}