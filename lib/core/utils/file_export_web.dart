// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// Web-specific download using HTML anchor element with blob URL.
///
/// Creates a temporary blob URL from the file bytes, attaches it to an
/// invisible anchor element with the [fileName] as the download attribute,
/// programmatically clicks it to trigger the browser's download dialog,
/// then revokes the blob URL to free memory.
void downloadFileWeb(List<int> bytes, String fileName, String mimeType) {
  // Create a Blob from the bytes with the specified MIME type
  final blob = html.Blob([bytes], mimeType);

  // Create an object URL from the blob
  final url = html.Url.createObjectUrlFromBlob(blob);

  // Create a hidden anchor element
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..style.display = 'none';

  // Add to document body, click it, then remove it
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  // Revoke the object URL to free memory
  html.Url.revokeObjectUrl(url);
}