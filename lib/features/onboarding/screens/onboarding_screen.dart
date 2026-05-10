import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/onboarding_step.dart';
import '../widgets/onboarding_page.dart';
import '../../inventory_selection/providers/inventory_list_provider.dart';
import '../../inventory_management/services/inventory_service.dart';
import '../../inventory_selection/screens/inventory_selection_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isCreatingDemo = false;

  final List<OnboardingStep> _steps = const [
    OnboardingStep(
      title: 'Welcome to Inventory Pro!',
      description:
          'Your all-in-one solution for managing inventory across multiple locations. Let\'s get you started with a quick tour.',
      iconAsset: 'inventory_2_rounded',
      highlightText: 'Track everything in one place',
      actionHint: 'Swipe to continue →',
    ),
    OnboardingStep(
      title: 'Create Inventories',
      description:
          'Organize your items by creating separate inventories for different locations like warehouses, stores, or departments.',
      iconAsset: 'warehouse_rounded',
      highlightText: 'Multiple locations, one app',
      actionHint: 'Swipe to continue →',
    ),
    OnboardingStep(
      title: 'Add Labels & Items',
      description:
          'Within each inventory, create labels (categories) and add items with detailed information like barcodes, quantities, and expiry dates.',
      iconAsset: 'label_rounded',
      highlightText: 'Organize with labels',
      actionHint: 'Swipe to continue →',
    ),
    OnboardingStep(
      title: 'Scan Barcodes',
      description:
          'Use your camera, USB scanner, or upload images to quickly add items by scanning their barcodes. Supports all major barcode formats.',
      iconAsset: 'qr_code_scanner',
      highlightText: 'Fast data entry',
      actionHint: 'Swipe to continue →',
    ),
    OnboardingStep(
      title: 'Generate Reports',
      description:
          'Export your inventory data as CSV files with customizable fields. Filter by expiry status and share reports easily.',
      iconAsset: 'assessment_rounded',
      highlightText: 'Export & share data',
      actionHint: 'Swipe to continue →',
    ),
    OnboardingStep(
      title: 'Ready to Start?',
      description:
          'We\'ll create a sample inventory with demo items so you can explore the app right away. You can delete it anytime!',
      iconAsset: 'rocket_launch_rounded',
      highlightText: 'Get started instantly',
      actionHint: 'Tap the button below ↓',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _createDemoInventory() async {
    if (_isCreatingDemo) return;

    setState(() => _isCreatingDemo = true);

    try {
      final listProvider = context.read<InventoryListProvider>();
      final service = context.read<InventoryService>();

      // Create a demo inventory
      final demoId = await listProvider.createInventory('My First Inventory', service);

      // Select it
      listProvider.selectInventory(demoId);

      // Navigate to main screen
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const InventorySelectionScreen(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating demo: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isCreatingDemo = false);
      }
    }
  }

  void _skipOnboarding() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const InventorySelectionScreen(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.primaryContainer.withValues(alpha: 0.3),
              colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: _currentPage < _steps.length - 1
                        ? _skipOnboarding
                        : null,
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              // Pages
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (page) {
                    setState(() => _currentPage = page);
                  },
                  itemCount: _steps.length,
                  itemBuilder: (context, index) {
                    return OnboardingPage(
                      step: _steps[index],
                      isLastPage: index == _steps.length - 1,
                      currentPage: index,
                      totalPages: _steps.length,
                    );
                  },
                ),
              ),
              // Bottom section
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Page indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _steps.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? colorScheme.primary
                                : colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Action button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: _currentPage == _steps.length - 1
                          ? FilledButton.icon(
                              onPressed: _isCreatingDemo ? null : _createDemoInventory,
                              icon: _isCreatingDemo
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.rocket_launch_rounded),
                              label: Text(
                                _isCreatingDemo
                                    ? 'Creating demo...'
                                    : 'Get Started with Demo',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            )
                          : FilledButton(
                              onPressed: () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOut,
                                );
                              },
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}