import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
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

  group('HomeScreen - RTF Auto-Populate Convention Editor', () {
    testWidgets('importing RTF bitácora automatically populates convention editor and displays lines',
        (WidgetTester tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001_261027.MP4',
        proposedFileName: 'A001C001_261027.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );
      final prop2 = RenameProposal(
        originalFilePath: '/media/A001C002_261027.MP4',
        proposedFileName: 'A001C002_261027.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1, prop2]);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Open the convention editor pane
      final editorButton = find.widgetWithText(OutlinedButton, 'Editor de Texto');
      expect(editorButton, findsOneWidget);
      await tester.tap(editorButton);
      await tester.pumpAndSettle();

      // Create a temporary RTF file with convention lines
      final tempDir = Directory.systemTemp.createTempSync('rtf_test_');
      final tempRtfFile = File('${tempDir.path}/D01_test.rtf');
      const rtfContent =
          r'{\rtf1\ansi\deff0 {\fonttbl{\f0 Helvetica;}}\pard TODTA_2_13_P1_T1_A001_D01_1_U1\par TODTA_2_13_P1_T2_A001_D01_2_U1\par}';
      tempRtfFile.writeAsStringSync(rtfContent);

      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      // Drop RTF bitacora onto DropTarget
      final dropTargetFinder = find.byType(DropTarget);
      final dropTarget = tester.widget<DropTarget>(dropTargetFinder);

      await tester.runAsync(() async {
        dropTarget.onDragDone?.call(DropDoneDetails(
          files: [DropItemFile(tempRtfFile.path)],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ));
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      // Notification confirms RTF imported
      expect(find.textContaining('Bitácora importada'), findsOneWidget);

      // Verify convention editor TextField was auto-populated with extracted plain text
      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      final conventionTextField = textFields.firstWhere(
        (tf) => tf.controller != null && tf.controller!.text.contains('TODTA_2_13_P1_T1_A001_D01_1_U1'),
      );
      expect(conventionTextField.controller!.text, contains('TODTA_2_13_P1_T1_A001_D01_1_U1'));
      expect(conventionTextField.controller!.text, contains('TODTA_2_13_P1_T2_A001_D01_2_U1'));

      // Verify line inspection list items appear in the editor pane
      expect(find.textContaining('Línea 1:'), findsOneWidget);
      expect(find.textContaining('Línea 2:'), findsOneWidget);
      expect(find.textContaining('A001C001_261027.MP4'), findsWidgets);
      expect(find.textContaining('A001C002_261027.MP4'), findsWidgets);
    });
  });
}
