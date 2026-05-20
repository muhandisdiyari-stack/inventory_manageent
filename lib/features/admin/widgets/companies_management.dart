import 'package:flutter/material.dart';
import '../../../core/services/admin_service.dart';

class CompaniesManagement extends StatefulWidget {
  final AdminService adminService;

  const CompaniesManagement({super.key, required this.adminService});

  @override
  State<CompaniesManagement> createState() =>
      _CompaniesManagementState();
}

class _CompaniesManagementState extends State<CompaniesManagement> {
  List<Map<String, dynamic>> _companies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final companies = await widget.adminService.getAllCompanies();

    if (!mounted) return;
    setState(() {
      _companies = companies;
      _isLoading = false;
    });
  }

  /// Safely trims an ISO-8601 timestamp string to a date (YYYY-MM-DD).
  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return DateTime.parse(raw)
          .toLocal()
          .toString()
          .substring(0, 10);
    } catch (_) {
      return raw.length >= 10 ? raw.substring(0, 10) : raw;
    }
  }

  /// Safely formats a full ISO-8601 timestamp for display.
  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
          '${_pad(dt.hour)}:${_pad(dt.minute)}';
    } catch (_) {
      return raw.length >= 19 ? raw.substring(0, 19) : raw;
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text('All Companies',
                style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            if (!_isLoading)
              Text('${_companies.length} total',
                  style: TextStyle(color: Colors.grey[600])),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadCompanies,
              tooltip: 'Refresh',
            ),
          ]),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _companies.isEmpty
                  ? const Center(child: Text('No companies found'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16),
                      itemCount: _companies.length,
                      itemBuilder: (_, i) {
                        final company = _companies[i];
                        final name =
                            company['name']?.toString() ??
                                'Unknown';
                        final createdAt = _formatDate(
                            company['created_at']?.toString());

                        return Card(
                          margin:
                              const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  Colors.blue.shade100,
                              child: const Icon(Icons.business,
                                  color: Colors.blue),
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight:
                                        FontWeight.w600)),
                            subtitle:
                                Text('Created: $createdAt'),
                            trailing: IconButton(
                              icon: const Icon(
                                  Icons.info_outline),
                              onPressed: () =>
                                  _showCompanyDetails(company),
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
        title:
            Text(company['name']?.toString() ?? 'Company Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('ID', company['id']?.toString() ?? '—'),
            _detailRow('Created',
                _formatDateTime(company['created_at']?.toString())),
            _detailRow('Updated',
                _formatDateTime(company['updated_at']?.toString())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
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
          SizedBox(
              width: 80,
              child: Text('$label:',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}