import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/services/still_capture_service.dart';

class _FakeScreenshotPlayer extends Fake implements Player {
  Uint8List? screenshotBytes;
  bool shouldThrow = false;
  String? lastFormat;

  _FakeScreenshotPlayer({this.screenshotBytes, this.shouldThrow = false});

  @override
  Future<Uint8List?> screenshot({
    String? format = 'image/jpeg',
    bool includeLibassSubtitles = false,
  }) async {
    lastFormat = format;
    if (shouldThrow) {
      throw Exception('Hardware screenshot error');
    }
    return screenshotBytes;
  }
}

void main() {
  group('StillCaptureService Tests', () {
    late Directory tempTestDir;

    setUp(() {
      tempTestDir = Directory.systemTemp.createTempSync('renombrata_still_test_');
    });

    tearDown(() {
      if (tempTestDir.existsSync()) {
        tempTestDir.deleteSync(recursive: true);
      }
    });

    test('getDesktopDirectoryPath resolves Desktop path with or without overrideHome', () {
      final customHome = p.join(tempTestDir.path, 'MockUser');
      final desktopPath = StillCaptureService.getDesktopDirectoryPath(overrideHome: customHome);
      expect(desktopPath, equals(p.join(customHome, 'Desktop')));

      final defaultDesktop = StillCaptureService.getDesktopDirectoryPath();
      expect(defaultDesktop.endsWith('Desktop'), isTrue);
    });

    test('sanitizeFileName removes disallowed characters and collapses whitespace', () {
      const raw = 'Scene: 12/A *Take? "Best" <Angle> | test\\file';
      final sanitized = StillCaptureService.sanitizeFileName(raw);
      expect(sanitized, equals('Scene- 12-A -Take- -Best- -Angle- - test-file'));
      expect(sanitized.contains(':'), isFalse);
      expect(sanitized.contains('/'), isFalse);
      expect(sanitized.contains('*'), isFalse);
      expect(sanitized.contains('?'), isFalse);
      expect(sanitized.contains('"'), isFalse);
      expect(sanitized.contains('<'), isFalse);
      expect(sanitized.contains('>'), isFalse);
      expect(sanitized.contains('|'), isFalse);
      expect(sanitized.contains(r'\'), isFalse);
    });

    test('getProjectStillsDirectory creates correct folder name with fallback and sanitization', () {
      final baseDesktop = p.join(tempTestDir.path, 'Desktop');

      // Normal valid input
      final dir1 = StillCaptureService.getProjectStillsDirectory(
        projectName: 'La Máquina: Producción',
        date: '2026-11-06',
        baseDesktopPath: baseDesktop,
      );
      expect(
        p.basename(dir1.path),
        equals('Stills - La Máquina- Producción - 2026-11-06'),
      );
      expect(dir1.path.startsWith(baseDesktop), isTrue);

      // Empty project name and date fallback
      final dir2 = StillCaptureService.getProjectStillsDirectory(
        projectName: '   ',
        date: '',
        baseDesktopPath: baseDesktop,
      );
      expect(p.basename(dir2.path).startsWith('Stills - Proyecto Sin Título - '), isTrue);
    });

    test('captureStill writes screenshot bytes and handles collision naming', () async {
      final stillsDir = Directory(p.join(tempTestDir.path, 'Stills - Test'));
      final fakeBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02]);
      final player = _FakeScreenshotPlayer(screenshotBytes: fakeBytes);

      // 1. First capture -> baseName.jpg
      final file1 = await StillCaptureService.captureStill(
        player: player,
        baseName: 'A001_C001_110626',
        targetDir: stillsDir,
        format: 'image/jpeg',
      );
      expect(file1, isNotNull);
      expect(file1!.existsSync(), isTrue);
      expect(p.basename(file1.path), equals('A001_C001_110626.jpg'));
      expect(await file1.readAsBytes(), equals(fakeBytes));
      expect(player.lastFormat, equals('image/jpeg'));

      // 2. Second capture with same baseName -> baseName (1).jpg
      final file2 = await StillCaptureService.captureStill(
        player: player,
        baseName: 'A001_C001_110626',
        targetDir: stillsDir,
        format: 'image/jpeg',
      );
      expect(file2, isNotNull);
      expect(file2!.existsSync(), isTrue);
      expect(p.basename(file2.path), equals('A001_C001_110626 (1).jpg'));

      // 3. Third capture -> baseName (2).jpg
      final file3 = await StillCaptureService.captureStill(
        player: player,
        baseName: 'A001_C001_110626',
        targetDir: stillsDir,
        format: 'image/jpeg',
      );
      expect(file3, isNotNull);
      expect(file3!.existsSync(), isTrue);
      expect(p.basename(file3.path), equals('A001_C001_110626 (2).jpg'));

      // 4. PNG format produces .png extension
      final filePng = await StillCaptureService.captureStill(
        player: player,
        baseName: 'A001_C001_110626',
        targetDir: stillsDir,
        format: 'image/png',
      );
      expect(filePng, isNotNull);
      expect(filePng!.existsSync(), isTrue);
      expect(p.basename(filePng.path), equals('A001_C001_110626.png'));
      expect(player.lastFormat, equals('image/png'));
    });

    test('captureStill returns null when screenshot produces empty or null data', () async {
      final stillsDir = Directory(p.join(tempTestDir.path, 'Stills - NullTest'));
      final player = _FakeScreenshotPlayer(screenshotBytes: null);

      final file = await StillCaptureService.captureStill(
        player: player,
        baseName: 'NullShot',
        targetDir: stillsDir,
      );
      expect(file, isNull);

      final emptyPlayer = _FakeScreenshotPlayer(screenshotBytes: Uint8List(0));
      final fileEmpty = await StillCaptureService.captureStill(
        player: emptyPlayer,
        baseName: 'EmptyShot',
        targetDir: stillsDir,
      );
      expect(fileEmpty, isNull);
    });

    test('captureStill returns null safely when player throws', () async {
      final stillsDir = Directory(p.join(tempTestDir.path, 'Stills - ErrorTest'));
      final player = _FakeScreenshotPlayer(shouldThrow: true);

      final file = await StillCaptureService.captureStill(
        player: player,
        baseName: 'CrashShot',
        targetDir: stillsDir,
      );
      expect(file, isNull);
    });
  });
}
