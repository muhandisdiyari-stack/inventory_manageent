import 'package:flutter/foundation.dart';
import '../../../core/database/hive/hive_cache_service.dart';
import '../../../core/models/company.dart';

class CompanyProvider extends ChangeNotifier {
  // _cacheService is retained for future use (e.g. offline caching) but is
  // not called until we know the actual HiveCacheService API. Companies are
  // managed in-memory and populated via setCompanies() by callers that already
  // hold the data (e.g. after AuthService.getUserCompanies() returns).
  // ignore: unused_field
  final HiveCacheService _cacheService;

  Company? _selectedCompany;
  final List<Company> _companies = [];
  bool _isLoading = false;
  String? _error;

  CompanyProvider({required HiveCacheService cacheService})
      : _cacheService = cacheService;

  Company? get selectedCompany => _selectedCompany;
  String? get selectedCompanyId => _selectedCompany?.id;
  List<Company> get companies => List.unmodifiable(_companies);
  bool get hasCompanies => _companies.isNotEmpty;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Replace the in-memory company list. Call this after fetching companies
  /// from AuthService so the provider stays in sync without needing its own
  /// network/cache layer.
  void setCompanies(List<Company> companies) {
    _companies
      ..clear()
      ..addAll(companies);
    // If the previously selected company is no longer in the list, clear it.
    if (_selectedCompany != null &&
        !_companies.any((c) => c.id == _selectedCompany!.id)) {
      _selectedCompany = null;
    }
    notifyListeners();
  }

  /// Add or update a single company in the in-memory list.
  void upsertCompany(Company company) {
    final index = _companies.indexWhere((c) => c.id == company.id);
    if (index >= 0) {
      _companies[index] = company;
    } else {
      _companies.add(company);
    }
    notifyListeners();
  }

  /// Remove a company from the in-memory list.
  void removeCompany(String companyId) {
    _companies.removeWhere((c) => c.id == companyId);
    if (_selectedCompany?.id == companyId) {
      _selectedCompany = null;
    }
    notifyListeners();
  }

  void selectCompany(String companyId) {
    _selectedCompany = _companies.firstWhere(
      (c) => c.id == companyId,
      orElse: () => Company(id: companyId, name: 'Unknown'),
    );
    notifyListeners();
  }

  void clearSelection() {
    _selectedCompany = null;
    notifyListeners();
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? error) {
    _error = error;
    notifyListeners();
  }
}