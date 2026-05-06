import 'dart:async';
import 'package:flutter/services.dart';

/// Listens for keyboard wedge barcode scanner input.
/// USB barcode scanners typically type characters very fast followed by Enter.
///
/// **IMPORTANT**: This listener is PASSIVE — it returns `false` for all events
/// so that keystrokes still reach active text fields. Use this dialog only
/// when you want to capture barcode input, and dismiss it before typing.
class KeyboardScannerListener {
  final Function(String) onBarcodeScanned;

  static const int _scanThreshold = 50; // milliseconds between keystrokes
  static const int _minBarcodeLength = 4;
  static const int _bufferTimeout = 150; // ms before stale buffer clears

  final List<int> _buffer = [];
  DateTime? _lastKeyTime;
  Timer? _timer;
  bool _isListening = false;

  KeyboardScannerListener({required this.onBarcodeScanned});

  /// Start listening for keyboard input (passive — does NOT consume events).
  void startListening() {
    if (_isListening) return;
    _isListening = true;
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  /// Stop listening for keyboard input.
  void stopListening() {
    if (!_isListening) return;
    _isListening = false;
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _buffer.clear();
    _timer?.cancel();
  }

  /// Always returns `false` — never consumes keyboard events.
  /// This is critical so that normal typing still works while the listener
  /// is active.
  bool _onKeyEvent(KeyEvent event) {
    if (!_isListening) return false;

    // Only process key down events
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();

    // If this is an Enter/Tab key and we have buffered characters
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      if (_buffer.isNotEmpty) {
        final barcode = String.fromCharCodes(_buffer);
        _buffer.clear();
        _timer?.cancel();

        if (barcode.length >= _minBarcodeLength) {
          onBarcodeScanned(barcode);
          return false; // Always passive
        }
      }
      return false;
    }

    // Calculate real elapsed time from last key
    final elapsed = _lastKeyTime != null
        ? now.difference(_lastKeyTime!).inMilliseconds
        : _scanThreshold + 1;

    _lastKeyTime = now;

    // If too much time has passed, it's probably manual typing — flush
    if (elapsed > _scanThreshold && _buffer.isNotEmpty) {
      _buffer.clear();
      _timer?.cancel();
      return false;
    }

    // Only capture characters typical of barcodes
    final char = event.character;
    if (char != null && char.isNotEmpty &&
        (RegExp(r'[a-zA-Z0-9\-\.\$\/\+% ]').hasMatch(char))) {
      _buffer.add(char.codeUnitAt(0));

      // Clear buffer if no terminator arrives within timeout
      _timer?.cancel();
      final captureTime = now;
      _timer = Timer(const Duration(milliseconds: _bufferTimeout), () {
        final elapsedSinceLastKey = DateTime.now().difference(captureTime).inMilliseconds;
        if (elapsedSinceLastKey >= _bufferTimeout) {
          _buffer.clear();
        }
      });

      // IMPORTANT: Always return false — never consume the event
      return false;
    }

    return false;
  }

  void dispose() {
    stopListening();
  }
}