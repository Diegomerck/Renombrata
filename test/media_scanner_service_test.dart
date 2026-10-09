import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('MediaScannerService', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('media_scanner_test');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('scans and filters files correctly', () {
      File(p.join(tempDir.path, 'C0001.MP4')).createSync();
      File(p.join(tempDir.path, 'C0001.XML')).createSync();
      File(p.join(tempDir.path, 'C0002.mov')).createSync();
      File(p.join(tempDir.path, 'C0003.MXF')).createSync();
      File(p.join(tempDir.path, 'C0004.txt')).createSync(); // Ignored
      
      var subDir = Directory(p.join(tempDir.path, 'CLIP'))..createSync();
      File(p.join(subDir.path, 'C0005.MP4')).createSync(); // Should be found if searchSubdirectories = true

      var files = MediaScannerService.scanDirectory(tempDir.path, searchSubdirectories: true);
      
      expect(files.length, 5); // 4 in root + 1 in subdir
      
      var extensions = files.map((f) => f.extension).toSet();
      expect(extensions, containsAll(['.mp4', '.xml', '.mov', '.mxf']));
      expect(extensions.contains('.txt'), false);

      var hasVideo = files.any((f) => f.isVideo);
      var hasXml = files.any((f) => f.isXml);
      expect(hasVideo, true);
      expect(hasXml, true);
    });
  });
}
