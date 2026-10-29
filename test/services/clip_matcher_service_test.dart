import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';

void main() {
  group('ClipMatcherService - Stable Natural Ordering Tests', () {
    test('matchFiles preserves natural disk clip order when a subset of clips are matched', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty().copyWith(
          nomenclature: 'TEST',
          date: '261028',
          day: '1',
          unit: '1',
        ),
        records: [
          // Only clip 002 is matched in the shooting log
          ShotRecord(
            chapter: '1',
            scene: '10',
            take: '1',
            reel: 'A001',
            cameras: [
              CameraTakeRecord(cameraName: 'A', clipName: '002'),
            ],
          ),
        ],
      );

      final files = [
        ScannedFile('/media/A001C001.MP4'), // unmatched
        ScannedFile('/media/A001C002.MP4'), // matched (ready)
        ScannedFile('/media/A001C002M01.XML'), // companion
        ScannedFile('/media/A001C003.MP4'), // unmatched
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
      );

      // Verify that proposals maintain exact C001, C002, C003 order
      // rather than putting matched C002 at the top.
      expect(report.proposals.length, equals(4));

      expect(report.proposals[0].originalFilePath, equals('/media/A001C001.MP4'));
      expect(report.proposals[0].status, equals(ProposalStatus.unmatchedClip));

      expect(report.proposals[1].originalFilePath, equals('/media/A001C002.MP4'));
      expect(report.proposals[1].status, equals(ProposalStatus.ready));
      expect(report.proposals[1].isCompanionFile, isFalse);

      expect(report.proposals[2].originalFilePath, equals('/media/A001C002M01.XML'));
      expect(report.proposals[2].status, equals(ProposalStatus.ready));
      expect(report.proposals[2].isCompanionFile, isTrue);

      expect(report.proposals[3].originalFilePath, equals('/media/A001C003.MP4'));
      expect(report.proposals[3].status, equals(ProposalStatus.unmatchedClip));
    });

    test('extractCamera extracts camera letter from various naming conventions', () {
      expect(ClipMatcherService.extractCamera('A001C002.MP4'), equals('A'));
      expect(ClipMatcherService.extractCamera('B002C015.MOV'), equals('B'));
      expect(ClipMatcherService.extractCamera('C003C001.MXF'), equals('C'));
      expect(ClipMatcherService.extractCamera('C0001.MP4', fallback: 'A'), equals('A'));
      expect(ClipMatcherService.extractCamera('B001_C001_test.mp4'), equals('B'));
    });
  });

  group('Sony M01 Metadata XML Pairing Tests', () {
    test('pairs Sony MXF video with M01.XML sidecar correctly when pairM01Sidecars is true', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty().copyWith(
          nomenclature: 'SERIE',
          date: '230309',
          day: '1',
          unit: '1',
        ),
        records: [
          ShotRecord(
            chapter: '1',
            scene: '55',
            take: '1',
            reel: 'A055',
            cameras: [
              CameraTakeRecord(cameraName: 'A', clipName: '001'),
            ],
          ),
        ],
      );

      final files = [
        ScannedFile('/media/A055C001_230309CV.mxf'),
        ScannedFile('/media/A055C001_230309CVM01.xml'),
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        pairM01Sidecars: true,
      );

      expect(report.proposals.length, equals(2));
      final videoProp = report.proposals.firstWhere((p) => !p.isCompanionFile);
      final xmlProp = report.proposals.firstWhere((p) => p.isCompanionFile);

      expect(videoProp.originalFilePath, equals('/media/A055C001_230309CV.mxf'));
      expect(videoProp.status, equals(ProposalStatus.ready));

      expect(xmlProp.originalFilePath, equals('/media/A055C001_230309CVM01.xml'));
      expect(xmlProp.status, equals(ProposalStatus.ready));
      expect(xmlProp.isCompanionFile, isTrue);
      // Companion name should have M01 preserved
      expect(xmlProp.proposedFileName.toUpperCase().endsWith('M01.XML'), isTrue);
      expect(
        xmlProp.proposedFileName,
        equals('${videoProp.proposedFileName.replaceAll('.MXF', '')}M01.XML'),
      );
    });

    test('ignores M01.XML sidecars when pairM01Sidecars is false', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty().copyWith(
          nomenclature: 'SERIE',
          date: '230309',
          day: '1',
          unit: '1',
        ),
        records: [
          ShotRecord(
            chapter: '1',
            scene: '55',
            take: '1',
            reel: 'A055',
            cameras: [
              CameraTakeRecord(cameraName: 'A', clipName: '001'),
            ],
          ),
        ],
      );

      final files = [
        ScannedFile('/media/A055C001_230309CV.mxf'),
        ScannedFile('/media/A055C001_230309CVM01.xml'),
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        pairM01Sidecars: false,
      );

      // With pairM01Sidecars: false, M01.xml is not paired as companion
      final companions = report.proposals.where((p) => p.isCompanionFile).toList();
      expect(companions, isEmpty);
    });
  });

  group('All Cameras (ALL) Matching Tests', () {
    test('matches clips across multiple cameras simultaneously when targetCamera is ALL', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty().copyWith(
          nomenclature: 'PROD',
          date: '261028',
          day: '1',
          unit: '1',
        ),
        records: [
          ShotRecord(
            chapter: '1',
            scene: '10',
            take: '1',
            reel: '001',
            cameras: [
              CameraTakeRecord(cameraName: 'A', clipName: '001'),
              CameraTakeRecord(cameraName: 'B', clipName: '001'),
            ],
          ),
        ],
      );

      final files = [
        ScannedFile('/media/A001C001.MP4'),
        ScannedFile('/media/B001C001.MP4'),
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'ALL',
      );

      expect(report.proposals.length, equals(2));
      final aProp = report.proposals.firstWhere(
        (p) => p.originalFilePath == '/media/A001C001.MP4',
      );
      final bProp = report.proposals.firstWhere(
        (p) => p.originalFilePath == '/media/B001C001.MP4',
      );

      expect(aProp.status, equals(ProposalStatus.ready));
      expect(bProp.status, equals(ProposalStatus.ready));
    });
  });
}

