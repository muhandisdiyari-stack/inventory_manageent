// File: lib/features/inventory_management/services/demo_data_service.dart
//
// DEMO DATA SERVICE HAS BEEN REMOVED
// This project now uses a proper multi-tenant workflow:
// - User creates account
// - User creates companies
// - User creates inventories within companies
// - Members are invited to specific inventories
//
// Demo data is no longer needed and this service is deprecated.

class DemoDataService {
  /// No-op - Demo data is not used in the multi-tenant workflow.
  static Future<void> loadDemoData() async {
    // Intentionally empty - demo data removed
    return;
  }
}