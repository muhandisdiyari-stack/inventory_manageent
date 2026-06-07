import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/admin_bloc.dart';

class CompaniesManagement extends StatefulWidget {
  const CompaniesManagement({super.key});

  @override
  State<CompaniesManagement> createState() => _CompaniesManagementState();
}

class _CompaniesManagementState extends State<CompaniesManagement> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AdminBloc>().add(const LoadAdminCompanies());
      }
    });
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      return DateTime.parse(raw).toLocal().toString().substring(0, 10);
    } catch (_) {
      return raw.length >= 10 ? raw.substring(0, 10) : raw;
    }
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
    } catch (_) {
      return raw.length >= 19 ? raw.substring(0, 19) : raw;
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  void _showCompanyDetails(Map<String, dynamic> company) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(company['name']?.toString() ?? 'Company Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('ID', company['id']?.toString() ?? '—'),
            _detailRow('Owner', company['owner_name']?.toString() ?? company['full_name']?.toString() ?? '—'),
            _detailRow('Owner Email', company['owner_email']?.toString() ?? '—'),
            _detailRow('Inventories', company['inventory_count']?.toString() ?? '0'),
            _detailRow('Items', company['item_count']?.toString() ?? '0'),
            _detailRow('Created', _formatDateTime(company['created_at']?.toString())),
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 80, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: Text(value)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdminBloc, AdminState>(
      builder: (context, state) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Text('All Companies', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                if (!state.isLoading)
                  Text('${state.companies.length} total', style: TextStyle(color: Colors.grey[600])),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => context.read<AdminBloc>().add(const LoadAdminCompanies()),
                  tooltip: 'Refresh',
                ),
              ]),
            ),
            Expanded(
              child: state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : state.companies.isEmpty
                      ? const Center(child: Text('No companies found'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: state.companies.length,
                          itemBuilder: (_, i) {
                            final company = state.companies[i];
                            final name = company['name']?.toString() ?? 'Unknown';
                            final ownerName = company['owner_name']?.toString() ?? '—';
                            final inventoryCount = company['inventory_count']?.toString() ?? '0';
                            final itemCount = company['item_count']?.toString() ?? '0';
                            final createdAt = _formatDate(company['created_at']?.toString());

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.shade100,
                                  child: const Icon(Icons.business, color: Colors.blue),
                                ),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('Owner: $ownerName • $inventoryCount inventories • $itemCount items\nCreated: $createdAt'),
                                isThreeLine: true,
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
      },
    );
  }
}