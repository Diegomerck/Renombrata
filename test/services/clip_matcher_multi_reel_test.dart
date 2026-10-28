import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';

void main() {
  group('ClipMatcherService - Multi-Reel Clip Matching Tests', () {
    late ShootingLog multiReelLog;

    setUp(() {
      final records = <ShotRecord>[];

      // Reel A001 with clips 1 to 5
      for (int i = 1; i <= 5; i++) {
        records.add(ShotRecord(
          id: 'rec_a001_$i',
          chapter: '1',
          scene: '10',
          plane: '1',
          take: '$i',
          reel: 'A001',
          cameras: [
            CameraTakeRecord(
              cameraName: 'A',
              clipName: i.toString().padLeft(3, '0'),
            ),
          ],
        ));
      }

      // Reel A002 with clips 1 to 5 (same clip numbers, different reel)
      for (int i = 1; i <= 5; i++) {
        records.add(ShotRecord(
          id: 'rec_a002_$i',
          chapter: '1',
          scene: '20',
          plane: '1',
          take: '$i',
          reel: 'A002',
          cameras: [
            CameraTakeRecord(
              cameraName: 'A',
              clipName: i.toString().padLeft(3, '0'),
            ),
          ],
        ));
      }

      multiReelLog = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'TODTA',
          date: '261027',
          unit: 'U1',
          day: 'D01',
          producer: 'P',
          production: 'TODTA',
          location: 'LOC',
          audioFormat: '48k',
          frameRate: '24fps',
          videoCodec: 'ProRes',
          responsibleEngineer: 'ENG',
          ingestor: 'ING',
        ),
        records: records,
      );
    });

    test('matches Reel A001 and Reel A002 clips without collision or reel conflict', () {
      final scannedFiles = [
        ScannedFile('/media/A001C001_261027_R001.MP4'),
        ScannedFile('/media/A001C002_261027_R001.MP4'),
        ScannedFile('/media/A002C001_261027_R002.MP4'),
        ScannedFile('/media/A002C002_261027_R002.MP4'),
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: scannedFiles,
        log: multiReelLog,
        targetCamera: 'A',
      );

      expect(report.hasConflicts, isFalse);

      // Verify A001C001 matches Reel A001 Take 1
      final a001Prop = report.proposals.firstWhere(
        (p) => p.originalFilePath == '/media/A001C001_261027_R001.MP4',
      );
      expect(a001Prop.status, equals(ProposalStatus.ready));
      expect(a001Prop.hasReelDiscrepancy, isFalse);
      expect(a001Prop.associatedRecord?.reel, equals('A001'));
      expect(a001Prop.associatedRecord?.take, equals('1'));
      expect(a001Prop.proposedFileName, equals('TODTA_261027_10_1_T1_A001_D01_U1.MP4'));

      // Verify A002C001 matches Reel A002 Take 1 (not overwritten by A001 or vice versa)
      final a002Prop = report.proposals.firstWhere(
        (p) => p.originalFilePath == '/media/A002C001_261027_R002.MP4',
      );
      expect(a002Prop.status, equals(ProposalStatus.ready));
      expect(a002Prop.hasReelDiscrepancy, isFalse);
      expect(a002Prop.associatedRecord?.reel, equals('A002'));
      expect(a002Prop.associatedRecord?.take, equals('1'));
      expect(a002Prop.proposedFileName, equals('TODTA_261027_20_1_T1_A002_D01_U1.MP4'));
    });

    test('when only Reel A001 card is scanned, A001 clips match ready and A002 clips are missing', () {
      final scannedFiles = [
        ScannedFile('/media/A001C001_261027_R001.MP4'),
        ScannedFile('/media/A001C002_261027_R001.MP4'),
        ScannedFile('/media/A001C003_261027_R001.MP4'),
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: scannedFiles,
        log: multiReelLog,
        targetCamera: 'A',
      );

      expect(report.hasConflicts, isFalse);
      expect(report.totalMatched, equals(3));
      expect(report.totalMissing, equals(7)); // 2 from A001 + 5 from A002

      final a001Prop = report.proposals.firstWhere(
        (p) => p.originalFilePath == '/media/A001C001_261027_R001.MP4',
      );
      expect(a001Prop.status, equals(ProposalStatus.ready));
      expect(a001Prop.hasReelDiscrepancy, isFalse);
      expect(a001Prop.associatedRecord?.reel, equals('A001'));

      // Verify missing proposal exists for Reel A002 Clip 001
      final a002Missing = report.proposals.firstWhere(
        (p) => p.associatedRecord?.reel == 'A002' && p.associatedRecord?.take == '1',
      );
      expect(a002Missing.status, equals(ProposalStatus.missingFile));
      expect(a002Missing.originalFilePath, isNull);
    });
  });
}
