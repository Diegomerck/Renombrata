import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';

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

  group('HomeScreen - Undo / Revert Convention Text Overrides', () {
    testWidgets('applying matches and clicking Deshacer button restores previous report', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop = RenameProposal(
        originalFilePath: '/media/A001C001_260817AB.MP4',
        proposedFileName: 'ORIGINAL_PROPOSAL_001.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      // Switch to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Open convention editor
      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      // Initially Deshacer is disabled
      final deshacerFinder = find.widgetWithText(OutlinedButton, 'Deshacer');
      expect(deshacerFinder, findsOneWidget);
      OutlinedButton deshacerBtn = tester.widget<OutlinedButton>(deshacerFinder);
      expect(deshacerBtn.onPressed, isNull);

      // Enter convention text matching clip 001
      final textFields = find.byType(TextField);
      await tester.enterText(
        textFields.last,
        'PROD_01_01_T1_A001_D01_001_U1.MP4',
      );
      await tester.pump();

      // Apply matches
      final applyFinder = find.widgetWithText(FilledButton, 'Aplicar Coincidencias (1)');
      expect(applyFinder, findsOneWidget);
      await tester.tap(applyFinder);
      await tester.pumpAndSettle();

      // Proposal in report updated to applied convention name
      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final currentReport = homeState.report as DryRunReport;
      expect(currentReport.proposals.first.proposedFileName, equals('PROD_01_01_T1_A001_D01_001_U1.MP4'));
      expect(currentReport.proposals.first.status, equals(ProposalStatus.ready));

      // Deshacer button is now enabled
      deshacerBtn = tester.widget<OutlinedButton>(deshacerFinder);
      expect(deshacerBtn.onPressed, isNotNull);

      // Tap Deshacer
      await tester.tap(deshacerFinder);
      await tester.pumpAndSettle();

      // Verify report is restored to original proposal
      final restoredReport = homeState.report as DryRunReport;
      expect(restoredReport.proposals.first.proposedFileName, equals('ORIGINAL_PROPOSAL_001.MP4'));
      expect(restoredReport.proposals.first.status, equals(ProposalStatus.unmatchedClip));

      // Notification banner shows revert confirmation
      expect(find.text('Cambios de convención deshechos.'), findsOneWidget);

      // Deshacer button is disabled again
      deshacerBtn = tester.widget<OutlinedButton>(deshacerFinder);
      expect(deshacerBtn.onPressed, isNull);
    });

    testWidgets('Ctrl+Z keyboard shortcut restores previous report', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop = RenameProposal(
        originalFilePath: '/media/A001C001_260817AB.MP4',
        proposedFileName: 'ORIGINAL_PROPOSAL_001.MP4',
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

      final textFields = find.byType(TextField);
      await tester.enterText(
        textFields.last,
        'PROD_01_01_T1_A001_D01_001_U1.MP4',
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Aplicar Coincidencias (1)'));
      await tester.pumpAndSettle();
      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      expect((homeState.report as DryRunReport).proposals.first.proposedFileName, equals('PROD_01_01_T1_A001_D01_001_U1.MP4'));

      // Press Ctrl+Z
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Check restored
      final restoredReport = homeState.report as DryRunReport;
      expect(restoredReport.proposals.first.proposedFileName, equals('ORIGINAL_PROPOSAL_001.MP4'));
      expect(find.text('Cambios de convención deshechos.'), findsOneWidget);
    });
  });
}
