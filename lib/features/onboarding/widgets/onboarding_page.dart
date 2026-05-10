import 'package:flutter/material.dart';
import '../models/onboarding_step.dart';

class OnboardingPage extends StatelessWidget {
  final OnboardingStep step;
  final bool isLastPage;
  final int currentPage;
  final int totalPages;

  const OnboardingPage({
    super.key,
    required this.step,
    required this.isLastPage,
    required this.currentPage,
    required this.totalPages,
  });

  IconData _getIconData(String assetName) {
    switch (assetName) {
      case 'inventory_2_rounded':
        return Icons.inventory_2_rounded;
      case 'warehouse_rounded':
        return Icons.warehouse_rounded;
      case 'label_rounded':
        return Icons.label_rounded;
      case 'qr_code_scanner':
        return Icons.qr_code_scanner;
      case 'assessment_rounded':
        return Icons.assessment_rounded;
      case 'rocket_launch_rounded':
        return Icons.rocket_launch_rounded;
      default:
        return Icons.check_circle_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final icon = _getIconData(step.iconAsset);

    // Use SingleChildScrollView to prevent overflow on small screens
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Flexible spacing at top
                const SizedBox(height: 16),
                // Icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: isLastPage
                        ? colorScheme.primaryContainer
                        : colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    size: 60,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),
                // Step counter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Step ${currentPage + 1} of $totalPages',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  step.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 14),
                // Highlight text
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    step.highlightText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Description
                Text(
                  step.description,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                    height: 1.5,
                    fontSize: 15,
                  ),
                ),
                if (step.actionHint != null) ...[
                  const SizedBox(height: 20),
                  // Action hint
                  Text(
                    step.actionHint!,
                    style: TextStyle(
                      color: colorScheme.primary.withValues(alpha: 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                // Flexible spacing at bottom
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}