import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/services/sidecar_metadata_service.dart';

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

    test('propagates sidecar timecode and evaluates isTimecodeMatched', () {
      ShootingLog log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007', tcIn: '10:00:00:00', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: '001')
          ]),
          ShotRecord(chapter: '1', scene: '10', plane: '2', take: '2', reel: 'A007', tcIn: '11:00:00:00', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: '002')
          ]),
        ]
      );

      const xml001 = '''
<NonRealTimeMeta>
  <Duration value="1440"/>
  <LtcChangeTable tcFps="24p">
    <LtcChange frameCount="0" value="00000010"/>
  </LtcChangeTable>
</NonRealTimeMeta>
''';

      const xml002 = '''
<NonRealTimeMeta>
  <Duration value="720"/>
  <LtcChangeTable tcFps="24p">
    <LtcChange frameCount="0" value="00000012"/>
  </LtcChangeTable>
</NonRealTimeMeta>
''';

      List<ScannedFile> files = [
        ScannedFile('C0001.MP4'),
        ScannedFile('C0001M01.XML'),
        ScannedFile('C0002.MP4'),
        ScannedFile('C0002M01.XML'),
      ];

      var report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        xmlContentsForTesting: {
          'C0001M01.XML': xml001,
          'C0002M01.XML': xml002,
        },
      );

      var p1Video = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001.MP4');
      expect(p1Video.fileTcIn, '10:00:00:00');
      expect(p1Video.fileTcOut, '10:01:00:00');
      expect(p1Video.isTimecodeMatched, isTrue);

      var p1Xml = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001M01.XML');
      expect(p1Xml.fileTcIn, '10:00:00:00');
      expect(p1Xml.fileTcOut, '10:01:00:00');
      expect(p1Xml.isTimecodeMatched, isTrue);

      var p2Video = report.proposals.firstWhere((p) => p.originalFilePath == 'C0002.MP4');
      expect(p2Video.fileTcIn, '12:00:00:00');
      expect(p2Video.fileTcOut, '12:00:30:00');
      expect(p2Video.isTimecodeMatched, isFalse);
    });

    test('RenameProposal smart tolerance and delta calculation', () {
      final record = ShotRecord(
        chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007',
        tcIn: '10:00:15:00',
        cameras: [],
      );

      // 1. Within In->Out window (+ 10s margin)
      final proposalInWindow = RenameProposal(
        proposedFileName: 'test.mp4',
        status: ProposalStatus.ready,
        associatedRecord: record,
        fileTcIn: '10:00:00:00',
        fileTcOut: '10:01:00:00',
      );
      expect(proposalInWindow.isTimecodeMatched, isTrue);
      expect(proposalInWindow.timecodeDeltaSeconds, 15);

      // 2. Pre-roll 5 seconds before fileTcIn (within 10s margin of fileInSec)
      final recordPreRoll = ShotRecord(
        chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007',
        tcIn: '09:59:55:00', // 5s before fileTcIn 10:00:00:00
        cameras: [],
      );
      final proposalPreRoll = RenameProposal(
        proposedFileName: 'test.mp4',
        status: ProposalStatus.ready,
        associatedRecord: recordPreRoll,
        fileTcIn: '10:00:00:00',
        fileTcOut: '10:01:00:00',
      );
      expect(proposalPreRoll.isTimecodeMatched, isTrue);
      expect(proposalPreRoll.timecodeDeltaSeconds, 5);

      // 3. Beyond window + 10s margin
      final recordFar = ShotRecord(
        chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007',
        tcIn: '10:02:00:00', // > 10:01:10:00
        cameras: [],
      );
      final proposalFar = RenameProposal(
        proposedFileName: 'test.mp4',
        status: ProposalStatus.ready,
        associatedRecord: recordFar,
        fileTcIn: '10:00:00:00',
        fileTcOut: '10:01:00:00',
      );
      expect(proposalFar.isTimecodeMatched, isFalse);

      // 4. fileTcOut == null, within 30s tolerance
      final proposalNoOut = RenameProposal(
        proposedFileName: 'test.mp4',
        status: ProposalStatus.ready,
        associatedRecord: record, // 10:00:15:00
        fileTcIn: '10:00:00:00', // diff is 15s <= 30s
      );
      expect(proposalNoOut.isTimecodeMatched, isTrue);
      expect(proposalNoOut.timecodeDeltaSeconds, 15);

      // 5. fileTcOut == null, > 30s tolerance
      final proposalNoOutFar = RenameProposal(
        proposedFileName: 'test.mp4',
        status: ProposalStatus.ready,
        associatedRecord: record, // 10:00:15:00
        fileTcIn: '10:01:00:00', // diff is 45s > 30s
      );
      expect(proposalNoOutFar.isTimecodeMatched, isFalse);
      expect(proposalNoOutFar.timecodeDeltaSeconds, 45);
    });

    test('matchFilesAsync probes standalone video file when no XML is present', () async {
      final log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(
            chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007',
            tcIn: '10:00:00:00',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
          ),
        ],
      );

      final files = [
        ScannedFile('C0001.MOV'), // No companion XML
      ];

      var probeCalled = false;
      final report = await ClipMatcherService.matchFilesAsync(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        probeFunction: (filePath) async {
          probeCalled = true;
          return SidecarMetadata(
            tcIn: '10:00:00:00',
            tcOut: '10:00:10:00',
            frameRate: '24.000',
          );
        },
      );

      expect(probeCalled, isTrue);
      final proposal = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001.MOV');
      expect(proposal.fileTcIn, '10:00:00:00');
      expect(proposal.fileTcOut, '10:00:10:00');
      expect(proposal.isTimecodeMatched, isTrue);
    });

    test('matchFilesAsync preserves companion XML timecode and skips probing', () async {
      final log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(
            chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007',
            tcIn: '10:00:00:00',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
          ),
        ],
      );

      final files = [
        ScannedFile('C0001.MP4'),
        ScannedFile('C0001M01.XML'),
      ];

      var probeCalled = false;
      final report = await ClipMatcherService.matchFilesAsync(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        xmlContentsForTesting: {
          'C0001M01.XML': '''<?xml version="1.0" encoding="UTF-8"?>
<NonRealTimeMeta xmlns="urn:schemas-professionalDisc:nonRealTimeMeta:ver.2.20">
  <LtcChangeTable tcFps="24p">
    <LtcChange value="00000010" status="increment" frameCount="0" />
  </LtcChangeTable>
  <Duration value="240" />
</NonRealTimeMeta>''',
        },
        probeFunction: (filePath) async {
          probeCalled = true;
          return SidecarMetadata(tcIn: '99:99:99:99');
        },
      );

      // Probe function should NOT be called because XML already provided fileTcIn
      expect(probeCalled, isFalse);
      final videoProposal = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001.MP4');
      expect(videoProposal.fileTcIn, '10:00:00:00');
      expect(videoProposal.fileTcOut, '10:00:10:00');
      expect(videoProposal.isTimecodeMatched, isTrue);
    });

    test('matchFilesAsync handles probe returning null gracefully', () async {
      final log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(
            chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
          ),
        ],
      );

      final files = [
        ScannedFile('C0001.MXF'),
      ];

      final report = await ClipMatcherService.matchFilesAsync(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        probeFunction: (filePath) async => null,
      );

      final proposal = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001.MXF');
      expect(proposal.fileTcIn, isNull);
      expect(proposal.fileTcOut, isNull);
      expect(proposal.isTimecodeMatched, isFalse);
    });

    test('single clip with matching clip number but discrepant timecode gets flagged as conflict', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(
            id: 'rec_1',
            chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007',
            tcIn: '10:00:00:00',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
          ),
        ],
      );

      final files = [
        ScannedFile('C0001.MP4'),
        ScannedFile('C0001M01.XML'),
      ];

      // File has TC 09:04:22:00 from Sony LTC "00220409", but log expects 10:00:00:00
      final report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        xmlContentsForTesting: {
          'C0001M01.XML': '''<?xml version="1.0" encoding="UTF-8"?>
<NonRealTimeMeta xmlns="urn:schemas-professionalDisc:nonRealTimeMeta:ver.2.20">
  <LtcChangeTable tcFps="24p">
    <LtcChange value="00220409" status="increment" frameCount="0" />
  </LtcChangeTable>
  <Duration value="240" />
</NonRealTimeMeta>''',
        },
      );

      final videoProposal = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001.MP4');
      final xmlProposal = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001M01.XML');

      expect(videoProposal.fileTcIn, '09:04:22:00');
      expect(videoProposal.hasTimecodeDiscrepancy, isTrue);
      expect(videoProposal.status, ProposalStatus.conflict);

      expect(xmlProposal.fileTcIn, '09:04:22:00');
      expect(xmlProposal.status, ProposalStatus.conflict);
      expect(report.hasConflicts, isTrue);
    });

    test('manual override on a discrepant clip successfully transitions it to ready', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(
            id: 'rec_1',
            chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007',
            tcIn: '10:00:00:00',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
          ),
        ],
      );

      final files = [
        ScannedFile('C0001.MP4'),
        ScannedFile('C0001M01.XML'),
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        manualOverrides: {
          'C0001.MP4': 'rec_1',
        },
        xmlContentsForTesting: {
          'C0001M01.XML': '''<?xml version="1.0" encoding="UTF-8"?>
<NonRealTimeMeta xmlns="urn:schemas-professionalDisc:nonRealTimeMeta:ver.2.20">
  <LtcChangeTable tcFps="24p">
    <LtcChange value="00220409" status="increment" frameCount="0" />
  </LtcChangeTable>
  <Duration value="240" />
</NonRealTimeMeta>''',
        },
      );

      final videoProposal = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001.MP4');
      final xmlProposal = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001M01.XML');

      expect(videoProposal.status, ProposalStatus.ready);
      expect(xmlProposal.status, ProposalStatus.ready);
      expect(report.hasConflicts, isFalse);
    });

    test('matchFilesAsync flags single probed video with TC discrepancy as conflict', () async {
      final log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(
            id: 'rec_1',
            chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007',
            tcIn: '10:00:00:00',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
          ),
        ],
      );

      final files = [
        ScannedFile('C0001.MOV'),
      ];

      final report = await ClipMatcherService.matchFilesAsync(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        probeFunction: (filePath) async => SidecarMetadata(
          tcIn: '09:00:00:00', // Discrepant from 10:00:00:00
          tcOut: '09:01:00:00',
        ),
      );

      final proposal = report.proposals.firstWhere((p) => p.originalFilePath == 'C0001.MOV');
      expect(proposal.fileTcIn, '09:00:00:00');
      expect(proposal.hasTimecodeDiscrepancy, isTrue);
      expect(proposal.status, ProposalStatus.conflict);
      expect(report.hasConflicts, isTrue);
    });

    test('extractReel on various camera filenames', () {
      expect(ClipMatcherService.extractReel('A001C001_260608ZY.MP4'), 'A001');
      expect(ClipMatcherService.extractReel('B002C015.MOV'), 'B002');
      expect(ClipMatcherService.extractReel('A001_C001_take1.mp4'), 'A001');
      expect(ClipMatcherService.extractReel('C0001.MP4'), isNull);
      expect(ClipMatcherService.extractReel('unrelated_file.txt'), isNull);
    });

    test('isReelMatched and hasReelDiscrepancy logic', () {
      expect(RenameProposal.isReelMatched('A001', 'A001'), isTrue);
      expect(RenameProposal.isReelMatched('A001', '001'), isTrue);
      expect(RenameProposal.isReelMatched('001', 'A001'), isTrue);
      expect(RenameProposal.isReelMatched('A001', '002'), isFalse);
      expect(RenameProposal.isReelMatched('A007', 'A007_1'), isTrue);
      expect(RenameProposal.isReelMatched('A001', 'A007_1'), isFalse);
      expect(RenameProposal.isReelMatched('A001', 'B001'), isFalse);
      expect(RenameProposal.isReelMatched(null, 'A007_1'), isTrue);
      expect(RenameProposal.isReelMatched('A001', null), isTrue);

      final recordA007 = ShotRecord(
        chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007_1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
      );

      final propMatching = RenameProposal(
        proposedFileName: 'test.mp4',
        status: ProposalStatus.ready,
        fileReel: 'A007',
        associatedRecord: recordA007,
      );
      expect(propMatching.hasReelDiscrepancy, isFalse);

      final propDiscrepant = RenameProposal(
        proposedFileName: 'test.mp4',
        status: ProposalStatus.ready,
        fileReel: 'A001',
        associatedRecord: recordA007,
      );
      expect(propDiscrepant.hasReelDiscrepancy, isTrue);
    });

    test('matchFiles flags reel discrepancy as conflict', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(
            id: 'rec_reel_test',
            chapter: '1', scene: '102Y103', plane: '1', take: '1', reel: 'A007_1',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
          ),
        ],
      );

      // File is from reel A001, but bitácora says A007_1
      final files = [
        ScannedFile('A001C001_260608ZY.MP4'),
        ScannedFile('A001C001_260608ZYM01.XML'),
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
      );

      final videoProp = report.proposals.firstWhere((p) => p.originalFilePath == 'A001C001_260608ZY.MP4');
      final xmlProp = report.proposals.firstWhere((p) => p.originalFilePath == 'A001C001_260608ZYM01.XML');

      expect(videoProp.fileReel, 'A001');
      expect(videoProp.hasReelDiscrepancy, isTrue);
      expect(videoProp.status, ProposalStatus.conflict);
      expect(xmlProp.status, ProposalStatus.conflict);
      expect(report.hasConflicts, isTrue);
    });

    test('manual override resolves reel discrepancy conflict to ready', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(
            id: 'rec_reel_test',
            chapter: '1', scene: '102Y103', plane: '1', take: '1', reel: 'A007_1',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
          ),
        ],
      );

      final files = [
        ScannedFile('A001C001_260608ZY.MP4'),
        ScannedFile('A001C001_260608ZYM01.XML'),
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        manualOverrides: {
          'A001C001_260608ZY.MP4': 'rec_reel_test',
        },
      );

      final videoProp = report.proposals.firstWhere((p) => p.originalFilePath == 'A001C001_260608ZY.MP4');
      final xmlProp = report.proposals.firstWhere((p) => p.originalFilePath == 'A001C001_260608ZYM01.XML');

      expect(videoProp.status, ProposalStatus.ready);
      expect(xmlProp.status, ProposalStatus.ready);
      expect(report.hasConflicts, isFalse);
    });
  });
}
