import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';

void main() {
  group('HomeScreen - Smart Reel Filtering & Quick-Paste', () {
    testWidgets('renders filter chips when multiple reels exist and filters table rows', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final propA001 = RenameProposal(
        originalFilePath: '/media/A001C001_260608ZY.MP4',
        proposedFileName: 'PROD_01_01_T1_A001_D01_U1.MP4',
        fileReel: 'A001',
        status: ProposalStatus.ready,
      );

      final propGpr1 = RenameProposal(
        originalFilePath: '/media/GPR1C001.MP4',
        proposedFileName: 'PROD_01_02_T1_GPR1_D01_U1.MP4',
        fileReel: 'GPR1',
        status: ProposalStatus.ready,
      );

      final report = DryRunReport(proposals: [propA001, propGpr1]);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            initialStudioMode: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Verify filter chips exist
      expect(find.widgetWithText(FilterChip, 'Todos (2)'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'A001 (1)'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'GPR1 (1)'), findsOneWidget);

      // Initially "Todos (2)" is selected, both rows visible
      expect(find.text('A001C001_260608ZY.MP4'), findsOneWidget);
      expect(find.text('GPR1C001.MP4'), findsOneWidget);

      // Tap A001 chip
      await tester.tap(find.widgetWithText(FilterChip, 'A001 (1)'));
      await tester.pumpAndSettle();

      // Only A001 row should be displayed
      expect(find.text('A001C001_260608ZY.MP4'), findsOneWidget);
      expect(find.text('GPR1C001.MP4'), findsNothing);

      // Tap GPR1 chip
      await tester.tap(find.widgetWithText(FilterChip, 'GPR1 (1)'));
      await tester.pumpAndSettle();

      // Only GPR1 row should be displayed
      expect(find.text('A001C001_260608ZY.MP4'), findsNothing);
      expect(find.text('GPR1C001.MP4'), findsOneWidget);

      // Tap Todos (2) to reset filter
      await tester.tap(find.widgetWithText(FilterChip, 'Todos (2)'));
      await tester.pumpAndSettle();

      // Both rows visible again
      expect(find.text('A001C001_260608ZY.MP4'), findsOneWidget);
      expect(find.text('GPR1C001.MP4'), findsOneWidget);
    });

    testWidgets('does not render filter chips when all clips belong to a single reel', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001.MP4',
        proposedFileName: 'PROD_01_01_T1_A001_D01_U1.MP4',
        fileReel: 'A001',
        status: ProposalStatus.ready,
      );

      final prop2 = RenameProposal(
        originalFilePath: '/media/A001C002.MP4',
        proposedFileName: 'PROD_01_01_T2_A001_D01_U1.MP4',
        fileReel: 'A001',
        status: ProposalStatus.ready,
      );

      final report = DryRunReport(proposals: [prop1, prop2]);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            initialStudioMode: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // No FilterChips when reel count is 1
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('A001C001.MP4'), findsOneWidget);
      expect(find.text('A001C002.MP4'), findsOneWidget);
    });

    testWidgets('toggling Editor de Texto opens convention editor pane and applies convention names', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001.MP4',
        proposedFileName: 'OLD_NAME_01.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final prop2 = RenameProposal(
        originalFilePath: '/media/A001C002.MP4',
        proposedFileName: 'OLD_NAME_02.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1, prop2]);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            initialStudioMode: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Find Editor de Texto toggle button
      final toggleButton = find.widgetWithText(OutlinedButton, 'Editor de Texto');
      expect(toggleButton, findsOneWidget);

      await tester.tap(toggleButton);
      await tester.pumpAndSettle();

      // Verify Convention Editor Pane is visible
      expect(find.text('Convención de Texto'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Ocultar Editor'), findsOneWidget);

      // Enter new convention names in the convention editor TextField
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.last, 'NEW_CONV_01\nNEW_CONV_02');
      await tester.pump();

      // Verify DataTable updated live with proposed names
      expect(find.text('NEW_CONV_01.MP4'), findsOneWidget);
      expect(find.text('NEW_CONV_02.MP4'), findsOneWidget);

      // Tap Aplicar Coincidencias (2)
      final applyButton = find.widgetWithText(FilledButton, 'Aplicar Coincidencias (2)');
      expect(applyButton, findsOneWidget);
      await tester.tap(applyButton);
      await tester.pumpAndSettle();

      // Verify notification banner was shown
      expect(find.text('2 nombres aplicados'), findsOneWidget);

      // Verify DataTable persists proposed names
      expect(find.text('NEW_CONV_01.MP4'), findsOneWidget);
      expect(find.text('NEW_CONV_02.MP4'), findsOneWidget);
    });
  });
}
