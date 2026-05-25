import 'package:flutter/material.dart';

class EmptyStateWidget extends StatelessWidget {
  final VoidCallback? onCreateInventory;

  const EmptyStateWidget({
    super.key,
    this.onCreateInventory,
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
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Icon(
                      Icons.inventory_2_outlined,
                      size: 60,
                      color: Theme.of(context)
                          .colorScheme
                          .primary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'No Inventories Yet',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    onCreateInventory != null
                        ? 'Create your first inventory to start managing items'
                        : 'Pull down to refresh or connect to the internet',
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  if (onCreateInventory != null) ...[
                    const SizedBox(height: 40),
                    SizedBox(
                      width: 220,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: onCreateInventory,
                        icon: const Icon(Icons.add_rounded,
                            size: 22),
                        label: const Text(
                          'Create Inventory',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Pull down to refresh',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4),
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}