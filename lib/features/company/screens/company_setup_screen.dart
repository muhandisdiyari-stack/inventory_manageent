import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/company_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../inventory_selection/screens/inventory_selection_screen.dart';

class CompanySetupScreen extends StatefulWidget {
  const CompanySetupScreen({super.key});

  @override
  State<CompanySetupScreen> createState() =>
      _CompanySetupScreenState();
}

class _CompanySetupScreenState
    extends State<CompanySetupScreen> {
  final _companyNameController = TextEditingController();
  final _invitationTokenController = TextEditingController();
  bool _showCreateForm = false;
  bool _showJoinForm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CompanyBloc>().add(const LoadCompanies());
    });
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _invitationTokenController.dispose();
    super.dispose();
  }

  void _createCompany() {
    final name = _companyNameController.text.trim();
    if (name.isEmpty) return;
    context.read<CompanyBloc>().add(CreateCompany(name));
    setState(() {
      _showCreateForm = false;
      _companyNameController.clear();
    });
  }

  void _joinCompany() {
    final token = _invitationTokenController.text.trim();
    if (token.isEmpty) return;
    context.read<CompanyBloc>().add(JoinCompany(token));
    setState(() {
      _showJoinForm = false;
      _invitationTokenController.clear();
    });
  }

  void _deleteCompany(
      String companyId, String companyName) async {
    final state = context.read<CompanyBloc>().state;
    final company = state.companies
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (c) => c?['id']?.toString() == companyId,
          orElse: () => null,
        );
    final role = company?['role']?.toString() ?? 'staff';
    if (role != 'owner') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Only owners can delete a company'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final confirmed =
        await _showDeleteConfirmationDialog(companyName);
    if (confirmed != true || !mounted) return;

    context
        .read<CompanyBloc>()
        .add(DeleteCompany(companyId, companyName));
  }

  Future<bool?> _showDeleteConfirmationDialog(
      String companyName) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool canDelete = false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.delete_forever_rounded,
                  color:
                      Theme.of(context).colorScheme.error,
                  size: 28),
              const SizedBox(width: 8),
              const Text('Delete Company',
                  style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  // Warning box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.05),
                      borderRadius:
                          BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red
                            .withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber,
                                color: Colors.red,
                                size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Warning',
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                                color: Colors.red,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'This action is permanent and cannot be undone.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // What gets deleted
                  const Text(
                    'The following will be permanently deleted:',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  const _DeleteItem(
                      icon: Icons.inventory_2,
                      text: 'All inventories'),
                  const _DeleteItem(
                      icon: Icons.label,
                      text: 'All items and labels'),
                  const _DeleteItem(
                      icon: Icons.people,
                      text: 'All member data'),
                  const _DeleteItem(
                      icon: Icons.mail,
                      text: 'All pending invitations'),
                  const _DeleteItem(
                      icon: Icons.history,
                      text: 'Activity logs'),
                  const SizedBox(height: 16),

                  // Confirmation input
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Type ',
                          style: TextStyle(fontSize: 13),
                        ),
                        TextSpan(
                          text: '"$companyName"',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const TextSpan(
                          text: ' to confirm:',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: 'Type company name',
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(10),
                      ),
                      filled: true,
                      contentPadding:
                          const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14),
                    ),
                    style: const TextStyle(fontSize: 14),
                    validator: (value) {
                      if (value == null ||
                          value.trim() != companyName) {
                        return 'Name does not match';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      setDialogState(() {
                        canDelete =
                            value.trim() == companyName;
                      });
                    },
                    onFieldSubmitted: (value) {
                      if (canDelete &&
                          formKey.currentState!
                              .validate()) {
                        Navigator.pop(ctx, true);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: canDelete
                  ? () {
                      if (formKey.currentState!
                          .validate()) {
                        Navigator.pop(ctx, true);
                      }
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: canDelete
                    ? Theme.of(context).colorScheme.error
                    : Colors.grey.shade300,
                foregroundColor: canDelete
                    ? Colors.white
                    : Colors.grey,
              ),
              child: const Text('Delete Company'),
            ),
          ],
        ),
      ),
    );
  }

  void _leaveCompany(
      String companyId, String companyName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Company'),
        content: Text('Leave "$companyName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    context
        .read<CompanyBloc>()
        .add(LeaveCompany(companyId, companyName));
  }

void _openCompany(String companyId, String companyName) {
    // Select the company in CompanyBloc
    context.read<CompanyBloc>().add(SelectCompany(companyId));

    // Navigate to inventory selection
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => const InventorySelectionScreen()),
    );
  }

  void _signOut() {
    context.read<AuthBloc>().add(const SignOutRequested());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return BlocListener<CompanyBloc, CompanyState>(
      listener: (context, state) {
        if (state.successMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.successMessage!),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context
              .read<CompanyBloc>()
              .add(const ClearMessages());
        }
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error!),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
          context
              .read<CompanyBloc>()
              .add(const ClearMessages());
        }
      },
      child:
          BlocBuilder<CompanyBloc, CompanyState>(
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Your Companies'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Sign Out',
                  onPressed: _signOut,
                ),
              ],
            ),
            body: state.isLoading && state.companies.isEmpty
                ? const Center(
                    child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      context
                          .read<CompanyBloc>()
                          .add(const LoadCompanies());
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (state.error != null)
                          Container(
                            margin: const EdgeInsets.only(
                                bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red
                                  .withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            child: Text(state.error!,
                                style: const TextStyle(
                                    color: Colors.red)),
                          ),

                        if (state.companies.isEmpty &&
                            !_showCreateForm)
                          Container(
                            margin: const EdgeInsets.only(
                                bottom: 16),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue
                                  .withValues(alpha: 0.1),
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.blue,
                                    size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'If you were invited to a company, '
                                    'sign in with the email that received the invitation '
                                    'and the company will appear here automatically.',
                                    style: TextStyle(
                                        fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        ...state.companies.map((c) {
                          final name =
                              c['name']?.toString() ?? '';
                          final role = (c['role']?.toString() ??
                                  'staff')
                              .toUpperCase();
                          final isOwner = role == 'OWNER';
                          final companyId =
                              c['id']?.toString() ?? '';

                          return Card(
                            margin: const EdgeInsets.only(
                                bottom: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(
                                        12)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorScheme
                                    .primaryContainer,
                                child: Icon(Icons.business,
                                    color:
                                        colorScheme.primary),
                              ),
                              title: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight
                                          .w600)),
                              subtitle:
                                  Text('Role: $role'),
                              trailing:
                                  PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'delete' &&
                                      isOwner) {
                                    _deleteCompany(
                                        companyId, name);
                                  }
                                  if (action == 'leave' &&
                                      !isOwner) {
                                    _leaveCompany(
                                        companyId, name);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  if (isOwner)
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons
                                                .delete_forever,
                                            size: 18,
                                            color:
                                                Colors.red,
                                          ),
                                          SizedBox(
                                              width: 8),
                                          Text('Delete',
                                              style: TextStyle(
                                                  color: Colors
                                                      .red)),
                                        ],
                                      ),
                                    ),
                                  if (!isOwner)
                                    const PopupMenuItem(
                                      value: 'leave',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons
                                                .exit_to_app,
                                            size: 18,
                                          ),
                                          SizedBox(
                                              width: 8),
                                          Text(
                                              'Leave Company'),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              onTap: () => _openCompany(
                                  companyId, name),
                            ),
                          );
                        }),

                        if (state.companies.isEmpty &&
                            !_showCreateForm)
                          Padding(
                            padding:
                                const EdgeInsets.all(32),
                            child: Column(children: [
                              Icon(Icons.business_outlined,
                                  size: 64,
                                  color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text('No companies yet',
                                  style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight
                                          .w600)),
                              const SizedBox(height: 8),
                              Text(
                                  'Create a company to get started',
                                  style: TextStyle(
                                      color:
                                          Colors.grey[500])),
                            ]),
                          ),

                        if (_showCreateForm)
                          Card(
                            child: Padding(
                              padding:
                                  const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('New Company',
                                      style: TextStyle(
                                          fontWeight: FontWeight
                                              .w600,
                                          fontSize: 16)),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller:
                                        _companyNameController,
                                    autofocus: true,
                                    textCapitalization:
                                        TextCapitalization
                                            .words,
                                    decoration:
                                        InputDecoration(
                                      hintText: 'Company name',
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius
                                              .circular(10)),
                                      filled: true,
                                    ),
                                    onSubmitted: (_) =>
                                        _createCompany(),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            setState(() {
                                          _showCreateForm =
                                              false;
                                          _companyNameController
                                              .clear();
                                        }),
                                        child: const Text(
                                            'Cancel'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed:
                                            _createCompany,
                                        child: const Text(
                                            'Create'),
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                          ),

                        if (_showJoinForm)
                          Card(
                            child: Padding(
                              padding:
                                  const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('Join Company',
                                      style: TextStyle(
                                          fontWeight: FontWeight
                                              .w600,
                                          fontSize: 16)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Usually invitations are auto-accepted. '
                                    'Use this only if you received a token.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller:
                                        _invitationTokenController,
                                    autofocus: true,
                                    decoration:
                                        InputDecoration(
                                      hintText:
                                          'Paste invitation token',
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius
                                              .circular(10)),
                                      filled: true,
                                    ),
                                    onSubmitted: (_) =>
                                        _joinCompany(),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            setState(() {
                                          _showJoinForm =
                                              false;
                                          _invitationTokenController
                                              .clear();
                                        }),
                                        child: const Text(
                                            'Cancel'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed:
                                            _joinCompany,
                                        style: FilledButton.styleFrom(
                                            backgroundColor:
                                                Colors.green),
                                        child: const Text(
                                            'Join'),
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                          ),

                        if (!_showCreateForm &&
                            !_showJoinForm) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => setState(() {
                                _showCreateForm = true;
                                _companyNameController
                                    .clear();
                              }),
                              icon: const Icon(
                                  Icons.add_business),
                              label: const Text(
                                  'Create New Company'),
                              style: FilledButton.styleFrom(
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                          vertical: 14)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() {
                                _showJoinForm = true;
                                _invitationTokenController
                                    .clear();
                              }),
                              icon: const Icon(
                                  Icons.group_add),
                              label: const Text(
                                  'Join with Token'),
                              style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                          vertical: 14)),
                            ),
                          ),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}

// Helper widget for delete confirmation items
class _DeleteItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DeleteItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: Colors.red.withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}