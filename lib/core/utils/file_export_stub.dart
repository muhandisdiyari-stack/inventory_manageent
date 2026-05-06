/// Stub for non-web platforms.
///
/// This function is a no-op on native platforms because the actual file
/// saving is handled by platform-specific implementations in CsvService.
void downloadFileWeb(List<int> bytes, String fileName, String mimeType) {
  // No-op on native platforms
  // File saving is handled by file_picker and dart:io in CsvService.saveFile()
}