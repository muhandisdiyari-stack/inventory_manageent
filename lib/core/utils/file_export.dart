/// Cross-platform file export utilities.
///
/// Uses conditional exports to provide the correct implementation per platform:
/// - **Web**: Uses `dart:html` to create downloadable blob URLs
/// - **Native**: No-op stub (file saving handled by platform-specific code)
library file_export;

export 'file_export_stub.dart'
    if (dart.library.html) 'file_export_web.dart';