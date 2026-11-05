import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/rtf_bitacora_parser_service.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:renombrata/src/ui/quick_paste_convention_dialog.dart';

void main() {
  void setupDesktopWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget createHomeScreen({
    required RenombrataProject project,
    required DryRunReport report,
  }) {
    return MaterialApp(
      home: HomeScreen(
        initialProject: project,
        initialReport: report,
        initialStudioMode: false,
      ),
    );
  }

  List<RenameProposal> createFiveClips() {
    return List.generate(5, (i) {
      final idx = i + 1;
      final pad = idx.toString().padLeft(3, '0');
      return RenameProposal(
        originalFilePath: '/media/A001C${pad}_260817AB.MP4',
        proposedFileName: 'ORIGINAL_PROPOSAL_$pad.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );
    });
  }

  const fiveLinesConventionText =
      'PROD_01_01_T1_A001_D01_001_U1\n'
      'PROD_01_02_T1_A001_D01_002_U1\n'
      'PROD_01_03_T1_A001_D01_003_U1\n'
      'PROD_01_04_T1_A001_D01_004_U1\n'
      'PROD_01_05_T1_A001_D01_005_U1';

  group('HomeScreen - Undo Convention Matches & Micronovela Parsing', () {
    testWidgets('Test 1: load 5 clips and paste matching convention text enables Aplicar Coincidencias (5)', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );
      final report = DryRunReport(proposals: createFiveClips());

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      // Switch to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Open convention editor pane
      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      // Enter matching convention text for the 5 clips
      final editorFinder = find.byKey(const ValueKey('studio_convention_editor_field'));
      expect(editorFinder, findsOneWidget);
      await tester.enterText(editorFinder, fiveLinesConventionText);
      await tester.pump();

      // Verify "Aplicar Coincidencias (5)" button is present and enabled
      final applyFinder = find.widgetWithText(FilledButton, 'Aplicar Coincidencias (5)');
      expect(applyFinder, findsOneWidget);
      final applyBtn = tester.widget<FilledButton>(applyFinder);
      expect(applyBtn.onPressed, isNotNull);
    });

    testWidgets('Test 2: tap Aplicar Coincidencias updates proposals in report', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );
      final report = DryRunReport(proposals: createFiveClips());

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      final editorFinder = find.byKey(const ValueKey('studio_convention_editor_field'));
      await tester.enterText(editorFinder, fiveLinesConventionText);
      await tester.pump();

      final applyFinder = find.widgetWithText(FilledButton, 'Aplicar Coincidencias (5)');
      await tester.tap(applyFinder);
      await tester.pumpAndSettle();

      // Verify all 5 proposals are updated with .MP4 extension and status ready
      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final currentReport = homeState.report as DryRunReport;
      for (int i = 0; i < 5; i++) {
        final pad = (i + 1).toString().padLeft(3, '0');
        final scenePad = (i + 1).toString().padLeft(2, '0');
        expect(
          currentReport.proposals[i].proposedFileName,
          equals('PROD_01_${scenePad}_T1_A001_D01_${pad}_U1.MP4'),
        );
        expect(currentReport.proposals[i].status, equals(ProposalStatus.ready));
      }

      // Check notification banner
      expect(find.text('5 nombres aplicados'), findsOneWidget);
    });

    testWidgets('Test 3: tap Deshacer reverts proposals, preserves green checkmarks, and re-enables Aplicar Coincidencias (5)', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );
      final report = DryRunReport(proposals: createFiveClips());

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      final editorFinder = find.byKey(const ValueKey('studio_convention_editor_field'));
      await tester.enterText(editorFinder, fiveLinesConventionText);
      await tester.pump();

      // Apply matches
      final applyFinder = find.widgetWithText(FilledButton, 'Aplicar Coincidencias (5)');
      await tester.tap(applyFinder);
      await tester.pumpAndSettle();

      // Tap Deshacer
      final deshacerFinder = find.widgetWithText(OutlinedButton, 'Deshacer');
      expect(deshacerFinder, findsOneWidget);
      await tester.tap(deshacerFinder);
      await tester.pumpAndSettle();

      // 1. Verify proposals revert to original names and unmatchedClip status
      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final restoredReport = homeState.report as DryRunReport;
      for (int i = 0; i < 5; i++) {
        final pad = (i + 1).toString().padLeft(3, '0');
        expect(
          restoredReport.proposals[i].proposedFileName,
          equals('ORIGINAL_PROPOSAL_$pad.MP4'),
        );
        expect(restoredReport.proposals[i].status, equals(ProposalStatus.unmatchedClip));
      }

      // 2. Notification confirmation
      expect(find.text('Cambios de convención deshechos.'), findsOneWidget);

      // 3. Verify all 5 line statuses remain green (Icons.check_circle) and NO conflicts
      expect(find.byIcon(Icons.check_circle), findsAtLeastNWidgets(5));
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      expect(find.textContaining('Conflicto en texto'), findsNothing);

      // 4. Verify "Aplicar Coincidencias (5)" is immediately enabled again
      expect(applyFinder, findsOneWidget);
      final applyBtn = tester.widget<FilledButton>(applyFinder);
      expect(applyBtn.onPressed, isNotNull);
    });

    testWidgets('Test 4: Micronovela convention lines parse correctly and match clips on disk by clip number and reel', (tester) async {
      setupDesktopWindow(tester);

      const microLine = 'MNBOENC_080626_17_11_T1_A001_1_D1_U3';

      // 1. Verify RtfBitacoraParserService parsing
      final entries = RtfBitacoraParserService.parseLines(microLine);
      expect(entries.length, equals(1));
      final entry = entries.first;
      expect(entry.nomenclature, equals('MNBOENC'));
      expect(entry.chapter, equals('17'));
      expect(entry.scene, equals('11'));
      expect(entry.plane, isNull);
      expect(entry.take, equals('T1'));
      expect(entry.reel, equals('A001'));
      expect(entry.clipIndex, equals('1'));
      expect(entry.day, equals('D1'));
      expect(entry.unit, equals('U3'));

      // 2. Verify QuickPasteConventionDialog parsing
      final parsed = QuickPasteConventionDialog.parsePastedLine(microLine, 1);
      expect(parsed.reel, equals('A001'));
      expect(parsed.clipNumber, equals(1));
      expect(parsed.hasExtractedClip, isTrue);

      // 3. Verify HomeScreen in-tab matching with disk clip A001C001_260608ZY.MP4
      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop = RenameProposal(
        originalFilePath: '/media/A001C001_260608ZY.MP4',
        proposedFileName: 'A001C001_260608ZY.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      final editorFinder = find.byKey(const ValueKey('studio_convention_editor_field'));
      await tester.enterText(editorFinder, microLine);
      await tester.pump();

      // Check matched status
      expect(find.byIcon(Icons.check_circle), findsAtLeastNWidgets(1));

      // Apply button enabled for 1 clip
      final applyFinder = find.widgetWithText(FilledButton, 'Aplicar Coincidencias (1)');
      expect(applyFinder, findsOneWidget);
      final applyBtn = tester.widget<FilledButton>(applyFinder);
      expect(applyBtn.onPressed, isNotNull);

      // Tap apply and check proposed file name
      await tester.tap(applyFinder);
      await tester.pumpAndSettle();

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final currentReport = homeState.report as DryRunReport;
      expect(
        currentReport.proposals.first.proposedFileName,
        equals('MNBOENC_080626_17_11_T1_A001_1_D1_U3.MP4'),
      );
      expect(currentReport.proposals.first.status, equals(ProposalStatus.ready));
    });
  });
}
