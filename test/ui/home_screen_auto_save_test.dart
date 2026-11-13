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
        initialStudioMode: false,
      ),
    );
  }

  group('HomeScreen Studio Slate Auto-Save Tests', () {
    testWidgets('editing slate field updates metadata instantly and badge never sticks on Guardando', (tester) async {
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

      // Navigate to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Enter Modo Estudio
      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final saveButtonFinder = find.byKey(const ValueKey('studio_save_slate_button'));
      expect(saveButtonFinder, findsOneWidget);
      expect(find.descendant(of: saveButtonFinder, matching: find.text('Guardado')), findsOneWidget);

      // Edit Scene field
      final sceneFieldFinder = find.byKey(const ValueKey('studio_slate_scene_field'));
      expect(sceneFieldFinder, findsOneWidget);
      await tester.enterText(sceneFieldFinder, '42');
      await tester.pump(); // Trigger onChanged

      // In-memory update is synchronous: badge reads 'Guardado' right away
      // (well under 100 ms), never 'Guardando...'.
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.descendant(of: saveButtonFinder, matching: find.text('Guardando...')), findsNothing);
      expect(find.descendant(of: saveButtonFinder, matching: find.text('Guardado')), findsOneWidget);
      final earlyState = tester.state(find.byType(HomeScreen)) as dynamic;
      expect((earlyState.project as RenombrataProject).log.records.first.scene, equals('42'));

      // Let the deferred (coalesced) preview refresh run.
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      // Verify records in project updated automatically
      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final updatedProject = homeState.project as RenombrataProject;
      expect(updatedProject.log.records.length, equals(1));
      expect(updatedProject.log.records.first.scene, equals('42'));

      // Verify silent save: floating notification banner was NOT displayed
      expect(find.text('Metadatos de claqueta actualizados'), findsNothing);

      // Verify button returns to 'Guardado'
      expect(find.descendant(of: saveButtonFinder, matching: find.text('Guardado')), findsOneWidget);
    });

    testWidgets('manual click on Guardado button shows notification banner', (tester) async {
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

      final sceneFieldFinder = find.byKey(const ValueKey('studio_slate_scene_field'));
      await tester.enterText(sceneFieldFinder, '99');
      await tester.pump();

      // Tap manual save button directly
      final saveButtonFinder = find.byKey(const ValueKey('studio_save_slate_button'));
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      // Manual save displays notification banner
      expect(find.text('Metadatos de claqueta actualizados'), findsOneWidget);
    });

    testWidgets('editing slate fields multiple times updates the existing record without creating duplicate/ghost takes', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        showChapter: true,
        showPlane: true,
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

      final sceneFieldFinder = find.byKey(const ValueKey('studio_slate_scene_field'));
      final takeFieldFinder = find.byKey(const ValueKey('studio_slate_take_field'));
      final planeFieldFinder = find.byKey(const ValueKey('studio_slate_plane_field'));
      final chapterFieldFinder = find.byKey(const ValueKey('studio_slate_chapter_field'));

      // 1. First edit: scene -> '10'
      await tester.enterText(sceneFieldFinder, '10');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      var homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      var currentProj = homeState.project as RenombrataProject;
      expect(currentProj.log.records.length, equals(1));
      expect(currentProj.log.records.first.scene, equals('10'));
      final recordId = currentProj.log.records.first.id;

      // 2. Second edit: scene -> '11'
      await tester.enterText(sceneFieldFinder, '11');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      currentProj = homeState.project as RenombrataProject;
      expect(currentProj.log.records.length, equals(1), reason: 'Must not create a duplicate record when changing scene');
      expect(currentProj.log.records.first.scene, equals('11'));
      expect(currentProj.log.records.first.id, equals(recordId), reason: 'Must preserve the same record ID');

      // 3. Third edit: take -> '2'
      await tester.enterText(takeFieldFinder, '2');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      currentProj = homeState.project as RenombrataProject;
      expect(currentProj.log.records.length, equals(1), reason: 'Must not create a duplicate record when changing take');
      expect(currentProj.log.records.first.take, equals('2'));
      expect(currentProj.log.records.first.id, equals(recordId));

      // 4. Fourth edit: plane -> 'A'
      await tester.enterText(planeFieldFinder, 'A');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      currentProj = homeState.project as RenombrataProject;
      expect(currentProj.log.records.length, equals(1), reason: 'Must not create a duplicate record when changing plane');
      expect(currentProj.log.records.first.plane, equals('A'));
      expect(currentProj.log.records.first.id, equals(recordId));

      // 5. Fifth edit: chapter -> '5'
      await tester.enterText(chapterFieldFinder, '5');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();

      homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      currentProj = homeState.project as RenombrataProject;
      expect(currentProj.log.records.length, equals(1), reason: 'Must not create a duplicate record when changing chapter');
      expect(currentProj.log.records.first.chapter, equals('5'));
      expect(currentProj.log.records.first.scene, equals('11'));
      expect(currentProj.log.records.first.take, equals('2'));
      expect(currentProj.log.records.first.plane, equals('A'));
      expect(currentProj.log.records.first.id, equals(recordId));
    });
  });
}
