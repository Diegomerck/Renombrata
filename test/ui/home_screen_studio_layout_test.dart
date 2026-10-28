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

  Widget createHomeScreen({
    required RenombrataProject project,
    required DryRunReport report,
  }) {
    return MaterialApp(
      home: HomeScreen(
        initialProject: project,
        initialReport: report,
      ),
    );
  }

  group('HomeScreen - 3-Pane Studio Workspace Layout', () {
    testWidgets('toggles 3-pane studio workspace on and off via toolbar button', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001_260817AB.MP4',
        proposedFileName: 'A001C001_260817AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final prop2 = RenameProposal(
        originalFilePath: '/media/A001C002_260817AB.MP4',
        proposedFileName: 'A001C002_260817AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1, prop2]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      // Switch to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Initially in standard table view
      final studioToggleFinder = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      expect(studioToggleFinder, findsOneWidget);
      expect(find.text('Clips de Medios (2)'), findsNothing);

      // Tap Modo Estudio button
      await tester.tap(studioToggleFinder);
      await tester.pumpAndSettle();

      // Now in Studio Mode
      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      expect(homeState.isStudioMode, isTrue);
      expect(find.widgetWithText(OutlinedButton, 'Vista Tabla'), findsOneWidget);

      // Verify Column 1: Media list
      expect(find.text('Clips de Medios (2)'), findsOneWidget);
      expect(find.text('A001C001_260817AB.MP4'), findsWidgets);
      expect(find.text('A001C002_260817AB.MP4'), findsWidgets);

      // Verify Column 2: Center Inspector & Slate
      expect(find.text('Claqueta y Bitácora'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Guardar'), findsOneWidget);

      // Verify Column 3: Convention Editor
      expect(find.text('Convención de Texto'), findsOneWidget);

      // Toggle back to table view
      await tester.tap(find.widgetWithText(OutlinedButton, 'Vista Tabla'));
      await tester.pumpAndSettle();

      expect(homeState.isStudioMode, isFalse);
      expect(find.text('Clips de Medios (2)'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Modo Estudio'), findsOneWidget);
    });

    testWidgets('selecting a clip in Column 1 updates center inspector and highlighted convention line', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: [
          ShotRecord(
            chapter: '1',
            scene: '10',
            plane: 'P1',
            take: '1',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
            reel: 'A001',
          ),
          ShotRecord(
            chapter: '1',
            scene: '12',
            plane: 'P2',
            take: '3',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '002')],
            reel: 'A001',
          ),
        ]),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001_260817AB.MP4',
        proposedFileName: 'TODTA_D01_10_P1_T1.MP4',
        fileReel: 'A001',
        status: ProposalStatus.ready,
        associatedRecord: project.log.records[0],
      );

      final prop2 = RenameProposal(
        originalFilePath: '/media/A001C002_260817AB.MP4',
        proposedFileName: 'TODTA_D01_12_P2_T3.MP4',
        fileReel: 'A001',
        status: ProposalStatus.ready,
        associatedRecord: project.log.records[1],
      );

      final report = DryRunReport(proposals: [prop1, prop2]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Enter Modo Estudio
      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;

      // Automatically selects first clip
      expect(homeState.selectedStudioClip?.originalFilePath, equals('/media/A001C001_260817AB.MP4'));

      // Click second clip in Column 1
      await tester.tap(find.byKey(const ValueKey('studio_clip_1')));
      await tester.pumpAndSettle();

      // Center inspector updates to clip 2
      expect(homeState.selectedStudioClip?.originalFilePath, equals('/media/A001C002_260817AB.MP4'));
      expect(homeState.studioSceneController.text, equals('12'));
      expect(homeState.studioTakeController.text, equals('3'));
      expect(homeState.studioPlaneController.text, equals('P2'));
      expect(find.byKey(const ValueKey('studio_proposed_banner_text')), findsOneWidget);
    });

    testWidgets('editing and saving slate metadata in Studio mode updates project records', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop = RenameProposal(
        originalFilePath: '/media/A001C001_260817AB.MP4',
        proposedFileName: 'A001C001_260817AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      // Enter Escena and Toma in the center inspector
      final sceneFieldFinder = find.widgetWithText(TextField, 'Escena');
      expect(sceneFieldFinder, findsOneWidget);
      await tester.enterText(sceneFieldFinder, '25');

      final takeFieldFinder = find.widgetWithText(TextField, 'Toma');
      expect(takeFieldFinder, findsOneWidget);
      await tester.enterText(takeFieldFinder, '2');

      final planeFieldFinder = find.widgetWithText(TextField, 'Plano');
      expect(planeFieldFinder, findsOneWidget);
      await tester.enterText(planeFieldFinder, 'P1');

      // Tap Guardar
      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
      await tester.pumpAndSettle();

      // Check notification banner
      expect(find.text('Metadatos de claqueta actualizados'), findsOneWidget);

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final updatedProject = homeState.project as RenombrataProject;
      expect(updatedProject.log.records.length, equals(1));
      expect(updatedProject.log.records.first.scene, equals('25'));
      expect(updatedProject.log.records.first.take, equals('2'));
      expect(updatedProject.log.records.first.plane, equals('P1'));
    });
  });
}
