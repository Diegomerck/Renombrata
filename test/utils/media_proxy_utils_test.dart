import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/utils/media_proxy_utils.dart';

void main() {
  group('MediaProxyUtils Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('media_proxy_test_');
      MediaProxyUtils.resetTestMocks();
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
      MediaProxyUtils.resetTestMocks();
    });

    test('isCanonRaw correctly detects .crm and .CRM', () {
      expect(MediaProxyUtils.isCanonRaw('/path/to/clip.crm'), isTrue);
      expect(MediaProxyUtils.isCanonRaw('/path/to/clip.CRM'), isTrue);
      expect(MediaProxyUtils.isCanonRaw('/path/to/clip.mp4'), isFalse);
      expect(MediaProxyUtils.isCanonRaw(null), isFalse);
    });

    test('isRawDecoderError identifies codec decoder failures', () {
      expect(
        MediaProxyUtils.isRawDecoderError(
          'Failed to initialize a decoder for codec: rawvideo',
        ),
        isTrue,
      );
      expect(
        MediaProxyUtils.isRawDecoderError('Decoder init failed: crm'),
        isTrue,
      );
      expect(
        MediaProxyUtils.isRawDecoderError('Failed to recognize file format.'),
        isFalse,
      );
      expect(MediaProxyUtils.isRawDecoderError(null), isFalse);
    });

    test('findLinkedProxyPath finds companion proxy in same directory', () {
      final crmPath = p.join(tempDir.path, 'A001C001.CRM');
      final proxyMp4 = p.join(tempDir.path, 'A001C001_Proxy.mp4');

      File(crmPath).createSync();
      File(proxyMp4).createSync();

      final found = MediaProxyUtils.findLinkedProxyPath(crmPath);
      expect(found, equals(proxyMp4));
    });

    test('findLinkedProxyPath finds proxy in Proxy/ subfolder with suffix', () {
      final crmPath = p.join(tempDir.path, 'A002C001.CRM');
      final proxyDir = Directory(p.join(tempDir.path, 'Proxy'))..createSync();
      final proxyFile = p.join(proxyDir.path, 'A002C001P.mp4');

      File(crmPath).createSync();
      File(proxyFile).createSync();

      final found = MediaProxyUtils.findLinkedProxyPath(crmPath);
      expect(found, equals(proxyFile));
    });

    test('findLinkedProxyPath returns null when no proxy exists', () {
      final crmPath = p.join(tempDir.path, 'A003C001.CRM');
      File(crmPath).createSync();

      final found = MediaProxyUtils.findLinkedProxyPath(crmPath);
      expect(found, isNull);
    });

    test('findPosterFrame finds companion image in same directory', () {
      final crmPath = p.join(tempDir.path, 'A001C001.CRM');
      final jpgPath = p.join(tempDir.path, 'A001C001.jpg');

      File(crmPath).createSync();
      File(jpgPath).createSync();

      final poster = MediaProxyUtils.findPosterFrame(crmPath);
      expect(poster, isNotNull);
      expect(poster!.path, equals(jpgPath));
    });

    test('findPosterFrame finds cached thumbnail in .renombrata_cache', () {
      final crmPath = p.join(tempDir.path, 'A002C001.CRM');
      final cacheDir = Directory(p.join(tempDir.path, '.renombrata_cache'))
        ..createSync();
      final thumbPath = p.join(cacheDir.path, 'A002C001.png');

      File(crmPath).createSync();
      File(thumbPath).createSync();

      final poster = MediaProxyUtils.findPosterFrame(crmPath);
      expect(poster, isNotNull);
      expect(poster!.path, equals(thumbPath));
    });

    test(
      'extractEmbeddedCrmPosterFrame scans CRM header and extracts large 2K poster frame',
      () {
        final crmPath = p.join(tempDir.path, 'A001_C001.CRM');
        final crmFile = File(crmPath);

        // Create synthetic CRM container with a small thumbnail and large 2K poster frame
        final containerBytes = <int>[];
        // 1. Initial container header bytes (e.g. 500 bytes)
        containerBytes.addAll(List.filled(500, 0x00));

        // 2. Small thumbnail (e.g. 40 bytes)
        containerBytes.addAll([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
        containerBytes.addAll(List.filled(30, 0xAA));
        containerBytes.addAll([0xFF, 0xD9]);

        // 3. Container intermediate metadata
        containerBytes.addAll(List.filled(1000, 0x11));

        // 4. Large 2K poster frame (e.g. 3000 bytes)
        final posterBytes = <int>[0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x20];
        posterBytes.addAll(List.filled(3000, 0xBB));
        posterBytes.addAll([0xFF, 0xD9]);
        containerBytes.addAll(posterBytes);

        // 5. Trailing payload bytes
        containerBytes.addAll(List.filled(2000, 0x22));

        crmFile.writeAsBytesSync(containerBytes);

        final extractedPath = MediaProxyUtils.extractEmbeddedCrmPosterFrame(
          crmPath,
        );
        expect(extractedPath, isNotNull);
        expect(File(extractedPath!).existsSync(), isTrue);

        final extractedBytes = File(extractedPath).readAsBytesSync();
        expect(extractedBytes.length, equals(posterBytes.length));
        expect(extractedBytes, equals(posterBytes));

        // Calling findPosterFrame automatically returns the extracted poster frame
        final poster = MediaProxyUtils.findPosterFrame(crmPath);
        expect(poster, isNotNull);
        expect(poster!.path, equals(extractedPath));
      },
    );

    test(
      'findLinkedProxyPath finds GoPro GL companion proxy from GX master clip',
      () {
        final masterGoPro = p.join(tempDir.path, 'GX018226.MP4');
        final proxyLrv = p.join(tempDir.path, 'GL018226.LRV');

        File(masterGoPro).createSync();
        File(proxyLrv).createSync();

        final found = MediaProxyUtils.findLinkedProxyPath(masterGoPro);
        expect(found, equals(proxyLrv));
      },
    );
  });
}
