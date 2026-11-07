import 'dart:io';
import 'dart:typed_data';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

/// Service for capturing still frames from video playback and saving them
/// to the user's Desktop directory inside a dedicated project stills folder.
class StillCaptureService {
  /// Resolves the user's Desktop directory path cross-platform.
  /// If [overrideHome] is provided, it is used instead of reading environment variables.
  static String getDesktopDirectoryPath({String? overrideHome}) {
    String? home = overrideHome;
    if (home == null || home.trim().isEmpty) {
      if (Platform.isWindows) {
        home = Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'];
      } else {
        home = Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'];
      }
    }

    final effectiveHome = (home != null && home.trim().isNotEmpty)
        ? home.trim()
        : Directory.current.path;

    return p.join(effectiveHome, 'Desktop');
  }

  /// Strips or replaces characters not allowed in file and directory names
  /// (`\`, `/`, `:`, `*`, `?`, `"`, `<`, `>`, `|`) with `-`.
  static String sanitizeFileName(String name) {
    final sanitized = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized;
  }

  /// Returns the target [Directory] for project stills:
  /// Folder name: `Stills - {projectName} - {date}`.
  ///
  /// Falls back to `'Proyecto Sin Título'` if [projectName] is empty,
  /// and today's date if [date] is empty.
  static Directory getProjectStillsDirectory({
    required String projectName,
    required String date,
    String? baseDesktopPath,
  }) {
    final effectiveProject = projectName.trim().isNotEmpty
        ? projectName.trim()
        : 'Proyecto Sin Título';
    final effectiveDate = date.trim().isNotEmpty
        ? date.trim()
        : DateTime.now().toString().split(' ').first;

    final folderName = sanitizeFileName(
      'Stills - $effectiveProject - $effectiveDate',
    );
    final desktopPath = baseDesktopPath ?? getDesktopDirectoryPath();

    return Directory(p.join(desktopPath, folderName));
  }

  /// Captures a still frame from [player], ensuring [targetDir] exists,
  /// creates a non-colliding unique filename based on [baseName],
  /// and writes the screenshot bytes to disk.
  ///
  /// Returns the created [File], or `null` if screenshot fails or produces no data.
  static Future<File?> captureStill({
    required Player player,
    required String baseName,
    required Directory targetDir,
    String format = 'image/jpeg',
  }) async {
    try {
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }

      final ext = format.toLowerCase().contains('png') ? '.png' : '.jpg';
      final cleanBase = sanitizeFileName(p.basenameWithoutExtension(baseName));
      final effectiveBase = cleanBase.isNotEmpty ? cleanBase : 'still';

      var candidateFile = File(p.join(targetDir.path, '$effectiveBase$ext'));
      var counter = 1;
      while (candidateFile.existsSync()) {
        candidateFile = File(
          p.join(targetDir.path, '$effectiveBase ($counter)$ext'),
        );
        counter++;
      }

      final Uint8List? bytes = await player.screenshot(format: format);
      if (bytes == null || bytes.isEmpty) {
        return null;
      }

      candidateFile.writeAsBytesSync(bytes, flush: false);
      return candidateFile;
    } catch (_) {
      return null;
    }
  }
}
