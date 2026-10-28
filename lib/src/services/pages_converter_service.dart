import 'dart:io';
import 'package:flutter/foundation.dart';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Service for converting Apple Pages (.pages) files into Microsoft Excel (.xlsx)
/// format via native AppleScript execution on macOS.
class PagesConverterService {
  @visibleForTesting
  static ProcessRunner processRunner = Process.run;

  @visibleForTesting
  static bool? overrideIsMacOS;

  /// Converts a `.pages` document at [pagesFilePath] into a temporary `.xlsx` file.
  ///
  /// On macOS, executes headless AppleScript via `osascript` to invoke Pages.
  /// Returns the path to the converted `.xlsx` file, or `null` if the conversion
  /// fails or if the current platform is not macOS.
  static Future<String?> convertPagesToXlsx(
    String pagesFilePath, {
    ProcessRunner? runner,
  }) async {
    final isMac = overrideIsMacOS ?? Platform.isMacOS;
    if (!isMac) {
      return null;
    }

    final effectiveRunner = runner ?? processRunner;
    final tempDir = Directory.systemTemp;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath =
        '${tempDir.path}${Platform.pathSeparator}renombrata_temp_pages_export_$timestamp.xlsx';

    final safePagesPath = pagesFilePath.replaceAll('"', r'\"');
    final safeOutputPath = outputPath.replaceAll('"', r'\"');

    final script = '''
tell application "Pages"
    set doc to open POSIX file "$safePagesPath"
    export doc to POSIX file "$safeOutputPath" as Microsoft Excel
    close doc saving no
end tell
''';

    try {
      final result = await effectiveRunner('osascript', ['-e', script]);
      if (result.exitCode != 0) {
        return null;
      }
      if (File(outputPath).existsSync()) {
        return outputPath;
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}
