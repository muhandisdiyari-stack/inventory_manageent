import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/onboarding_step.dart';
import '../widgets/onboarding_page.dart';
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
  bool _isRequestingPermissions = false;

  final List<OnboardingStep> _steps = const [
    OnboardingStep(
      title: 'Welcome to Inventory Pro!',
      description: 'Your all-in-one solution for managing inventory across multiple locations.',
      iconAsset: 'inventory_2_rounded',
      highlightText: 'Track everything in one place',
      actionHint: 'Swipe to continue →',
    ),
    OnboardingStep(
      title: 'Create Inventories',
      description: 'Organize your items by creating separate inventories for different locations.',
      iconAsset: 'warehouse_rounded',
      highlightText: 'Multiple locations, one app',
      actionHint: 'Swipe to continue →',
    ),
    OnboardingStep(
      title: 'Add Labels & Items',
      description: 'Create labels and add items with barcodes, quantities, and expiry dates.',
      iconAsset: 'label_rounded',
      highlightText: 'Organize with labels',
      actionHint: 'Swipe to continue →',
    ),
    OnboardingStep(
      title: 'Scan Barcodes',
      description: 'Use camera, USB scanner, or images to quickly add items.',
      iconAsset: 'qr_code_scanner',
      highlightText: 'Fast data entry',
      actionHint: 'Swipe to continue →',
    ),
    OnboardingStep(
      title: 'Generate Reports',
      description: 'Export inventory data as CSV files with customizable fields.',
      iconAsset: 'assessment_rounded',
      highlightText: 'Export & share data',
      actionHint: 'Swipe to continue →',
    ),
    OnboardingStep(
      title: 'App Permissions',
      description: 'Camera for barcode scanning, storage for saving reports.',
      iconAsset: 'security_rounded',
      highlightText: 'We respect your privacy',
      actionHint: 'Tap below to grant permissions ↓',
    ),
    OnboardingStep(
      title: 'Ready to Start!',
      description: 'You\'re all set! Start managing your inventory now.',
      iconAsset: 'rocket_launch_rounded',
      highlightText: 'Let\'s get started!',
      actionHint: 'Tap below to begin ↓',
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

    setState(() => _isRequestingPermissions = true);

    try {
      final permissions = <Permission>[];
      permissions.add(Permission.camera);

      if (!kIsWeb) {
        try { permissions.add(Permission.storage); } catch (_) {}
      }

      for (final permission in permissions) {
        try {
          final status = await permission.status;
          if (!status.isGranted) await permission.request();
        } catch (_) {}
      }
    } catch (_) {}

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Permissions updated'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    setState(() => _isRequestingPermissions = false);
  }

  void _finishOnboarding() async {
    await _markOnboardingComplete();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const InventorySelectionScreen()),
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
    final colorScheme = Theme.of(context).colorScheme;
    final isPermissionsPage = _currentPage == _steps.length - 2;
    final isLastPage = _currentPage == _steps.length - 1;

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
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: _finishOnboarding,
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
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  itemCount: _steps.length,
                  itemBuilder: (context, index) => OnboardingPage(
                    step: _steps[index],
                    isLastPage: isLastPage,
                    currentPage: index,
                    totalPages: _steps.length,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
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
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: isPermissionsPage
                          ? FilledButton.icon(
                              onPressed: _isRequestingPermissions ? null : _requestPermissions,
                              icon: _isRequestingPermissions
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.security_rounded),
                              label: Text(
                                _isRequestingPermissions ? 'Requesting...' : 'Grant Permissions',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            )
                          : isLastPage
                              ? FilledButton.icon(
                                  onPressed: _finishOnboarding,
                                  icon: const Icon(Icons.rocket_launch_rounded),
                                  label: const Text('Get Started', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                )
                              : FilledButton(
                                  onPressed: _nextPage,
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  child: const Text('Continue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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