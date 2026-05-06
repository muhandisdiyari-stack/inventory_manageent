import 'package:flutter/material.dart';

class EmptyStateWidget extends StatelessWidget {
  final VoidCallback onCreateInventory;

  const EmptyStateWidget({
    super.key,
    required this.onCreateInventory,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildIcon(context),
                  const SizedBox(height: 32),
                  _buildTitle(context),
                  const SizedBox(height: 12),
                  _buildDescription(context),
                  const SizedBox(height: 40),
                  _buildCreateButton(context),
                  const SizedBox(height: 16),
                  _buildRefreshHint(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIcon(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        // Fixed: Replaced withOpacity with withValues
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        size: 60,
        // Fixed: Replaced withOpacity with withValues
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    return Text(
      'Welcome to Inventory Pro',
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildDescription(BuildContext context) {
    return Text(
      'Create your first inventory to start managing your items efficiently',
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            // Fixed: Replaced withOpacity with withValues
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.6),
          ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildCreateButton(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 56,
      child: FilledButton.icon(
        onPressed: onCreateInventory,
        icon: const Icon(Icons.add_rounded, size: 22),
        label: const Text(
          'Create Inventory',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshHint(BuildContext context) {
    return Text(
      'Pull down to refresh',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            // Fixed: Replaced withOpacity with withValues
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.4),
          ),
    );
  }
}