import 'dart:io';
import 'package:path/path.dart' as p;

class ScannedFile {
  final String path;
  final String basename;
  final String extension;
  final bool isVideo;
  final bool isXml;

  ScannedFile(this.path)
      : basename = p.basename(path),
        extension = p.extension(path).toLowerCase(),
        isVideo = ['.mp4', '.mov', '.mxf'].contains(p.extension(path).toLowerCase()),
        isXml = p.extension(path).toLowerCase() == '.xml';
}

class MediaScannerService {
  static List<ScannedFile> scanDirectory(String dirPath, {bool searchSubdirectories = true}) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];

    List<File> allFiles = [];
    final entities = dir.listSync(recursive: false, followLinks: false);
    
    for (var entity in entities) {
      if (entity is File) {
        allFiles.add(entity);
      } else if (entity is Directory && searchSubdirectories) {
        // 1-level depth
        final subEntities = entity.listSync(recursive: false, followLinks: false);
        allFiles.addAll(subEntities.whereType<File>());
      }
    }

    return allFiles
        .map((f) => ScannedFile(f.path))
        .where((f) => f.isVideo || f.isXml)
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
