import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/services/rename_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rename_safety_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('RenameService - Ironclad Non-Destructive Guardrails', () {
    test('Pre-flight batch collision check: throws Exception when two proposals resolve to same target path', () async {
      final fileA = File(p.join(tempDir.path, 'A001C001.MP4'));
      final fileB = File(p.join(tempDir.path, 'B001C001.MP4'));
      await fileA.writeAsString('video A content');
      await fileB.writeAsString('video B content');

      final proposals = [
        RenameProposal(
          originalFilePath: fileA.path,
          proposedFileName: 'CONVENTION_COLLISION.MP4',
          status: ProposalStatus.ready,
        ),
        RenameProposal(
          originalFilePath: fileB.path,
          proposedFileName: 'convention_collision.mp4', // Case-insensitive collision!
          status: ProposalStatus.ready,
        ),
      ];

      expect(
        () async => await RenameService.executeRename(
          mediaFolderPath: tempDir.path,
          proposals: proposals,
          renameMetadata: false,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Operación bloqueada por seguridad: Dos o más archivos intentan renombrarse al mismo nombre'),
          ),
        ),
      );

      // Verify ZERO files were renamed or destroyed
      expect(await fileA.exists(), isTrue);
      expect(await fileB.exists(), isTrue);
      expect(await fileA.readAsString(), equals('video A content'));
      expect(await fileB.readAsString(), equals('video B content'));
      expect(await File(p.join(tempDir.path, 'CONVENTION_COLLISION.MP4')).exists(), isFalse);
    });

    test('Pre-flight disk existence check: throws Exception when target file already exists on disk', () async {
      final fileA = File(p.join(tempDir.path, 'A001C001.MP4'));
      final existingTarget = File(p.join(tempDir.path, 'ALREADY_EXISTS.MP4'));
      await fileA.writeAsString('original clip');
      await existingTarget.writeAsString('important existing media');

      final proposals = [
        RenameProposal(
          originalFilePath: fileA.path,
          proposedFileName: 'ALREADY_EXISTS.MP4',
          status: ProposalStatus.ready,
        ),
      ];

      expect(
        () async => await RenameService.executeRename(
          mediaFolderPath: tempDir.path,
          proposals: proposals,
          renameMetadata: false,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Operación bloqueada por seguridad: El archivo destino ya existe en disco'),
          ),
        ),
      );

      // Verify existing file was NOT overwritten
      expect(await fileA.exists(), isTrue);
      expect(await existingTarget.exists(), isTrue);
      expect(await existingTarget.readAsString(), equals('important existing media'));
    });

    test('Undo rename safety: never overwrites existing file at originalPath during undo', () async {
      final fileA = File(p.join(tempDir.path, 'A001C001.MP4'));
      await fileA.writeAsString('original video');

      final proposals = [
        RenameProposal(
          originalFilePath: fileA.path,
          proposedFileName: 'RENAMED_CLIP.MP4',
          status: ProposalStatus.ready,
        ),
      ];

      // Execute legitimate rename
      await RenameService.executeRename(
        mediaFolderPath: tempDir.path,
        proposals: proposals,
        renameMetadata: false,
      );

      final renamedFile = File(p.join(tempDir.path, 'RENAMED_CLIP.MP4'));
      expect(await renamedFile.exists(), isTrue);
      expect(await fileA.exists(), isFalse);

      // Now create a NEW file at originalPath (e.g. user or external process put a new file there)
      await fileA.writeAsString('new intruder file at original path');

      // Attempt undo
      await RenameService.undoRename(tempDir.path);

      // Verify that neither file was overwritten
      expect(await renamedFile.exists(), isTrue);
      expect(await fileA.exists(), isTrue);
      expect(await fileA.readAsString(), equals('new intruder file at original path'));

      // Verify the history entry was preserved because it could not be safely undone
      final history = await RenameService.readRenameHistory(tempDir.path);
      expect(history.length, equals(1));
    });

    test('Successful rename and undo workflow when no collisions exist', () async {
      final fileA = File(p.join(tempDir.path, 'A001C001.MP4'));
      final companionA = File(p.join(tempDir.path, 'A001C001M01.XML'));
      await fileA.writeAsString('video content');
      await companionA.writeAsString('<xml>metadata</xml>');

      final proposals = [
        RenameProposal(
          originalFilePath: fileA.path,
          proposedFileName: 'SC01_T01.MP4',
          status: ProposalStatus.ready,
        ),
        RenameProposal(
          originalFilePath: companionA.path,
          proposedFileName: 'SC01_T01M01.XML',
          status: ProposalStatus.ready,
          isCompanionFile: true,
        ),
      ];

      await RenameService.executeRename(
        mediaFolderPath: tempDir.path,
        proposals: proposals,
        renameMetadata: true,
      );

      final newVideo = File(p.join(tempDir.path, 'SC01_T01.MP4'));
      final newXml = File(p.join(tempDir.path, 'SC01_T01M01.XML'));
      expect(await newVideo.exists(), isTrue);
      expect(await newXml.exists(), isTrue);
      expect(await fileA.exists(), isFalse);
      expect(await companionA.exists(), isFalse);

      // Undo rename
      await RenameService.undoRename(tempDir.path);

      expect(await fileA.exists(), isTrue);
      expect(await companionA.exists(), isTrue);
      expect(await newVideo.exists(), isFalse);
      expect(await newXml.exists(), isFalse);

      final history = await RenameService.readRenameHistory(tempDir.path);
      expect(history, isEmpty);
    });
  });
}

