import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../database/hive/hive_cache_service.dart';
import '../database/supabase/supabase_client.dart';
import '../services/auth_service.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/company/providers/company_provider.dart';

class InjectionContainer {
  static final HiveCacheService cacheService = HiveCacheService();
  static final SupabaseClientService supabaseClient = SupabaseClientService();
  static final AuthService authService = AuthService(
    supabaseClient: supabaseClient,
  );

  static List<ChangeNotifierProvider<ChangeNotifier>>
      registerChangeNotifierProviders() {
    return [
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(authService: authService),
      ),
      ChangeNotifierProvider<CompanyProvider>(
        create: (_) => CompanyProvider(),
      ),
    ];
  }

  static Future<void> initialize() async {
    await authService.initialize();
  }
}