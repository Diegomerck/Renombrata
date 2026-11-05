import 'dart:io';
import 'package:path/path.dart' as p;

class ScannedFile {
  final String path;
  final String basename;
  final String extension;
  final bool isVideo;
  final bool isPrimaryVideo;
  final bool isXml;
  final bool isAudio;
  final bool isCompanion;

  ScannedFile(this.path)
    : basename = p.basename(path),
      extension = p.extension(path).toLowerCase(),
      isVideo = [
        '.mp4',
        '.mov',
        '.mxf',
        '.crm',
        '.lrv',
      ].contains(p.extension(path).toLowerCase()),
      isPrimaryVideo = [
        '.mp4',
        '.mov',
        '.mxf',
        '.crm',
      ].contains(p.extension(path).toLowerCase()),
      isXml = p.extension(path).toLowerCase() == '.xml',
      isAudio = [
        '.wav',
        '.aif',
        '.aiff',
        '.mp3',
        '.m4a',
        '.aac',
      ].contains(p.extension(path).toLowerCase()),
      isCompanion = [
        '.lrv',
        '.thm',
        '.xml',
        '.bim',
        '.srt',
      ].contains(p.extension(path).toLowerCase());
}

class MediaScannerService {
  static List<ScannedFile> scanDirectory(
    String dirPath, {
    bool searchSubdirectories = true,
  }) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];

    List<File> allFiles = [];
    try {
      final entities = dir.listSync(
        recursive: searchSubdirectories,
        followLinks: false,
      );
      allFiles.addAll(entities.whereType<File>());
    } catch (_) {
      try {
        final entities = dir.listSync(recursive: false, followLinks: false);
        allFiles.addAll(entities.whereType<File>());
      } catch (_) {}
    }

    return allFiles
        .map((f) => ScannedFile(f.path))
        .where((f) => f.isVideo || f.isXml || f.isAudio || f.isCompanion)
        .toList();
  }

  /// Detects whether any scanned files are Sony M01 metadata XML sidecars
  /// paired with video clips.
  static bool hasSonyM01Files(List<ScannedFile> files) {
    final videoStems = files
        .where((f) => f.isVideo)
        .map((f) => p.basenameWithoutExtension(f.basename).toUpperCase())
        .toSet();
    for (final file in files.where((f) => f.isXml)) {
      final xmlStem = p.basenameWithoutExtension(file.basename).toUpperCase();
      if (xmlStem.endsWith('M01') && xmlStem.length > 3) {
        final candidateVideo = xmlStem.substring(0, xmlStem.length - 3);
        if (videoStems.contains(candidateVideo)) {
          return true;
        }
      }
    }
    return false;
  }
}
