/// Model representing a single step in the onboarding tutorial.
class OnboardingStep {
  final String title;
  final String description;
  final String iconAsset; // Material icon name (string identifier)
  final String highlightText;
  final String? actionHint;

  const OnboardingStep({
    required this.title,
    required this.description,
    required this.iconAsset,
    required this.highlightText,
    this.actionHint,
  });
}