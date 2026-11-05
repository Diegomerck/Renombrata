import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/bitacora_editor_tab.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  void setupDesktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('Take Card & Studio Slate Simplification Tests', () {
    testWidgets('BitacoraEditorTab take rows render ONLY MOS and TF checkboxes', (tester) async {
      setupDesktop(tester);

      final record = ShotRecord(
        chapter: '1',
        scene: '10',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
        reel: 'A001',
        isMos: false,
        isTf: false,
      );

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: [record]),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BitacoraEditorTab(
              project: project,
              onProjectChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expand the take row notes/tier2
      await tester.tap(find.byTooltip('Expandir notas'));
      await tester.pumpAndSettle();

      // Verify MOS and TF checkboxes exist
      expect(find.byKey(ValueKey('${record.id}_is_mos')), findsOneWidget);
      expect(find.byKey(ValueKey('${record.id}_is_tf')), findsOneWidget);

      // Verify DS, FF, GPR, DR checkboxes do NOT exist
      expect(find.byKey(ValueKey('${record.id}_is_ds')), findsNothing);
      expect(find.byKey(ValueKey('${record.id}_is_ff')), findsNothing);
      expect(find.byKey(ValueKey('${record.id}_is_gpr')), findsNothing);
      expect(find.byKey(ValueKey('${record.id}_is_dr')), findsNothing);
    });

    testWidgets('Studio Slate in HomeScreen renders ONLY MOS and TF flag chips', (tester) async {
      setupDesktop(tester);
      SharedPreferences.setMockInitialValues({});

      final record = ShotRecord(
        chapter: '1',
        scene: '10',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
        reel: 'A001',
      );

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: [record]),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final proposal = RenameProposal(
        originalFilePath: '/media/A001C001_260817AB.MP4',
        proposedFileName: 'A001C001_260817AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.ready,
        associatedRecord: record,
      );

      final report = DryRunReport(proposals: [proposal]);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Renamer tab then Studio mode
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
        await tester.pumpAndSettle();
      }

      // Verify MOS and TF chips are present
      expect(find.byKey(const ValueKey('studio_flag_mos')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_flag_tf')), findsOneWidget);

      // Verify DS, FF, GPR, DR chips are NOT present
      expect(find.byKey(const ValueKey('studio_flag_ds')), findsNothing);
      expect(find.byKey(const ValueKey('studio_flag_ff')), findsNothing);
      expect(find.byKey(const ValueKey('studio_flag_gpr')), findsNothing);
      expect(find.byKey(const ValueKey('studio_flag_dr')), findsNothing);
    });
  });
}
