import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/auth_service.dart';
import '../../inventory_selection/screens/inventory_selection_screen.dart';
import '../../auth/providers/auth_provider.dart';

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
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final authService = context.read<AuthService>();
      final companies = await authService.getUserCompanies();
      if (!mounted) return;
      setState(() { _userCompanies = companies; _isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _userCompanies = []; _isLoading = false; _errorMessage = 'Failed to load companies.'; });
    }
  }

  Future<void> _createCompany() async {
    final name = _companyNameController.text.trim();
    if (name.isEmpty) return;

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final authService = context.read<AuthService>();
      final result = await authService.createCompany(name);
      if (!mounted) return;

      if (result != null) {
        await _loadUserCompanies();
        setState(() { _showCreateForm = false; _companyNameController.clear(); });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Company "$name" created!'), behavior: SnackBarBehavior.floating));
        }
      } else {
        setState(() { _isLoading = false; _errorMessage = 'Failed to create company'; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = 'Error: ${e.toString()}'; });
    }
  }

  Future<void> _deleteCompany(String companyId, String companyName) async {
    final company = _userCompanies.firstWhere((c) => c['id'] == companyId, orElse: () => <String, dynamic>{});
    final role = company['role'] ?? 'staff';
    if (role != 'owner') {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only owners can delete.'), backgroundColor: Colors.orange));
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Company'),
        content: Text('Delete "$companyName" and ALL its data?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final authService = context.read<AuthService>();
      await authService.deleteCompany(companyId);
      if (!mounted) return;
      await _loadUserCompanies();
      messenger.showSnackBar(SnackBar(content: Text('"$companyName" deleted')));
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = 'Error: ${e.toString()}'; });
    }
  }

  Future<void> _leaveCompany(String companyId, String companyName) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Company'),
        content: Text('Leave "$companyName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave', style: TextStyle(color: Colors.orange))),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final authService = context.read<AuthService>();
      await authService.leaveCompany(companyId);
      if (!mounted) return;
      await _loadUserCompanies();
      messenger.showSnackBar(SnackBar(content: Text('Left "$companyName"')));
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = 'Error: ${e.toString()}'; });
    }
  }

Future<void> _acceptInvitation() async {
    final token = _invitationTokenController.text.trim();
    if (token.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final authService = context.read<AuthService>();
      final result = await authService.acceptInvitation(token);
      
      if (!mounted) return;

      if (result != null && result['success'] == true) {
        await _loadUserCompanies();
        setState(() { _showJoinForm = false; _invitationTokenController.clear(); });
        messenger.showSnackBar(const SnackBar(content: Text('Company joined successfully!')));
      } else {
        final message = result?['message']?.toString() ?? 'Invalid or expired invitation token';
        setState(() { _isLoading = false; _errorMessage = message; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = 'Error: ${e.toString()}'; });
    }
  }

  // FIXED: Don't call selectInventory or initializeForInventory
  void _openCompany(String companyId, String companyName) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InventorySelectionScreen()),
    );
  }

  void _signOut() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Companies'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign Out', onPressed: _signOut),
        ],
      ),
      body: _isLoading && _userCompanies.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUserCompanies,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                  ),
                ..._userCompanies.map((c) {
                  final name = c['name']?.toString() ?? '';
                  final role = (c['role']?.toString() ?? 'staff').toUpperCase();
                  final isOwner = role == 'OWNER';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: colorScheme.primaryContainer, child: Icon(Icons.business, color: colorScheme.primary)),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('Role: $role'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'delete' && isOwner) _deleteCompany(c['id']?.toString() ?? '', name);
                          if (action == 'leave' && !isOwner) _leaveCompany(c['id']?.toString() ?? '', name);
                        },
                        itemBuilder: (ctx) => [
                          if (isOwner) const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                          if (!isOwner) const PopupMenuItem(value: 'leave', child: Text('Leave Company')),
                        ],
                      ),
                      onTap: () => _openCompany(c['id']?.toString() ?? '', name),
                    ),
                  );
                }),
                if (_userCompanies.isEmpty && !_showCreateForm && !_showJoinForm)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      Icon(Icons.business_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No companies yet', style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Create or join a company', style: TextStyle(color: Colors.grey[500])),
                    ]),
                  ),
                if (_showCreateForm)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('New Company', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        const SizedBox(height: 12),
                        TextField(controller: _companyNameController, autofocus: true, textCapitalization: TextCapitalization.words, decoration: InputDecoration(hintText: 'Company name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: OutlinedButton(onPressed: () => setState(() { _showCreateForm = false; _companyNameController.clear(); }), child: const Text('Cancel'))),
                          const SizedBox(width: 8),
                          Expanded(child: FilledButton(onPressed: _createCompany, child: const Text('Create'))),
                        ]),
                      ]),
                    ),
                  ),
                if (_showJoinForm)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Join Company', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        const SizedBox(height: 12),
                        TextField(controller: _invitationTokenController, autofocus: true, decoration: InputDecoration(hintText: 'Paste invitation token', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true)),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: OutlinedButton(onPressed: () => setState(() { _showJoinForm = false; _invitationTokenController.clear(); }), child: const Text('Cancel'))),
                          const SizedBox(width: 8),
                          Expanded(child: FilledButton(onPressed: _acceptInvitation, style: FilledButton.styleFrom(backgroundColor: Colors.green), child: const Text('Join'))),
                        ]),
                      ]),
                    ),
                  ),
                if (!_showCreateForm && !_showJoinForm) ...[
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => setState(() { _showCreateForm = true; _companyNameController.clear(); }), icon: const Icon(Icons.add_business), label: const Text('Create New Company'), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)))),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => setState(() { _showJoinForm = true; _invitationTokenController.clear(); }), icon: const Icon(Icons.group_add), label: const Text('Join Existing Company'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)))),
                ],
                const SizedBox(height: 32),
              ]),
            ),
    );
  }
}