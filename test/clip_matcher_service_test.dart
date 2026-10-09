import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/models/dry_run_report.dart';

void main() {
  group('ClipMatcherService', () {
    test('extractClipNumber', () {
      expect(ClipMatcherService.extractClipNumber('C0001.MP4'), '001');
      expect(ClipMatcherService.extractClipNumber('CLIP002.MOV'), '002');
      expect(ClipMatcherService.extractClipNumber('001.mov'), '001');
      expect(ClipMatcherService.extractClipNumber('CAM_C_003.MXF'), '003');
      expect(ClipMatcherService.extractClipNumber('A007C001_261007OC.MP4'), '001');
      expect(ClipMatcherService.extractClipNumber('SonyC0012.MP4'), '012');
    });

    test('matchFiles logic', () {
      ShootingLog log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: '001')
          ]),
          ShotRecord(chapter: '1', scene: '10', plane: '2', take: '2', reel: 'A007', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: '003') // 002 is skipped/unmatched, 003 is missing
          ]),
        ]
      );

      List<ScannedFile> files = [
        ScannedFile('C0001.MP4'),
        ScannedFile('C0001M01.XML'),
        ScannedFile('C0002.MP4'), // Unmatched
        ScannedFile('C0099.MP4'), // Unmatched
      ];

      var report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A'
      );

      expect(report.totalMatched, 1);
      expect(report.totalMissing, 1);
      expect(report.totalUnmatched, 2);
      expect(report.hasConflicts, false);

      var readyProposal = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001.MP4');
      expect(readyProposal.status, ProposalStatus.ready);
      expect(readyProposal.proposedFileName, 'MNL_071026_10_1_T1_A007_D3_U3.MP4'); // upper case ext from ScannedFile

      var xmlProposal = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001M01.XML');
      expect(xmlProposal.status, ProposalStatus.ready);
      expect(xmlProposal.isCompanionFile, true);
      expect(xmlProposal.proposedFileName, 'MNL_071026_10_1_T1_A007_D3_U3.XML'); // upper case ext

      var missingProposal = report.proposals.firstWhere((p) => p.status == ProposalStatus.missingFile);
      expect(missingProposal.associatedRecord?.take, '2');

      var unmatchedCount = report.proposals.where((p) => p.status == ProposalStatus.unmatchedClip).length;
      expect(unmatchedCount, 2);
    });

    test('matchFiles logic with history (alreadyRenamed)', () {
      ShootingLog log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: '001')
          ]),
          ShotRecord(chapter: '1', scene: '10', plane: '2', take: '2', reel: 'A007', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: '003')
          ]),
        ]
      );

      List<ScannedFile> files = [
        ScannedFile('MNL_071026_10_1_T1_A007_D3_U3.MP4'), // already perfectly renamed
        ScannedFile('C0003.MP4'), // ready
      ];

      var report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
      );

      var alreadyRenamed = report.proposals.firstWhere((p) => p.status == ProposalStatus.alreadyRenamed);
      expect(alreadyRenamed.originalFilePath, 'MNL_071026_10_1_T1_A007_D3_U3.MP4');
      
      var ready = report.proposals.firstWhere((p) => p.status == ProposalStatus.ready);
      expect(ready.associatedRecord?.cameras.first.clipName, '003');
    });

    test('matchFiles handles middle gaps correctly (non-sequential)', () {
      ShootingLog log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: '001')
          ]),
          ShotRecord(chapter: '1', scene: '10', plane: '2', take: '2', reel: 'A007', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: '002')
          ]),
          ShotRecord(chapter: '1', scene: '10', plane: '3', take: '3', reel: 'A007', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: '003')
          ]),
          ShotRecord(chapter: '1', scene: '10', plane: '4', take: '4', reel: 'A007', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: '004')
          ]),
        ]
      );

      List<ScannedFile> files = [
        ScannedFile('C0001.MP4'),
        ScannedFile('C0002.MP4'),
        // Gap: C0003 is missing from disk
        ScannedFile('C0004.MP4'), 
      ];

      var report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
      );

      expect(report.totalMatched, 3); // 1, 2, 4
      expect(report.totalMissing, 1); // 3
      
      var missingProposal = report.proposals.firstWhere((p) => p.status == ProposalStatus.missingFile);
      expect(missingProposal.associatedRecord?.take, '3');
      expect(missingProposal.associatedRecord?.cameras.first.clipName, '003');

      var readyFor004 = report.proposals.firstWhere((p) => p.associatedRecord?.cameras.first.clipName == '004');
      expect(readyFor004.status, ProposalStatus.ready);
      expect(readyFor004.originalFilePath, 'C0004.MP4');
    });

    test('matchFiles filters out files belonging to other cameras based on prefix', () {
      ShootingLog log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(chapter: '1', scene: '10', plane: '3', take: '3', reel: 'B007', cameras: [
            CameraTakeRecord(cameraName: 'B', clipName: '003')
          ]),
        ]
      );

      List<ScannedFile> files = [
        ScannedFile('A007C003.MP4'), // Should be ignored completely because it starts with A
        ScannedFile('B007C003.MP4'), // Should be matched successfully
      ];

      var report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'B',
      );

      expect(report.totalMatched, 1);
      expect(report.hasConflicts, false);
      expect(report.totalUnmatched, 0); // A007C003 should not even register as unmatched

      var readyFor003 = report.proposals.firstWhere((p) => p.status == ProposalStatus.ready);
      expect(readyFor003.originalFilePath, 'B007C003.MP4');
      expect(readyFor003.proposedFileName, 'MNL_071026_10_3_T3_B007_D3_U3.MP4');
    });
  });
}
