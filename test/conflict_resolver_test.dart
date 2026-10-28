// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/ui/conflict_resolver_dialog.dart';

void main() {
  group('ClipMatcherService manual overrides', () {
    test('conflicts resolve to ready and unmatchedClip when manual overrides are applied', () {
      final log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'PROD',
          date: '241010',
          unit: 'U1',
          day: 'D1',
          producer: 'PROD',
          production: 'TEST',
          location: 'LOC',
          audioFormat: 'WAV',
          frameRate: '23.98',
          videoCodec: 'ProRes',
          responsibleEngineer: 'ENG',
          ingestor: 'ING',
        ),
        records: [
          ShotRecord(
            id: 'rec_take_1',
            chapter: '1',
            scene: '10',
            plane: '1',
            take: '1',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '003')],
            reel: 'A001',
          ),
          ShotRecord(
            id: 'rec_take_2',
            chapter: '1',
            scene: '10',
            plane: '1',
            take: '2',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '004')],
            reel: 'A001',
          ),
        ],
      );

      final scannedFiles = [
        ScannedFile('/media/A001C003_241010_AAA.MOV'),
        ScannedFile('/media/A001C003_241010_BBB.MOV'),
      ];

      // 1. Without overrides -> Should detect conflict on clip 003
      final initialReport = ClipMatcherService.matchFiles(
        scannedFiles: scannedFiles,
        log: log,
        targetCamera: 'A',
      );

      expect(initialReport.hasConflicts, isTrue);
      final conflicts = initialReport.proposals.where((p) => p.status == ProposalStatus.conflict).toList();
      expect(conflicts.length, 2);

      // 2. With manual overrides: AAA is winner for take 1, BBB is omitted (null)
      final resolvedReport = ClipMatcherService.matchFiles(
        scannedFiles: scannedFiles,
        log: log,
        targetCamera: 'A',
        manualOverrides: {
          '/media/A001C003_241010_AAA.MOV': 'rec_take_1',
          '/media/A001C003_241010_BBB.MOV': null,
        },
      );

      expect(resolvedReport.hasConflicts, isFalse);

      final readyProposal = resolvedReport.proposals.firstWhere(
        (p) => p.originalFilePath == '/media/A001C003_241010_AAA.MOV',
      );
      expect(readyProposal.status, ProposalStatus.ready);
      expect(readyProposal.associatedRecord?.id, 'rec_take_1');
      expect(readyProposal.proposedFileName, contains('10_1_T1_A001'));

      final unmatchedProposal = resolvedReport.proposals.firstWhere(
        (p) => p.originalFilePath == '/media/A001C003_241010_BBB.MOV',
      );
      expect(unmatchedProposal.status, ProposalStatus.unmatchedClip);

      // Take 2 had no files, so it remains missing
      final missingTake2 = resolvedReport.proposals.firstWhere(
        (p) => p.status == ProposalStatus.missingFile,
      );
      expect(missingTake2.associatedRecord?.id, 'rec_take_2');

      // 3. Reassigning secondary candidate BBB to missing Take 2
      final reallocatedReport = ClipMatcherService.matchFiles(
        scannedFiles: scannedFiles,
        log: log,
        targetCamera: 'A',
        manualOverrides: {
          '/media/A001C003_241010_AAA.MOV': 'rec_take_1',
          '/media/A001C003_241010_BBB.MOV': 'rec_take_2',
        },
      );

      expect(reallocatedReport.hasConflicts, isFalse);
      expect(reallocatedReport.totalMissing, 0);
      expect(reallocatedReport.totalMatched, 2);

      final take2Proposal = reallocatedReport.proposals.firstWhere(
        (p) => p.originalFilePath == '/media/A001C003_241010_BBB.MOV',
      );
      expect(take2Proposal.status, ProposalStatus.ready);
      expect(take2Proposal.associatedRecord?.id, 'rec_take_2');
      expect(take2Proposal.proposedFileName, contains('10_1_T2_A001'));
    });
  });

  group('ConflictResolverDialog UI', () {
    testWidgets('renders conflict group, allows selecting winner and returns overrides', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final record1 = ShotRecord(
        id: 'rec_take_1',
        chapter: '1',
        scene: '14',
        plane: '1',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '005')],
        reel: 'A001',
      );

      final record2 = ShotRecord(
        id: 'rec_take_2',
        chapter: '1',
        scene: '14',
        plane: '1',
        take: '2',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '006')],
        reel: 'A001',
      );

      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty(),
        records: [record1, record2],
      );

      final report = DryRunReport(proposals: [
        RenameProposal(
          originalFilePath: '/media/A001C005_AAA.MOV',
          proposedFileName: 'PROD_14_1_1_A001_D1.MOV',
          associatedRecord: record1,
          status: ProposalStatus.conflict,
        ),
        RenameProposal(
          originalFilePath: '/media/A001C005_BBB.MOV',
          proposedFileName: 'PROD_14_1_1_A001_D1.MOV',
          associatedRecord: record1,
          status: ProposalStatus.conflict,
        ),
        RenameProposal(
          originalFilePath: null,
          proposedFileName: 'PROD_14_1_2_A001_D1.MOV',
          associatedRecord: record2,
          status: ProposalStatus.missingFile,
        ),
      ]);

      Map<String, String?>? returnedOverrides;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    returnedOverrides = await showDialog<Map<String, String?>>(
                      context: context,
                      builder: (ctx) => ConflictResolverDialog(
                        report: report,
                        log: log,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Dialog is displayed
      expect(find.text('Resolución de Conflictos de Medios'), findsOneWidget);
      expect(find.textContaining('Escena 14'), findsOneWidget);
      expect(find.text('A001C005_AAA.MOV'), findsOneWidget);
      expect(find.text('A001C005_BBB.MOV'), findsOneWidget);

      // Select candidate 2 (BBB) as the winner using its radio button
      final radios = find.byType(Radio<String>);
      expect(radios, findsNWidgets(2));
      await tester.tap(radios.at(1));
      await tester.pumpAndSettle();

      // Click "Guardar cambios"
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      // Verify returned overrides
      expect(returnedOverrides, isNotNull);
      expect(returnedOverrides!['/media/A001C005_BBB.MOV'], 'rec_take_1');
      expect(returnedOverrides!['/media/A001C005_AAA.MOV'], '__ALT__:rec_take_1'); // AAA became alternate (_ALT)
    });

    testWidgets('pre-populates existing overrides and allows resetting to conflict', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final record1 = ShotRecord(
        id: 'rec_take_1',
        chapter: '1',
        scene: '14',
        plane: '1',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '005')],
        reel: 'A001',
      );

      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty(),
        records: [record1],
      );

      final report = DryRunReport(proposals: [
        RenameProposal(
          originalFilePath: '/media/A001C005_AAA.MOV',
          proposedFileName: 'PROD_14_1_1_A001_D1.MOV',
          associatedRecord: record1,
          status: ProposalStatus.conflict,
        ),
        RenameProposal(
          originalFilePath: '/media/A001C005_BBB.MOV',
          proposedFileName: 'PROD_14_1_1_A001_D1.MOV',
          associatedRecord: record1,
          status: ProposalStatus.conflict,
        ),
      ]);

      // Suppose BBB was already chosen as winner, and AAA was omitted
      final initialOverrides = {
        '/media/A001C005_BBB.MOV': 'rec_take_1',
        '/media/A001C005_AAA.MOV': null,
      };

      Map<String, String?>? returnedOverrides;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    returnedOverrides = await showDialog<Map<String, String?>>(
                      context: context,
                      builder: (ctx) => ConflictResolverDialog(
                        report: report,
                        log: log,
                        currentOverrides: initialOverrides,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify that candidate 2 (BBB) is currently selected as winner
      final radios = tester.widgetList<Radio<String>>(find.byType(Radio<String>)).toList();
      expect(radios.length, 2);
      expect(radios[0].value, '/media/A001C005_AAA.MOV');
      expect(radios[0].groupValue, '/media/A001C005_BBB.MOV'); // Winner is BBB
      expect(radios[1].value, '/media/A001C005_BBB.MOV');
      expect(radios[1].groupValue, '/media/A001C005_BBB.MOV');

      // Click "Restablecer a conflicto"
      expect(find.text('Restablecer a conflicto'), findsOneWidget);
      await tester.tap(find.text('Restablecer a conflicto'));
      await tester.pumpAndSettle();

      // Check that radio selection is cleared (groupValue is null)
      final radiosAfterReset = tester.widgetList<Radio<String>>(find.byType(Radio<String>)).toList();
      expect(radiosAfterReset[0].groupValue, isNull);
      expect(radiosAfterReset[1].groupValue, isNull);

      // Click "Guardar cambios"
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      // Overrides should now be empty (restoring them to conflict)
      expect(returnedOverrides, isNotNull);
      expect(returnedOverrides!.containsKey('/media/A001C005_AAA.MOV'), isFalse);
      expect(returnedOverrides!.containsKey('/media/A001C005_BBB.MOV'), isFalse);
    });

    testWidgets('displays TC discrepancy warning badge and allows confirming candidate', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final record1 = ShotRecord(
        id: 'rec_take_1',
        chapter: '1',
        scene: '10',
        plane: '1',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
        reel: 'A007',
        tcIn: '10:00:00:00',
      );

      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty(),
        records: [record1],
      );

      final report = DryRunReport(proposals: [
        RenameProposal(
          originalFilePath: '/media/C0001.MP4',
          proposedFileName: 'PROD_10_1_1_A007_D1.MP4',
          associatedRecord: record1,
          status: ProposalStatus.conflict,
          fileTcIn: '09:04:22:00',
          fileTcOut: '09:05:22:00',
        ),
      ]);

      Map<String, String?>? returnedOverrides;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    returnedOverrides = await showDialog<Map<String, String?>>(
                      context: context,
                      builder: (ctx) => ConflictResolverDialog(
                        report: report,
                        log: log,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify TC In -> Out is rendered
      expect(find.textContaining('TC: 09:04:22:00 → 09:05:22:00'), findsOneWidget);

      // Verify TC Discrepancy warning badge is rendered
      expect(
        find.text('⚠ TC Discrepante: Bitácora (10:00:00:00) vs Archivo (09:04:22:00)'),
        findsOneWidget,
      );

      // Tap radio button to confirm candidate as target take
      final radio = find.byType(Radio<String>);
      expect(radio, findsOneWidget);
      await tester.tap(radio);
      await tester.pumpAndSettle();

      // Click "Guardar cambios"
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(returnedOverrides, isNotNull);
      expect(returnedOverrides!['/media/C0001.MP4'], 'rec_take_1');
    });

    testWidgets('groups multiple proposals sharing same reel and clip index in one conflict group', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final log = ShootingLog(
        metadata: ShootingLogMetadata.empty(),
        records: [],
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A007C001_261007OC.MP4',
        proposedFileName: 'A007C001_261007OC.MP4',
        fileReel: 'A007',
        status: ProposalStatus.conflict,
      );

      final prop2 = RenameProposal(
        originalFilePath: '/media/A007C001_ALT.MP4',
        proposedFileName: 'A007C001_ALT.MP4',
        fileReel: 'A007',
        status: ProposalStatus.conflict,
      );

      final report = DryRunReport(proposals: [prop1, prop2]);

      Map<String, String?>? returnedOverrides;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    returnedOverrides = await showDialog<Map<String, String?>>(
                      context: context,
                      builder: (ctx) => ConflictResolverDialog(
                        report: report,
                        log: log,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify both candidates are in the same conflict group
      expect(find.text('Resolución de Conflictos de Medios'), findsOneWidget);
      expect(find.text('1 conflicto'), findsOneWidget);
      expect(find.text('A007C001_261007OC.MP4'), findsOneWidget);
      expect(find.text('A007C001_ALT.MP4'), findsOneWidget);

      // Verify winner badge and alternate badge are displayed
      expect(find.text('Ganador / Principal'), findsOneWidget);
      expect(find.text('Alterno (_ALT)'), findsOneWidget);

      // Click "Guardar cambios"
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(returnedOverrides, isNotNull);
      expect(returnedOverrides!['/media/A007C001_261007OC.MP4'], '__PRIMARY__');
      expect(returnedOverrides!['/media/A007C001_ALT.MP4'], '__ALT__');
    });
  });
}
