import 'package:flutter/material.dart';
import '../../../core/services/admin_service.dart';

class CompaniesManagement extends StatefulWidget {
  const CompaniesManagement({super.key});

  @override
  State<CompaniesManagement> createState() => _CompaniesManagementState();
}

class _CompaniesManagementState extends State<CompaniesManagement> {
  final AdminService _adminService = AdminService();
  List<Map<String, dynamic>> _companies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    setState(() => _isLoading = true);
    _companies = await _adminService.getAllCompanies();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('All Companies', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Text('${_companies.length} total', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _companies.isEmpty
                  ? const Center(child: Text('No companies found'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _companies.length,
                      itemBuilder: (_, i) {
                        final company = _companies[i];
                        final name = company['name']?.toString() ?? 'Unknown';
                        final ownerId = company['owner_user_id']?.toString() ?? '';
                        final createdAt = company['created_at']?.toString() ?? '';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: const Icon(Icons.business, color: Colors.blue),
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('Created: ${createdAt.substring(0, 10)}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.info_outline),
                              onPressed: () => _showCompanyDetails(company),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  void _showCompanyDetails(Map<String, dynamic> company) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(company['name']?.toString() ?? 'Company Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('ID', company['id']?.toString() ?? ''),
            _detailRow('Created', company['created_at']?.toString() ?? ''),
            _detailRow('Updated', company['updated_at']?.toString() ?? ''),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}