import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/services/barcode_scanner_service.dart';
import 'barcode_scanner_sheet.dart';
import 'desktop_camera_scanner_sheet.dart';
import 'image_barcode_scanner.dart';
import 'keyboard_scanner_listener.dart';

/// Central dispatcher that picks the right barcode-scanning UI for the
/// current platform and the available hardware.
class UnifiedBarcodeScanner {
  /// Shows the appropriate barcode scanner for the current platform.
  ///
  /// When multiple scanning methods are supported the user is first
  /// presented with a picker sheet; otherwise the single available method
  /// is launched directly.
  static Future<void> showScanner(
    BuildContext context, {
    required Function(String) onBarcodeScanned,
  }) async {
    final supportedTypes = BarcodeScannerService.supportedTypes;

    if (supportedTypes.length == 1) {
      // Only one option — use it directly
      _openScanner(context, supportedTypes.first, onBarcodeScanned);
      return;
    }

    // Multiple options — show picker
    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => _ScannerOptionSheet(
          supportedTypes: supportedTypes,
          onSelect: (type) {
            Navigator.pop(ctx);
            _openScanner(context, type, onBarcodeScanned);
          },
        ),
      );
    }
  }

  static void _openScanner(
    BuildContext context,
    BarcodeScannerType type,
    Function(String) onBarcodeScanned,
  ) {
    switch (type) {
      case BarcodeScannerType.camera:
        // Mobile platforms use mobile_scanner; desktop uses the camera +
        // ML Kit combination. Try mobile first; fall back to desktop.
        if (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS) {
          try {
            BarcodeScannerSheet.show(context, onBarcodeScanned: onBarcodeScanned);
          } catch (_) {
            DesktopCameraScannerSheet.show(context, onBarcodeScanned: onBarcodeScanned);
          }
        } else {
          DesktopCameraScannerSheet.show(context, onBarcodeScanned: onBarcodeScanned);
        }
        break;

      case BarcodeScannerType.image:
        ImageBarcodeScanner.pickAndScan(context, onBarcodeScanned: onBarcodeScanned);
        break;

      case BarcodeScannerType.keyboard:
        _startKeyboardScanner(context, onBarcodeScanned);
        break;

      case BarcodeScannerType.unsupported:
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Barcode scanning is not supported on this device'),
            ),
          );
        }
        break;
    }
  }

  /// Opens a dialog that listens for keyboard-wedge barcode input.
  ///
  /// The listener is **passive** — it never consumes keystrokes, so the user
  /// can still type in text fields while the dialog is open (though typing
  /// while scanning is discouraged).
  static void _startKeyboardScanner(
    BuildContext context,
    Function(String) onBarcodeScanned,
  ) {
    // Hold a nullable reference so the closure can refer to the listener
    // before it is fully initialised.
    KeyboardScannerListener? listenerHolder;

    listenerHolder = KeyboardScannerListener(
      onBarcodeScanned: (barcode) {
        listenerHolder?.stopListening();
        onBarcodeScanned(barcode);
      },
    );

    // Capture in a final local so the dialog can safely close it
    final listener = listenerHolder;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _KeyboardScannerDialog(
        onCancel: () {
          listener.stopListening();
          Navigator.pop(ctx);
        },
      ),
    );

    listener.startListening();
  }
}

// ─── Scanner Option Picker ────────────────────────────────────────────────

class _ScannerOptionSheet extends StatelessWidget {
  final List<BarcodeScannerType> supportedTypes;
  final Function(BarcodeScannerType) onSelect;

  const _ScannerOptionSheet({
    required this.supportedTypes,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Scan Barcode',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose scanning method',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          if (supportedTypes.contains(BarcodeScannerType.camera))
            _buildOption(
              context,
              icon: Icons.camera_alt,
              title: 'Camera Scanner',
              subtitle: 'Use device camera to scan barcode',
              onTap: () => onSelect(BarcodeScannerType.camera),
            ),

          if (supportedTypes.contains(BarcodeScannerType.keyboard))
            _buildOption(
              context,
              icon: Icons.keyboard,
              title: 'USB Barcode Scanner',
              subtitle: 'Use connected barcode scanner (keyboard wedge)',
              onTap: () => onSelect(BarcodeScannerType.keyboard),
            ),

          if (supportedTypes.contains(BarcodeScannerType.image))
            _buildOption(
              context,
              icon: Icons.image,
              title: 'Scan from Image',
              subtitle: 'Pick an image containing a barcode',
              onTap: () => onSelect(BarcodeScannerType.image),
            ),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ─── Keyboard Scanner Dialog ──────────────────────────────────────────────

class _KeyboardScannerDialog extends StatelessWidget {
  final VoidCallback onCancel;

  const _KeyboardScannerDialog({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.qr_code_scanner,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Waiting for Barcode Scan',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please scan a barcode using your connected scanner.\n'
              'The barcode will be automatically detected.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Make sure the cursor is NOT in any text field',
                      style: TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(40),
                ),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}