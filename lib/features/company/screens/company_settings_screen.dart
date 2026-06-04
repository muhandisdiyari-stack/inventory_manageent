import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/company_bloc.dart';
import '../../../core/utils/snackbar_utils.dart';
import 'inventory_members_screen.dart';

class CompanySettingsScreen extends StatefulWidget {
  final String inventoryId;
  final String inventoryName;

  const CompanySettingsScreen({
    super.key,
    this.inventoryId = 'default',
    this.inventoryName = '',
  });

  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CompanyBloc>().add(const LoadCompanies());
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocListener<CompanyBloc, CompanyState>(
      listener: (context, state) {
        if (state.successMessage != null && mounted) {
          SnackBarUtils.success(context, state.successMessage!);
          context.read<CompanyBloc>().add(const ClearMessages());
        }
        if (state.error != null && mounted) {
          SnackBarUtils.error(context, state.error!);
          context.read<CompanyBloc>().add(const ClearMessages());
        }
      },
      child: BlocBuilder<CompanyBloc, CompanyState>(
        builder: (context, state) {
          if (state.isLoading && state.companies.isEmpty) {
            return Scaffold(
              appBar: AppBar(title: const Text('Company Settings')),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          if (state.selectedCompany == null && !state.isLoading) {
            return Scaffold(
              appBar: AppBar(title: const Text('Company Settings')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.business_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text('No company selected',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      const Text(
                        'Please go back and select a company first.',
                        style: TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final companyName = state.selectedCompany!['name']?.toString() ?? 'Unknown';
          final hasInventory = widget.inventoryId != 'default' && widget.inventoryId.isNotEmpty;

          return Scaffold(
            appBar: AppBar(
              title: Text('$companyName - Settings'),
            ),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.business, color: colorScheme.primary, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(companyName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text(
                                'Membership is managed per inventory',
                                style: TextStyle(color: Colors.grey[600], fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                          ),
                          const SizedBox(width: 12),
                          const Text('How Membership Works',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ]),
                        const SizedBox(height: 12),
                        const Text(
                          'Membership is now managed at the inventory level. '
                          'Each inventory has its own members, roles, and permissions.',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'To manage members:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '• Open an inventory\n'
                          '• Tap the People icon in the top bar\n'
                          '• Invite, remove, or change roles for that inventory',
                          style: TextStyle(fontSize: 14, height: 1.8),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (hasInventory)
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.people, color: Colors.green, size: 20),
                      ),
                      title: const Text('Manage Inventory Members',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('View and manage members for "${widget.inventoryName}"'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InventoryMembersScreen(
                              inventoryId: widget.inventoryId,
                              inventoryName: widget.inventoryName,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (!hasInventory)
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(Icons.inventory_2, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            'Open an inventory to manage its members',
                            style: TextStyle(color: Colors.grey[600]),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}