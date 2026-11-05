import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Utility class for discovering companion camera proxies, poster frames / thumbnails,
/// and identifying raw video sensor formats (such as Canon Cinema RAW Light .CRM).
class MediaProxyUtils {
  @visibleForTesting
  static final Map<String, String> testLinkedProxies = {};

  @visibleForTesting
  static final Map<String, File> testPosterFrames = {};

  @visibleForTesting
  static void resetTestMocks() {
    testLinkedProxies.clear();
    testPosterFrames.clear();
  }

  /// Determines if a file path represents a Canon Cinema RAW Light (.CRM) file.
  static bool isCanonRaw(String? filePath) {
    if (filePath == null) return false;
    return p.extension(filePath).toLowerCase() == '.crm';
  }

  /// Determines if an error message represents a raw video codec initialization failure
  /// (e.g. libmpv unable to decode sensor raw mosaic without hardware debayering).
  static bool isRawDecoderError(String? error) {
    if (error == null || error.isEmpty) return false;
    final lower = error.toLowerCase();
    return lower.contains('failed to initialize a decoder for codec') ||
        lower.contains('rawvideo') ||
        lower.contains('crm');
  }

  /// Extracts the embedded 2K JPEG poster frame from a Canon Cinema RAW Light (.CRM) file.
  ///
  /// Checks if already extracted in `.renombrata_cache` or the system temporary directory.
  /// If not cached, opens the `.crm` file in read mode and scans the container header
  /// (first 5MB - 10MB) for JPEG SOI marker `0xFF 0xD8 0xFF` and EOI marker `0xFF 0xD9`.
  /// Extracts the large 2048x1080 JPEG poster frame (offset ~113072, size ~418KB)
  /// and writes it to the cache directory, returning the path to the extracted image.
  static String? extractEmbeddedCrmPosterFrame(String crmPath) {
    try {
      final file = File(crmPath);
      if (!file.existsSync()) return null;

      final dir = p.dirname(crmPath);
      final base = p.basenameWithoutExtension(crmPath);

      // 1. Check local cache
      final localCacheDir = Directory(p.join(dir, '.renombrata_cache'));
      final localPoster = File(
        p.join(localCacheDir.path, '${base}_poster.jpg'),
      );
      if (localPoster.existsSync() && localPoster.lengthSync() > 0) {
        return localPoster.path;
      }
      final localPosterSimple = File(p.join(localCacheDir.path, '$base.jpg'));
      if (localPosterSimple.existsSync() &&
          localPosterSimple.lengthSync() > 0) {
        return localPosterSimple.path;
      }

      // 2. Check system temp cache
      final tempCacheDir = Directory(
        p.join(Directory.systemTemp.path, 'renombrata_cache'),
      );
      final tempPoster = File(p.join(tempCacheDir.path, '${base}_poster.jpg'));
      if (tempPoster.existsSync() && tempPoster.lengthSync() > 0) {
        return tempPoster.path;
      }

      // 3. Scan container header (up to 10MB)
      final fileSize = file.lengthSync();
      final bytesToScan = math.min(fileSize, 10 * 1024 * 1024);
      if (bytesToScan < 4) return null;

      final raf = file.openSync(mode: FileMode.read);
      late Uint8List buffer;
      try {
        buffer = raf.readSync(bytesToScan);
      } finally {
        raf.closeSync();
      }

      int bestStart = -1;
      int bestLength = 0;

      int i = 0;
      while (i < buffer.length - 3) {
        if (buffer[i] == 0xFF &&
            buffer[i + 1] == 0xD8 &&
            buffer[i + 2] == 0xFF) {
          final soi = i;
          int j = soi + 3;
          int foundEoi = -1;
          while (j < buffer.length - 1) {
            if (buffer[j] == 0xFF && buffer[j + 1] == 0xD9) {
              foundEoi = j + 2;
              break;
            }
            j++;
          }

          if (foundEoi > soi) {
            final len = foundEoi - soi;
            if (len > bestLength) {
              bestLength = len;
              bestStart = soi;
            }
            i = foundEoi;
            continue;
          }
        }
        i++;
      }

      if (bestStart >= 0 && bestLength > 0) {
        final jpegBytes = buffer.sublist(bestStart, bestStart + bestLength);
        // Attempt saving to local .renombrata_cache first
        try {
          if (!localCacheDir.existsSync()) {
            localCacheDir.createSync(recursive: true);
          }
          localPoster.writeAsBytesSync(jpegBytes, flush: true);
          return localPoster.path;
        } catch (_) {
          // Fall back to system temporary cache directory
          try {
            if (!tempCacheDir.existsSync()) {
              tempCacheDir.createSync(recursive: true);
            }
            tempPoster.writeAsBytesSync(jpegBytes, flush: true);
            return tempPoster.path;
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error extracting embedded CRM poster frame: $e');
    }
    return null;
  }

  /// Searches disk for an on-set camera proxy matching the master video file.
  ///
  /// Supports Canon Cinema RAW Light (.CRM), GoPro master clips (e.g. GX018226.MP4 matching
  /// GL018226.LRV), and standard video files (.mp4, .mov, .mxf).
  ///
  /// Checks in the same directory and subfolders ('Proxy', 'PROXY', 'Sub', etc.)
  /// for matching basenames with .lrv, .mp4, or .mov extensions and standard proxy suffixes.
  static String? findLinkedProxyPath(String? filePath) {
    if (filePath == null) return null;

    if (testLinkedProxies.containsKey(filePath)) {
      return testLinkedProxies[filePath];
    }

    final ext = p.extension(filePath).toLowerCase();
    // LRV files are proxies themselves; only search for companions if primary video
    if (ext == '.lrv') return null;
    if (!['.crm', '.mp4', '.mov', '.mxf'].contains(ext)) return null;

    try {
      final dir = p.dirname(filePath);
      final base = p.basenameWithoutExtension(filePath);

      final candidateDirs = [
        dir,
        p.join(dir, 'Proxy'),
        p.join(dir, 'PROXY'),
        p.join(dir, 'proxy'),
        p.join(dir, 'Sub'),
        p.join(dir, 'SUB'),
        p.join(dir, 'sub'),
      ];

      final nameVariants = <String>[
        base,
        '${base}_Proxy',
        '${base}_proxy',
        '${base}P',
        '${base}p',
        '${base}_P',
        '${base}_p',
      ];

      // GoPro 6-digit chapter + clip index pairing: e.g. GX018226 -> GL018226
      final goProMatch = RegExp(
        r'^(G[XHP])(\d{6})$',
        caseSensitive: false,
      ).firstMatch(base);
      if (goProMatch != null) {
        nameVariants.add('GL${goProMatch.group(2)}');
        nameVariants.add('gl${goProMatch.group(2)}');
      }

      final extensions = ['.lrv', '.LRV', '.mp4', '.MP4', '.mov', '.MOV'];

      for (final d in candidateDirs) {
        final dirEntity = Directory(d);
        if (!dirEntity.existsSync()) continue;

        try {
          final entries = dirEntity.listSync().whereType<File>();
          for (final entry in entries) {
            final entryName = p.basename(entry.path);
            final entryBase = p.basenameWithoutExtension(entryName);
            final entryExt = p.extension(entryName);
            if (p.equals(d, dir) &&
                entryBase.toUpperCase() == base.toUpperCase() &&
                entryExt.toLowerCase() == ext) {
              continue;
            }
            if (extensions
                .map((x) => x.toLowerCase())
                .contains(entryExt.toLowerCase())) {
              if (nameVariants
                  .map((x) => x.toUpperCase())
                  .contains(entryBase.toUpperCase())) {
                return entry.path;
              }
            }
          }
        } catch (_) {
          for (final name in nameVariants) {
            for (final e in extensions) {
              if (p.equals(d, dir) && name == base && e.toLowerCase() == ext) {
                continue;
              }
              final candidate = p.join(d, '$name$e');
              if (File(candidate).existsSync()) {
                return candidate;
              }
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Searches disk for an existing extracted poster frame, companion image, or cached thumbnail.
  static File? findPosterFrame(String? filePath) {
    if (filePath == null) return null;

    if (testPosterFrames.containsKey(filePath)) {
      return testPosterFrames[filePath];
    }

    try {
      final dir = p.dirname(filePath);
      final base = p.basenameWithoutExtension(filePath);
      final extensions = ['.jpg', '.jpeg', '.png', '.JPG', '.JPEG', '.PNG'];

      // 1. Same directory companion with exact basename
      for (final ext in extensions) {
        final f = File(p.join(dir, '$base$ext'));
        if (f.existsSync()) return f;
      }

      // 2. Suffixes in same folder (_thumb, _poster, _still)
      final suffixes = ['_thumb', '_thumbnail', '_poster', '_still', '_frame'];
      for (final s in suffixes) {
        for (final ext in extensions) {
          final f = File(p.join(dir, '$base$s$ext'));
          if (f.existsSync()) return f;
        }
      }

      // 3. Cache and thumbnail subdirectories
      final cacheDirs = [
        p.join(dir, '.renombrata_cache'),
        p.join(Directory.systemTemp.path, 'renombrata_cache'),
        p.join(dir, 'Thumbnails'),
        p.join(dir, 'thumbnails'),
        p.join(dir, '.thumbnails'),
      ];

      for (final cd in cacheDirs) {
        for (final ext in extensions) {
          final f = File(p.join(cd, '$base$ext'));
          if (f.existsSync()) return f;
          final fPoster = File(p.join(cd, '${base}_poster$ext'));
          if (fPoster.existsSync()) return fPoster;
          final fFull = File(p.join(cd, '${p.basename(filePath)}$ext'));
          if (fFull.existsSync()) return fFull;
        }
      }

      // 4. If Canon RAW and not yet extracted, extract embedded 2K poster frame
      if (isCanonRaw(filePath)) {
        final extractedPath = extractEmbeddedCrmPosterFrame(filePath);
        if (extractedPath != null) {
          final f = File(extractedPath);
          if (f.existsSync()) return f;
        }
      }
    } catch (_) {}

    return null;
  }
}
