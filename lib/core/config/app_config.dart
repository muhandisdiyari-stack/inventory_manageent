import 'package:flutter/material.dart';

/// Central app configuration.
///
/// This is the SINGLE SOURCE OF TRUTH for all app configuration.
/// Version numbers, feature flags, and environment settings are all here.
class AppConfig {
  // ─── Environment ──────────────────────────────────────────────
  static const String environment = 'development';

  // ─── Database Mode ───────────────────────────────────────────
  static const bool useSupabase = true;

  // ─── Supabase Configuration ──────────────────────────────────
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://mhyvwpseafkdpzeopqkt.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_e_uIekIur_GgIM8Pa-WkNg_TgnpbqIy',
  );

  // ─── Feature Flags ───────────────────────────────────────────
  static const bool enableAuthentication = true;
  static const bool enableMultiTenant = true;
  static const bool enableOfflineSync = true;
  static const bool enableRowLevelSecurity = true;

  // ─── App Info (SINGLE SOURCE OF TRUTH) ───────────────────────
  static const String appName = 'Inventory Pro';
  static const String appVersion = '2.1.0';
  static const String buildNumber = '1';
  static const String buildDate = '2026-05-06';

  static String get fullVersion => '$appVersion+$buildNumber';

  // ─── Helpers ─────────────────────────────────────────────────
  static bool get isDevelopment => environment == 'development';
  static bool get isProduction => environment == 'production';
  static bool get isCloudEnabled => useSupabase;
  static bool get requiresAuth => enableAuthentication;

  /// Validates configuration. Throws if required settings are missing.
  static bool validate() {
    if (useSupabase) {
      if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
        throw Exception(
            'Supabase configuration missing. Set SUPABASE_URL and SUPABASE_ANON_KEY environment variables.');
      }
    }
    return true;
  }

  /// Logs configuration at startup for debugging.
  static void logConfig() {
    debugPrint('═══════════════════════════════════════════');
    debugPrint('  $appName v$fullVersion');
    debugPrint('  Environment: $environment');
    debugPrint('  Build Date: $buildDate');
    debugPrint('  Supabase: ${useSupabase ? "Enabled" : "Disabled"}');
    debugPrint('  Auth: ${enableAuthentication ? "Required" : "Disabled"}');
    debugPrint('  Multi-tenant: ${enableMultiTenant ? "Enabled" : "Disabled"}');
    debugPrint('  Offline Sync: ${enableOfflineSync ? "Enabled" : "Disabled"}');
    debugPrint('═══════════════════════════════════════════');
  }
}