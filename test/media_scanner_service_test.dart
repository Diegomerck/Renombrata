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
    test('recognizes extended video formats (.crm, .lrv) and audio (.wav) correctly', () {
      final crmFile = ScannedFile('A001_C001_1028OC_001.CRM');
      final lrvFile = ScannedFile('GX010042.LRV');
      final wavFile = ScannedFile('AUDIO_T01.WAV');
      final mxfFile = ScannedFile('A001C001.MXF');

      expect(crmFile.isVideo, isTrue, reason: 'CRM should be recognized as video');
      expect(crmFile.isAudio, isFalse);

      expect(lrvFile.isVideo, isTrue, reason: 'LRV should be recognized as video');
      expect(lrvFile.isAudio, isFalse);

      expect(wavFile.isAudio, isTrue, reason: 'WAV should be recognized as audio');
      expect(wavFile.isVideo, isFalse);

      expect(mxfFile.isVideo, isTrue, reason: 'MXF should be recognized as video');
    });

    test('scans directory containing .crm, .lrv, and .wav files', () {
      File(p.join(tempDir.path, 'A001C001.CRM')).createSync();
      File(p.join(tempDir.path, 'GH010012.LRV')).createSync();
      File(p.join(tempDir.path, 'ROLL01.WAV')).createSync();

      final files = MediaScannerService.scanDirectory(tempDir.path);
      expect(files.length, 3);

      final extensions = files.map((f) => f.extension).toSet();
      expect(extensions, containsAll(['.crm', '.lrv', '.wav']));

      expect(files.where((f) => f.isVideo).length, 2);
      expect(files.where((f) => f.isAudio).length, 1);
    });
  });
}
