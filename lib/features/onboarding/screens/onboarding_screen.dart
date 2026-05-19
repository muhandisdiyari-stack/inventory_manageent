import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/onboarding_step.dart';
import '../widgets/onboarding_page.dart';
import '../../inventory_selection/providers/inventory_list_provider.dart';
import '../../inventory_management/services/inventory_service.dart';
import '../../inventory_selection/screens/inventory_selection_screen.dart';
import '../../../core/constants/app_constants.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isCreatingDemo = false;
  bool _isRequestingPermissions = false;
  String? _errorMessage;

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
      title: 'App Permissions',
      description:
          'To provide the best experience, we need a few permissions. Camera for barcode scanning, storage for saving reports, and notifications for alerts.',
      iconAsset: 'security_rounded',
      highlightText: 'We respect your privacy',
      actionHint: 'Tap the button below to grant permissions ↓',
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

  Future<void> _markOnboardingComplete() async {
    try {
      final appSettings = Hive.box(AppConstants.appSettingsBox);
      await appSettings.put(AppConstants.onboardingCompletedKey, true);
    } catch (e) {
      debugPrint('Error marking onboarding complete: $e');
    }
  }

  Future<void> _requestPermissions() async {
    if (_isRequestingPermissions) return;

    setState(() {
      _isRequestingPermissions = true;
      _errorMessage = null;
    });

    try {
      final permissions = <Permission>[];

      // Camera works on all platforms
      permissions.add(Permission.camera);

      // Storage only on native platforms (not web)
      if (!kIsWeb) {
        try {
          permissions.add(Permission.storage);
        } catch (_) {}
        
        try {
          permissions.add(Permission.manageExternalStorage);
        } catch (_) {}
      }

      // Notifications — only on platforms that support it
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          permissions.add(Permission.notification);
        } catch (_) {}
      }

      // Request each permission safely
      for (final permission in permissions) {
        try {
          final status = await permission.status;
          if (!status.isGranted) {
            await permission.request();
          }
        } catch (e) {
          debugPrint('Permission $permission not supported: $e');
        }
      }
    } catch (e) {
      debugPrint('Permission request error: $e');
    }

    if (!mounted) return;

    // Build status messages
    final messages = <String>[];

    try {
      final cameraStatus = await Permission.camera.status;
      messages.add(
        cameraStatus.isGranted
            ? '✓ Camera - for barcode scanning'
            : '✗ Camera - denied',
      );
    } catch (_) {
      messages.add('✓ Camera - web supported');
    }

    if (!kIsWeb) {
      try {
        final storageStatus = await Permission.storage.status;
        final manageStatus = await Permission.manageExternalStorage.status;
        messages.add(
          (storageStatus.isGranted || manageStatus.isGranted)
              ? '✓ Storage - for saving reports'
              : '✗ Storage - denied',
        );
      } catch (_) {}
    } else {
      messages.add('✓ Storage - web downloads supported');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: messages
              .map((m) => Text(m, style: const TextStyle(fontSize: 13)))
              .toList(),
        ),
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );

    setState(() => _isRequestingPermissions = false);
  }

  Future<void> _createDemoInventory() async {
    if (_isCreatingDemo) return;

    setState(() {
      _isCreatingDemo = true;
      _errorMessage = null;
    });

    try {
      final listProvider = context.read<InventoryListProvider>();
      final service = context.read<InventoryService>();

      // Create a demo inventory
      final demoId = await listProvider.createInventory('My First Inventory', service);

      if (!mounted) return;

      // Select it
      listProvider.selectInventory(demoId);

      // Mark onboarding as complete
      await _markOnboardingComplete();

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
      if (!mounted) return;

      setState(() {
        _isCreatingDemo = false;
        _errorMessage = 'Error creating demo: ${e.toString()}';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating demo: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _skipOnboarding() async {
    await _markOnboardingComplete();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const InventorySelectionScreen(),
      ),
      (route) => false,
    );
  }

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Container(
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
              
              // Error message
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Pages
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (page) {
                    setState(() {
                      _currentPage = page;
                      _errorMessage = null;
                    });
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
                      child: _buildActionButton(),
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

  Widget _buildActionButton() {
    final isPermissionsPage = _currentPage == _steps.length - 2;
    final isLastPage = _currentPage == _steps.length - 1;

    if (isPermissionsPage) {
      return FilledButton.icon(
        onPressed: _isRequestingPermissions ? null : _requestPermissions,
        icon: _isRequestingPermissions
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.security_rounded),
        label: Text(
          _isRequestingPermissions ? 'Requesting...' : 'Grant Permissions',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }

    if (isLastPage) {
      return FilledButton.icon(
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
          _isCreatingDemo ? 'Creating demo...' : 'Get Started with Demo',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }

    return FilledButton(
      onPressed: _nextPage,
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: const Text(
        'Continue',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }
}