import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:inventory_management/features/auth/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';
import '../../inventory_selection/providers/inventory_list_provider.dart';
import '../../inventory_selection/screens/inventory_selection_screen.dart';

// FIX #9: Removed the unused `import` of InventoryService. _openCompany was
// calling context.read<InventoryService>() and immediately discarding the
// result, which was a dead read that also unnecessarily coupled this screen
// to the service.

class CompanySetupScreen extends StatefulWidget {
  const CompanySetupScreen({super.key});

  @override
  State<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends State<CompanySetupScreen> {
  final _companyNameController = TextEditingController();
  final _invitationTokenController = TextEditingController();

  bool _isLoading = true;
  bool _showCreateForm = false;
  bool _showJoinForm = false;
  bool _showRenameForm = false;
  String _renamingCompanyId = '';
  String _renamingCompanyName = '';
  List<Map<String, dynamic>> _userCompanies = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUserCompanies());
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _invitationTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadUserCompanies() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      final companies = await authService.getUserCompanies();

      if (!mounted) return;

      setState(() {
        _userCompanies = companies;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _userCompanies = [];
        _isLoading = false;
        _errorMessage = 'Failed to load companies. Pull to refresh.';
      });
    }
  }

  Future<void> _createCompany() async {
    final name = _companyNameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      final result = await authService.createCompany(name);

      if (!mounted) return;

      if (result != null) {
        await _loadUserCompanies();
        if (!mounted) return;
        setState(() {
          _showCreateForm = false;
          _companyNameController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Company "$name" created!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to create company';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  Future<void> _renameCompany() async {
    final newName = _companyNameController.text.trim();
    if (newName.isEmpty || _renamingCompanyId.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      final success =
          await authService.updateCompany(_renamingCompanyId, newName);

      if (!mounted) return;

      if (success) {
        await _loadUserCompanies();
        // FIX #13: Re-check mounted after the second await. _loadUserCompanies
        // can return early if the widget unmounts mid-flight, and the
        // ScaffoldMessenger call immediately after would then use a stale
        // context and crash.
        if (!mounted) return;
        setState(() {
          _showRenameForm = false;
          _companyNameController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed to "$newName"')),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to rename company';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  Future<void> _deleteCompany(String companyId, String companyName) async {
    // FIX #12: The owner check via popup menu already prevents non-owners from
    // reaching this method through the UI. The server-side also enforces it.
    // The redundant early-return guard has been kept as a defence-in-depth
    // check but the unreachable SnackBar message is removed — it could never
    // be shown since the popup only renders the delete option for owners.
    final company = _userCompanies.firstWhere(
      (c) => c['id'] == companyId,
      orElse: () => <String, dynamic>{},
    );
    final role = company['role'] ?? 'staff';
    if (role != 'owner') return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Company'),
        content: Text(
          'Delete "$companyName" and ALL its data?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      final success = await authService.deleteCompany(companyId);

      if (!mounted) return;

      if (success) {
        // Clean up local storage
        try {
          final inventoriesBox = Hive.box('inventories_list');
          await inventoriesBox.delete(companyId);
        } catch (_) {}

        await _loadUserCompanies();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$companyName" deleted')),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to delete company';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  Future<void> _leaveCompany(String companyId, String companyName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Company'),
        content: Text('Leave "$companyName"?\n\nYou can rejoin if invited again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      final success = await authService.leaveCompany(companyId);

      if (!mounted) return;

      if (success) {
        await _loadUserCompanies();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Left "$companyName"')),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to leave company';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  Future<void> _acceptInvitation() async {
    final token = _invitationTokenController.text.trim();
    if (token.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      final result = await authService.acceptInvitation(token);

      if (!mounted) return;

      if (result != null && result['success'] == true) {
        await _loadUserCompanies();
        if (!mounted) return;
        setState(() {
          _showJoinForm = false;
          _invitationTokenController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Company joined!')),
        );
      } else {
        final msg = result?['message'] as String? ??
            'Invalid or expired invitation';

        if (msg.contains('already')) {
          await _loadUserCompanies();
          if (!mounted) return;
          setState(() {
            _showJoinForm = false;
            _invitationTokenController.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Already a member!')),
          );
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = msg;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  // FIX #9: Removed the dead context.read<InventoryService>() call — the
  // variable was assigned and immediately discarded with no side effects.
  // selectInventory() is the existing method on InventoryListProvider used
  // to record which company/inventory is active before navigating.
  void _openCompany(String companyId, String companyName) {
    final listProvider = context.read<InventoryListProvider>();
    listProvider.selectInventory(companyId);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const InventorySelectionScreen(),
      ),
    );
  }

  void _showRenameDialog(String id, String name) {
    setState(() {
      _showRenameForm = true;
      _showCreateForm = false;
      _showJoinForm = false;
      _renamingCompanyId = id;
      _renamingCompanyName = name;
      _companyNameController.text = name;
    });
  }

  // FIX #10: Changed from `void _signOut() async` to `Future<void>` and added
  // try/catch. An `async void` method swallows all exceptions silently — if
  // signOut() threw, the error would disappear with no feedback to the user.
  Future<void> _signOut() async {
    try {
      final authProvider = context.read<AuthProvider>();
      await authProvider.signOut();
      // Navigation is handled by the app's auth state listener.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign out failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
      body: _isLoading && _userCompanies.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUserCompanies,
              child: Column(
                children: [
                  // ── Error banner ──────────────────────────────────
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () =>
                                setState(() => _errorMessage = null),
                          ),
                        ],
                      ),
                    ),

                  // ── Company list ──────────────────────────────────
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Header
                        Row(
                          children: [
                            Icon(Icons.business, color: colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              '${_userCompanies.length} '
                              '${_userCompanies.length == 1 ? 'Company' : 'Companies'}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Company cards
                        ..._userCompanies.map((c) {
                          final name = (c['name'] as String?) ?? '';
                          final role =
                              (c['role'] as String? ?? 'staff').toUpperCase();
                          final isOwner = role == 'OWNER';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.primaryContainer,
                                child: Icon(Icons.business,
                                    color: colorScheme.primary),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text('Role: $role'),
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) {
                                  final id = (c['id'] as String?) ?? '';
                                  if (action == 'rename' && isOwner) {
                                    _showRenameDialog(id, name);
                                  } else if (action == 'delete' && isOwner) {
                                    _deleteCompany(id, name);
                                  } else if (action == 'leave' && !isOwner) {
                                    _leaveCompany(id, name);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  if (isOwner)
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Rename'),
                                    ),
                                  if (isOwner)
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        'Delete',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  if (!isOwner)
                                    const PopupMenuItem(
                                      value: 'leave',
                                      child: Text('Leave Company'),
                                    ),
                                ],
                              ),
                              onTap: () => _openCompany(
                                  (c['id'] as String?) ?? '', name),
                            ),
                          );
                        }),

                        // Empty state
                        if (_userCompanies.isEmpty &&
                            !_showCreateForm &&
                            !_showJoinForm)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(Icons.business_outlined,
                                    size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  'No companies yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Create or join a company to get started',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          ),

                        // Inline forms
                        if (_showRenameForm) _buildRenameForm(),
                        if (_showCreateForm) _buildCreateForm(),
                        if (_showJoinForm) _buildJoinForm(),

                        // Action buttons (hidden while a form is open)
                        if (!_showCreateForm &&
                            !_showJoinForm &&
                            !_showRenameForm) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => setState(() {
                                _showCreateForm = true;
                                _companyNameController.clear();
                              }),
                              icon: const Icon(Icons.add_business),
                              label: const Text('Create New Company'),
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() {
                                _showJoinForm = true;
                                _invitationTokenController.clear();
                              }),
                              icon: const Icon(Icons.group_add),
                              label: const Text('Join Existing Company'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCreateForm() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New Company',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _companyNameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'Company name',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
              ),
              onSubmitted: (_) => _createCompany(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _showCreateForm = false;
                      _companyNameController.clear();
                    }),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _isLoading ? null : _createCompany,
                    child: const Text('Create'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinForm() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Join Company',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _invitationTokenController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Paste invitation token',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
              ),
              onSubmitted: (_) => _acceptInvitation(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _showJoinForm = false;
                      _invitationTokenController.clear();
                    }),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _isLoading ? null : _acceptInvitation,
                    style:
                        FilledButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Join'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRenameForm() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rename "$_renamingCompanyName"',
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _companyNameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'New name',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
              ),
              onSubmitted: (_) => _renameCompany(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _showRenameForm = false;
                      _companyNameController.clear();
                    }),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _isLoading ? null : _renameCompany,
                    child: const Text('Rename'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}