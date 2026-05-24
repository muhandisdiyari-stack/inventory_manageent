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

    // ✅ Show confirmation dialog with name typing
    final confirmed = await _showDeleteConfirmationDialog(
        companyName);
    if (confirmed != true || !mounted) return;

    context
        .read<CompanyBloc>()
        .add(DeleteCompany(companyId, companyName));
  }

  /// Shows a confirmation dialog that requires typing the company name
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
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.delete_forever_rounded,
              color:
                  Theme.of(context).colorScheme.error,
              size: 32,
            ),
          ),
          title: const Text('Delete Company'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                    children: [
                      const TextSpan(
                        text:
                            'This action is ',
                      ),
                      TextSpan(
                        text:
                            'permanent and irreversible',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .error,
                        ),
                      ),
                      const TextSpan(
                        text:
                            '. All data related to this company will be permanently deleted:\n\n',
                      ),
                      const TextSpan(
                        text:
                            '• All inventories\n',
                      ),
                      const TextSpan(
                        text:
                            '• All items and labels\n',
                      ),
                      const TextSpan(
                        text:
                            '• All member data\n',
                      ),
                      const TextSpan(
                        text:
                            '• All pending invitations\n',
                      ),
                      const TextSpan(
                        text:
                            '• Activity logs\n',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'To confirm, type "$companyName" below:',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Type company name',
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    filled: true,
                    prefixIcon: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red),
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim() !=
                            companyName) {
                      return 'Company name does not match';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    setDialogState(() {
                      canDelete =
                          value.trim() == companyName;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(12),
                ),
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
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
                    ? Theme.of(context)
                        .colorScheme
                        .error
                    : Colors.grey,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Delete Everything',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
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
    context
        .read<CompanyBloc>()
        .add(SelectCompany(companyId));

    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) =>
              const InventorySelectionScreen()),
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