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
  group('Post-Rename Recognition & Clip Number Extraction Tests', () {
    test('extractClipNumber parses multi-token convention strings without confusing unit (U3) with clip number', () {
      expect(ClipMatcherService.extractClipNumber('MNBOENC_080626_17_11_T1_A001_1_D1_U3.MP4'), equals('001'));
      expect(ClipMatcherService.extractClipNumber('MNBOENC_080626_17_11_T2_A001_2_D1_U3.MP4'), equals('002'));
      expect(ClipMatcherService.extractClipNumber('MNBOENC_080626_17_11_T3_A001_15_D1_U3.MP4'), equals('015'));
      expect(ClipMatcherService.extractClipNumber('A001C001_260608ZY.MP4'), equals('001'));
      expect(ClipMatcherService.extractClipNumber('B001C002_260608HE.MP4'), equals('002'));
    });

    test('matchFiles recognizes already-renamed files via renameHistory and restores original reel and clip', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty().copyWith(
          nomenclature: 'MNBOENC',
          date: '080626',
          day: '1',
          unit: '3',
        ),
        records: [
          ShotRecord(
            chapter: '1',
            scene: '17',
            take: '1',
            reel: 'A001',
            cameras: [
              CameraTakeRecord(cameraName: 'A', clipName: '001'),
            ],
          ),
          ShotRecord(
            chapter: '1',
            scene: '17',
            take: '2',
            reel: 'A001',
            cameras: [
              CameraTakeRecord(cameraName: 'A', clipName: '002'),
            ],
          ),
        ],
      );

      final files = [
        ScannedFile('/media/MNBOENC_080626_17_11_T1_A001_1_D1_U3.MP4'),
        ScannedFile('/media/MNBOENC_080626_17_11_T2_A001_2_D1_U3.MP4'),
      ];

      final renameHistory = [
        {
          'originalPath': '/media/A001C001_260608ZY.MP4',
          'renamedPath': '/media/MNBOENC_080626_17_11_T1_A001_1_D1_U3.MP4',
        },
        {
          'originalPath': '/media/A001C002_260608HE.MP4',
          'renamedPath': '/media/MNBOENC_080626_17_11_T2_A001_2_D1_U3.MP4',
        },
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        renameHistory: renameHistory,
      );

      expect(report.proposals.length, equals(2));
      final p1 = report.proposals.firstWhere(
        (p) => p.originalFilePath == '/media/MNBOENC_080626_17_11_T1_A001_1_D1_U3.MP4',
      );
      final p2 = report.proposals.firstWhere(
        (p) => p.originalFilePath == '/media/MNBOENC_080626_17_11_T2_A001_2_D1_U3.MP4',
      );

      expect(p1.status, equals(ProposalStatus.alreadyRenamed));
      expect(p1.fileReel, equals('A001'));
      expect(p1.associatedRecord, isNotNull);
      expect(p1.associatedRecord!.take, equals('1'));

      expect(p2.status, equals(ProposalStatus.alreadyRenamed));
      expect(p2.fileReel, equals('A001'));
      expect(p2.associatedRecord, isNotNull);
      expect(p2.associatedRecord!.take, equals('2'));

      final conflicts = report.proposals.where((p) => p.status == ProposalStatus.conflict).toList();
      final missing = report.proposals.where((p) => p.status == ProposalStatus.missingFile).toList();
      expect(conflicts, isEmpty);
      expect(missing, isEmpty);
    });

    test('Strict Camera Isolation: Cam B clip does not match Cam A log record with reel A001', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty().copyWith(
          nomenclature: 'TEST',
          date: '261028',
          day: '1',
          unit: '1',
        ),
        records: [
          ShotRecord(
            chapter: '1',
            scene: '10',
            take: '1',
            reel: 'A001',
            cameras: [
              CameraTakeRecord(cameraName: 'A', clipName: '001'),
            ],
          ),
        ],
      );

      final files = [
        ScannedFile('/media/B001C001.MP4'),
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
      );

      final ready = report.proposals.where((p) => p.status == ProposalStatus.ready).toList();
      expect(ready, isEmpty);
    });
  });

  group('Universal XML Sidecar Recognition & Companion Pairing Tests', () {
    test('Exact stem match (A_0001C001...MXF + .XML) pairs companion and extracts TC In/Out', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty().copyWith(
          nomenclature: 'INFAMIA',
          date: '260116',
          day: '1',
          unit: '1',
        ),
        records: [
          ShotRecord(
            chapter: '1',
            scene: '1',
            take: '1',
            reel: 'A001',
            cameras: [
              CameraTakeRecord(cameraName: 'A', clipName: '001'),
            ],
          ),
        ],
      );

      final videoPath = '/media/A_0001C001AA01026_160134WZ_INFAM.MXF';
      final xmlPath = '/media/A_0001C001AA01026_160134WZ_INFAM.XML';

      const xmlContent = '<NonRealTimeMeta><LtcChangeTable tcFps="24"><LtcChange status="start" value="02502814" /><LtcChange status="end" value="18152914" /></LtcChangeTable></NonRealTimeMeta>';

      final files = [
        ScannedFile(videoPath),
        ScannedFile(xmlPath),
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: files,
        log: log,
        targetCamera: 'A',
        xmlContentsForTesting: {xmlPath: xmlContent},
      );

      expect(report.proposals.length, equals(2));
      final videoProp = report.proposals.firstWhere((p) => !p.isCompanionFile);
      final xmlProp = report.proposals.firstWhere((p) => p.isCompanionFile);

      expect(videoProp.originalFilePath, equals(videoPath));
      expect(videoProp.companionFilePath, equals(xmlPath));
      expect(videoProp.status, equals(ProposalStatus.ready));
      expect(videoProp.fileTcIn, isNotNull);
      expect(videoProp.fileTcIn, equals('14:28:50:02'));
      expect(videoProp.fileTcOut, equals('14:29:15:18'));

      expect(xmlProp.originalFilePath, equals(xmlPath));
      expect(xmlProp.companionFilePath, equals(videoPath));
      expect(xmlProp.status, equals(ProposalStatus.ready));
      expect(xmlProp.isCompanionFile, isTrue);
      expect(xmlProp.fileTcIn, equals('14:28:50:02'));
      expect(xmlProp.fileTcOut, equals('14:29:15:18'));
    });

    test('Subdirectory sidecar pairing (CLIP/ vs MEDIAMETA/) pairs cleanly', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty().copyWith(
          nomenclature: 'SERIE',
          date: '260116',
          day: '1',
          unit: '1',
        ),
        records: [
          ShotRecord(
            chapter: '1',
            scene: '10',
            take: '1',
            reel: 'A001',
            cameras: [
              CameraTakeRecord(cameraName: 'A', clipName: '001'),
            ],
          ),
        ],
      );

      final videoPath = '/media/CardA/CLIP/A001C001.MXF';
      final xmlPath = '/media/CardA/MEDIAMETA/A001C001.XML';

      final report = ClipMatcherService.matchFiles(
        scannedFiles: [ScannedFile(videoPath), ScannedFile(xmlPath)],
        log: log,
        targetCamera: 'A',
      );

      final videoProp = report.proposals.firstWhere((p) => !p.isCompanionFile);
      final xmlProp = report.proposals.firstWhere((p) => p.isCompanionFile);

      expect(videoProp.companionFilePath, equals(xmlPath));
      expect(xmlProp.companionFilePath, equals(videoPath));
    });

    test('Stripped camera-clip prefix pairing matches A_0001C001...MXF with A_0001C001.XML', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty().copyWith(
          nomenclature: 'INFAMIA',
          date: '260116',
          day: '1',
          unit: '1',
        ),
        records: [
          ShotRecord(
            chapter: '1',
            scene: '1',
            take: '1',
            reel: 'A001',
            cameras: [
              CameraTakeRecord(cameraName: 'A', clipName: '001'),
            ],
          ),
        ],
      );

      final videoPath = '/media/A_0001C001AA01026_160134WZ_INFAM.MXF';
      final xmlPath = '/media/A_0001C001.XML';

      final report = ClipMatcherService.matchFiles(
        scannedFiles: [ScannedFile(videoPath), ScannedFile(xmlPath)],
        log: log,
        targetCamera: 'A',
      );

      final videoProp = report.proposals.firstWhere((p) => !p.isCompanionFile);
      final xmlProp = report.proposals.firstWhere((p) => p.isCompanionFile);

      expect(videoProp.companionFilePath, equals(xmlPath));
      expect(xmlProp.companionFilePath, equals(videoPath));
    });

    test('Unmatched clip with companion XML preserves bidirectional companionFilePath and creates companion proposal', () {
      final emptyLog = ShootingLog(
        metadata: ShootingLogMetadata.empty(),
        records: [],
      );

      final videoPath = '/media/A001C005.MOV';
      final xmlPath = '/media/A001C005.XML';

      final report = ClipMatcherService.matchFiles(
        scannedFiles: [ScannedFile(videoPath), ScannedFile(xmlPath)],
        log: emptyLog,
        targetCamera: 'A',
      );

      expect(report.proposals.length, equals(2));
      final videoProp = report.proposals.firstWhere((p) => !p.isCompanionFile);
      final xmlProp = report.proposals.firstWhere((p) => p.isCompanionFile);

      expect(videoProp.status, equals(ProposalStatus.unmatchedClip));
      expect(videoProp.companionFilePath, equals(xmlPath));

      expect(xmlProp.status, equals(ProposalStatus.unmatchedClip));
      expect(xmlProp.isCompanionFile, isTrue);
      expect(xmlProp.companionFilePath, equals(videoPath));
    });
  });
}
