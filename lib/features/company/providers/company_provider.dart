import 'package:flutter/foundation.dart';
import '../../../core/models/company.dart';

class CompanyProvider extends ChangeNotifier {
  Company? _selectedCompany;
  final List<Company> _companies = [];

  // FIX #8: Removed unused _cacheService and HiveCacheService import
  CompanyProvider();

  Company? get selectedCompany => _selectedCompany;
  String? get selectedCompanyId => _selectedCompany?.id;
  List<Company> get companies => List.unmodifiable(_companies);
  bool get hasCompanies => _companies.isNotEmpty;

  void selectCompany(String companyId) {
    _selectedCompany = _companies.firstWhere(
      (c) => c.id == companyId,
      orElse: () => Company(id: companyId, name: 'Unknown'),
    );
    notifyListeners();
  }

  void setCompanies(List<Company> companies) {
    _companies.clear();
    _companies.addAll(companies);
    notifyListeners();
  }

  void clearSelection() {
    _selectedCompany = null;
    notifyListeners();
  }
}