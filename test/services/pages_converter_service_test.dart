import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/services/pages_converter_service.dart';

void main() {
  group('PagesConverterService', () {
    tearDown(() {
      PagesConverterService.overrideIsMacOS = null;
      PagesConverterService.processRunner = Process.run;
    });

    test('returns null when platform is not macOS', () async {
      PagesConverterService.overrideIsMacOS = false;
      bool runnerCalled = false;

      final result = await PagesConverterService.convertPagesToXlsx(
        '/path/to/test.pages',
        runner: (exe, args) async {
          runnerCalled = true;
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(result, isNull);
      expect(runnerCalled, isFalse);
    });

    test('invokes osascript with headless AppleScript when platform is macOS', () async {
      PagesConverterService.overrideIsMacOS = true;

      String? capturedExecutable;
      List<String>? capturedArgs;
      String? createdTempPath;

      final result = await PagesConverterService.convertPagesToXlsx(
        '/Users/editor/Documents/Callsheet.pages',
        runner: (exe, args) async {
          capturedExecutable = exe;
          capturedArgs = args;

          // Extract output path from script and create the mock file
          final script = args[1];
          final regex = RegExp(r'export doc to POSIX file "([^"]+)" as Microsoft Excel');
          final match = regex.firstMatch(script);
          if (match != null) {
            createdTempPath = match.group(1);
            File(createdTempPath!).writeAsStringSync('mock excel bytes');
          }

          return ProcessResult(1234, 0, 'success', '');
        },
      );

      addTearDown(() {
        if (createdTempPath != null && File(createdTempPath!).existsSync()) {
          File(createdTempPath!).deleteSync();
        }
      });

      expect(capturedExecutable, 'osascript');
      expect(capturedArgs, isNotNull);
      expect(capturedArgs!.length, 2);
      expect(capturedArgs![0], '-e');
      expect(capturedArgs![1], contains('tell application "Pages"'));
      expect(capturedArgs![1], contains('/Users/editor/Documents/Callsheet.pages'));
      expect(capturedArgs![1], contains('as Microsoft Excel'));
      expect(capturedArgs![1], contains('close doc saving no'));

      expect(result, isNotNull);
      expect(result, createdTempPath);
      expect(File(result!).existsSync(), isTrue);
    });

    test('returns null when osascript returns non-zero exit code', () async {
      PagesConverterService.overrideIsMacOS = true;

      final result = await PagesConverterService.convertPagesToXlsx(
        '/Users/editor/Documents/Missing.pages',
        runner: (exe, args) async {
          return ProcessResult(1235, 1, '', 'Pages error: File not found');
        },
      );

      expect(result, isNull);
    });

    test('returns null when runner throws an exception', () async {
      PagesConverterService.overrideIsMacOS = true;

      final result = await PagesConverterService.convertPagesToXlsx(
        '/Users/editor/Documents/Broken.pages',
        runner: (exe, args) async {
          throw const ProcessException('osascript', ['-e'], 'Command failed', 127);
        },
      );

      expect(result, isNull);
    });
  });
}
