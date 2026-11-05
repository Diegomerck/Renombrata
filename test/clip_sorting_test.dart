import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/bitacora_editor_tab.dart';
import 'package:renombrata/src/ui/home_screen.dart';

void main() {
  group('Clip Sequence Bitácora Ordering Tests', () {
    test('RenombrataProject autoSortByClip default and JSON serialization', () {
      final projectDefault = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );
      expect(projectDefault.autoSortByClip, isTrue);

      final projectFalse = projectDefault.copyWith(autoSortByClip: false);
      expect(projectFalse.autoSortByClip, isFalse);

      final json = projectFalse.toJson();
      expect(json['autoSortByClip'], isFalse);

      final revived = RenombrataProject.fromJson(json);
      expect(revived.autoSortByClip, isFalse);
    });

    test('BitacoraEditorTab.sortRecordsByClip sorts correctly by clip number', () {
      final r1 = ShotRecord(
        chapter: '1',
        scene: '1',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: 'A001C003_260608ZY.MP4')],
        reel: 'A001',
        tcIn: '10:00:00:00',
      );
      final r2 = ShotRecord(
        chapter: '1',
        scene: '1',
        take: '2',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
        reel: 'A001',
        tcIn: '09:00:00:00',
      );
      final r3 = ShotRecord(
        chapter: '1',
        scene: '2',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '002')],
        reel: 'A001',
        tcIn: '09:30:00:00',
      );
      final rNoClip = ShotRecord(
        chapter: '1',
        scene: '3',
        take: '1',
        cameras: [],
        reel: 'A001',
      );

      final sorted = BitacoraEditorTab.sortRecordsByClip([r1, r2, r3, rNoClip], 'A');

      // Expect r2 (clip 1) -> r3 (clip 2) -> r1 (clip 3) -> rNoClip (fallback 999999)
      expect(sorted[0].take, equals('2')); // r2 (clip 001)
      expect(sorted[1].scene, equals('2')); // r3 (clip 002)
      expect(sorted[2].take, equals('1')); // r1 (clip 003)
      expect(sorted[3].scene, equals('3')); // rNoClip
    });

    testWidgets('saving Clip 2 and then Clip 1 with autoSortByClip: true orders Clip 1 first', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final metadata = ShootingLogMetadata.empty();
      final project = RenombrataProject(
        log: ShootingLog(metadata: metadata, records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
        autoSortByClip: true,
      );

      final propClip2 = RenameProposal(
        originalFilePath: '/media/A001C002_260608ZY.MP4',
        proposedFileName: 'PROJ_261019_10_A_T2_A001_D1_U1.MP4',
        fileTcIn: '10:00:00:00',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final propClip1 = RenameProposal(
        originalFilePath: '/media/A001C001_260608ZY.MP4',
        proposedFileName: 'PROJ_261019_10_A_T1_A001_D1_U1.MP4',
        fileTcIn: '09:00:00:00',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(
        proposals: [propClip2, propClip1],
      );

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

      // Open MediaPreviewDialog via Inspeccionar Lote
      final inspectButton = find.widgetWithText(OutlinedButton, 'Inspeccionar Lote (2)');
      expect(inspectButton, findsOneWidget);
      await tester.tap(inspectButton);
      await tester.pumpAndSettle();

      // Fill and save Clip 2 as Scene 1, Take 2
      final sceneField = find.widgetWithText(TextField, 'Escena');
      await tester.enterText(sceneField, '1');
      final takeField = find.widgetWithText(TextField, 'Toma');
      await tester.enterText(takeField, '2');
      await tester.pumpAndSettle();

      final saveButton = find.widgetWithText(FilledButton, 'Guardar y Siguiente (Enter ➔)');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Now on Clip 1, fill and save as Scene 1, Take 1
      await tester.enterText(sceneField, '1');
      await tester.enterText(takeField, '1');
      await tester.pumpAndSettle();

      final saveFinalButton = find.widgetWithText(FilledButton, 'Guardar y Finalizar (Enter ➔)');
      await tester.tap(saveFinalButton);
      await tester.pumpAndSettle();

      // Switch to Bitácora Digital tab
      await tester.tap(find.text('Bitácora Digital'));
      await tester.pumpAndSettle();

      // Check Bitácora order in HomeState: Take 1 should be first, Take 2 second
      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final savedRecords = homeState.project.log.records as List<ShotRecord>;
      expect(savedRecords.length, equals(2));
      expect(savedRecords[0].take, equals('1'));
      expect(savedRecords[1].take, equals('2'));
    });

    testWidgets('saving Clip 2 and then Clip 1 with autoSortByClip: false preserves manual order', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final metadata = ShootingLogMetadata.empty();
      final project = RenombrataProject(
        log: ShootingLog(metadata: metadata, records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
        autoSortByClip: false,
      );

      final propClip2 = RenameProposal(
        originalFilePath: '/media/A001C002_260608ZY.MP4',
        proposedFileName: 'PROJ_261019_10_A_T2_A001_D1_U1.MP4',
        fileTcIn: '10:00:00:00',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final propClip1 = RenameProposal(
        originalFilePath: '/media/A001C001_260608ZY.MP4',
        proposedFileName: 'PROJ_261019_10_A_T1_A001_D1_U1.MP4',
        fileTcIn: '09:00:00:00',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(
        proposals: [propClip2, propClip1],
      );

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

      // Open MediaPreviewDialog via Inspeccionar Lote
      final inspectButton = find.widgetWithText(OutlinedButton, 'Inspeccionar Lote (2)');
      expect(inspectButton, findsOneWidget);
      await tester.tap(inspectButton);
      await tester.pumpAndSettle();

      // Ensure auto-ordenar toggle is false
      final autoSortToggle = find.widgetWithText(SwitchListTile, 'Auto-ordenar bitácora por clip');
      expect(tester.widget<SwitchListTile>(autoSortToggle).value, isFalse);

      // Save Clip 2 as Toma 2
      final sceneField = find.widgetWithText(TextField, 'Escena');
      await tester.enterText(sceneField, '1');
      final takeField = find.widgetWithText(TextField, 'Toma');
      await tester.enterText(takeField, '2');
      await tester.pumpAndSettle();

      final saveButton = find.widgetWithText(FilledButton, 'Guardar y Siguiente (Enter ➔)');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Save Clip 1 as Toma 1
      await tester.enterText(sceneField, '1');
      await tester.enterText(takeField, '1');
      await tester.pumpAndSettle();

      final saveFinalButton = find.widgetWithText(FilledButton, 'Guardar y Finalizar (Enter ➔)');
      await tester.tap(saveFinalButton);
      await tester.pumpAndSettle();

      // Switch to Bitácora Digital tab
      await tester.tap(find.widgetWithText(Tab, 'Bitácora Digital'));
      await tester.pumpAndSettle();

      // Dismiss any lingering SnackBar from dialog completion
      ScaffoldMessenger.of(tester.element(find.byType(HomeScreen))).clearSnackBars();
      await tester.pumpAndSettle();

      // Check order before manual reorder: Clip 2 was saved first so index 0 = Toma 2, index 1 = Toma 1
      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final savedRecordsBefore = homeState.project.log.records as List<ShotRecord>;
      expect(savedRecordsBefore.length, equals(2));
      expect(savedRecordsBefore[0].take, equals('2'));
      expect(savedRecordsBefore[1].take, equals('1'));

      // Verify the manual reorder button "Reordenar por Clip" exists and tap it
      final reorderButton = find.widgetWithText(OutlinedButton, 'Reordenar por Clip');
      expect(reorderButton, findsOneWidget);

      await tester.tap(reorderButton);
      await tester.pumpAndSettle();

      // After manual reorder, records must be sorted: Take 1 first, Take 2 second
      final savedRecordsAfter = homeState.project.log.records as List<ShotRecord>;
      expect(savedRecordsAfter[0].take, equals('1'));
      expect(savedRecordsAfter[1].take, equals('2'));
    });
  });
}
