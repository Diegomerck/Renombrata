import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      home: HomeScreen(initialProject: project, initialReport: report),
    );
  }

  group('Convention Editor & Line Numbered Gutter Bi-directional Sync', () {
    testWidgets(
      'Gutter renders line numbers matching lines in editor and highlights active clip line',
      (tester) async {
        setupDesktopWindow(tester);
        SharedPreferences.setMockInitialValues({});

        final project = RenombrataProject(
          showChapter: true,
          showPlane: true,
          log: ShootingLog(
            metadata: ShootingLogMetadata.empty().copyWith(
              production: 'MNBOENC',
              nomenclature: 'MNBOENC',
              date: '2026-06-08',
              day: '1',
              unit: '3',
            ),
            records: [],
          ),
          defaultReel: 'A001',
          activeCamera: 'A',
        );

        final prop1 = RenameProposal(
          originalFilePath: '/media/A001C001_260608AB.MP4',
          proposedFileName: 'A001C001_260608AB.MP4',
          fileReel: 'A001',
          status: ProposalStatus.unmatchedClip,
        );

        final prop2 = RenameProposal(
          originalFilePath: '/media/A001C002_260608AB.MP4',
          proposedFileName: 'A001C002_260608AB.MP4',
          fileReel: 'A001',
          status: ProposalStatus.unmatchedClip,
        );

        final prop3 = RenameProposal(
          originalFilePath: '/media/A001C003_260608AB.MP4',
          proposedFileName: 'A001C003_260608AB.MP4',
          fileReel: 'A001',
          status: ProposalStatus.unmatchedClip,
        );

        final report = DryRunReport(proposals: [prop1, prop2, prop3]);

        await tester.pumpWidget(
          createHomeScreen(project: project, report: report),
        );
        await tester.pumpAndSettle();

        // Switch to Renombrador de Medios tab
        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        // Enter Modo Estudio
        final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
        if (studioBtn.evaluate().isNotEmpty) {
          await tester.tap(studioBtn);
          await tester.pumpAndSettle();
        }

        // Open the convention editor pane if not visible
        if (find.text('Convención de Texto').evaluate().isEmpty) {
          await tester.tap(
            find.widgetWithText(OutlinedButton, 'Editor de Texto'),
          );
          await tester.pumpAndSettle();
        }

        // Enter 3 lines into the convention editor field
        final editorField = find.byKey(
          const ValueKey('studio_convention_editor_field'),
        );
        expect(editorField, findsOneWidget);

        await tester.enterText(
          editorField,
          'MNBOENC_080626_17_11_T1_A001_1_D1_U3\nMNBOENC_080626_17_12_T1_A001_2_D1_U3\nMNBOENC_080626_17_13_T1_A001_3_D1_U3',
        );
        await tester.pumpAndSettle();

        // Verify line numbers in gutter
        expect(
          find.byKey(const ValueKey('gutter_line_number_1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('gutter_line_number_2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('gutter_line_number_3')),
          findsOneWidget,
        );

        // Select Clip 2 from the media list
        await tester.tap(find.byKey(const ValueKey('studio_clip_1')));
        await tester.pumpAndSettle();

        // Verify line 2 in gutter has active highlight
        expect(
          find.byKey(const ValueKey('gutter_line_active_2')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Editing Slate Card fields automatically updates Convention Editor line in real time',
      (tester) async {
        setupDesktopWindow(tester);
        SharedPreferences.setMockInitialValues({});

        final project = RenombrataProject(
          showChapter: true,
          showPlane: true,
          log: ShootingLog(
            metadata: ShootingLogMetadata.empty().copyWith(
              production: 'MNBOENC',
              nomenclature: 'MNBOENC',
              date: '2026-06-08',
              day: '1',
              unit: '3',
            ),
            records: [],
          ),
          defaultReel: 'A001',
          activeCamera: 'A',
        );

        final prop1 = RenameProposal(
          originalFilePath: '/media/A001C001_260608AB.MP4',
          proposedFileName: 'A001C001_260608AB.MP4',
          fileReel: 'A001',
          status: ProposalStatus.unmatchedClip,
        );

        final report = DryRunReport(proposals: [prop1]);

        await tester.pumpWidget(
          createHomeScreen(project: project, report: report),
        );
        await tester.pumpAndSettle();

        // Switch to Renombrador de Medios tab
        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        // Enter Modo Estudio
        final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
        if (studioBtn.evaluate().isNotEmpty) {
          await tester.tap(studioBtn);
          await tester.pumpAndSettle();
        }

        // Select Clip 1
        await tester.tap(find.byKey(const ValueKey('studio_clip_0')));
        await tester.pumpAndSettle();

        // Enter values in Slate Card fields
        final capField = find.byKey(
          const ValueKey('studio_slate_chapter_field'),
        );
        final sceneField = find.byKey(
          const ValueKey('studio_slate_scene_field'),
        );
        final takeField = find.byKey(const ValueKey('studio_slate_take_field'));
        final reelField = find.byKey(const ValueKey('studio_slate_reel_field'));

        expect(capField, findsOneWidget);
        expect(sceneField, findsOneWidget);
        expect(takeField, findsOneWidget);
        expect(reelField, findsOneWidget);

        await tester.enterText(capField, '17');
        await tester.pumpAndSettle();

        await tester.enterText(sceneField, '11');
        await tester.pumpAndSettle();

        await tester.enterText(takeField, '1');
        await tester.pumpAndSettle();

        await tester.enterText(reelField, 'A001');
        await tester.pumpAndSettle();

        final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
        final editorController =
            homeState.conventionEditorController as TextEditingController;

        // Expect Convention Editor line to match generated convention
        expect(
          editorController.text.trim(),
          equals('MNBOENC_080626_17_11_T1_A001_1_D1_U3'),
        );

        // Verify log has the updated record
        final proj = homeState.project as RenombrataProject;
        expect(proj.log.records.isNotEmpty, isTrue);
        final rec = proj.log.records.first;
        expect(rec.chapter, equals('17'));
        expect(rec.scene, equals('11'));
        expect(rec.take, equals('1'));
        expect(rec.reel, equals('A001'));
      },
    );

    testWidgets(
      'Editing Convention Editor line synchronizes to Slate Card and ShootingLog',
      (tester) async {
        setupDesktopWindow(tester);
        SharedPreferences.setMockInitialValues({});

        final project = RenombrataProject(
          showChapter: true,
          showPlane: false,
          log: ShootingLog(
            metadata: ShootingLogMetadata.empty().copyWith(
              production: 'MNBOENC',
              nomenclature: 'MNBOENC',
              date: '2026-06-08',
              day: '1',
              unit: '3',
            ),
            records: [],
          ),
          defaultReel: 'A001',
          activeCamera: 'A',
        );

        final prop1 = RenameProposal(
          originalFilePath: '/media/A001C001_260608AB.MP4',
          proposedFileName: 'A001C001_260608AB.MP4',
          fileReel: 'A001',
          status: ProposalStatus.unmatchedClip,
        );

        final report = DryRunReport(proposals: [prop1]);

        await tester.pumpWidget(
          createHomeScreen(project: project, report: report),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
        if (studioBtn.evaluate().isNotEmpty) {
          await tester.tap(studioBtn);
          await tester.pumpAndSettle();
        }

        // Select Clip 1
        await tester.tap(find.byKey(const ValueKey('studio_clip_0')));
        await tester.pumpAndSettle();

        // Enter valid convention line in Convention Editor
        final editorField = find.byKey(
          const ValueKey('studio_convention_editor_field'),
        );
        await tester.enterText(
          editorField,
          'MNBOENC_080626_22_35_T2_A001_1_D1_U3',
        );
        await tester.pumpAndSettle();

        final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
        final capController =
            homeState.studioChapterController as TextEditingController;
        final sceneController =
            homeState.studioSceneController as TextEditingController;
        final takeController =
            homeState.studioTakeController as TextEditingController;
        final reelController =
            homeState.studioReelController as TextEditingController;

        expect(capController.text, equals('22'));
        expect(sceneController.text, equals('35'));
        expect(takeController.text, equals('2'));
        expect(reelController.text, equals('001'));
      },
    );

    testWidgets(
      'Arbitrary invalid text like TEST is rejected and does not map to rename proposals',
      (tester) async {
        setupDesktopWindow(tester);
        SharedPreferences.setMockInitialValues({});

        final project = RenombrataProject(
          showChapter: true,
          showPlane: false,
          log: ShootingLog(
            metadata: ShootingLogMetadata.empty().copyWith(
              production: 'MNBOENC',
              nomenclature: 'MNBOENC',
              date: '2026-06-08',
              day: '1',
              unit: '3',
            ),
            records: [],
          ),
          defaultReel: 'A001',
          activeCamera: 'A',
        );

        final prop1 = RenameProposal(
          originalFilePath: '/media/A001C001_260608AB.MP4',
          proposedFileName: 'ORIGINAL_PROPOSAL.MP4',
          fileReel: 'A001',
          status: ProposalStatus.unmatchedClip,
        );

        final report = DryRunReport(proposals: [prop1]);

        await tester.pumpWidget(
          createHomeScreen(project: project, report: report),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
        if (studioBtn.evaluate().isNotEmpty) {
          await tester.tap(studioBtn);
          await tester.pumpAndSettle();
        }

        // Type arbitrary random string "TEST" into convention editor
        final editorField = find.byKey(
          const ValueKey('studio_convention_editor_field'),
        );
        await tester.enterText(editorField, 'TEST');
        await tester.pumpAndSettle();

        // Verify status list flags unrecognized convention format
        expect(
          find.textContaining('Formato de convención no reconocido'),
          findsOneWidget,
        );

        final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
        final overrides = homeState.livePastedOverrides as Map<String, String>;

        // Ensure "TEST" was NOT approved or mapped as an override
        expect(overrides.containsKey('/media/A001C001_260608AB.MP4'), isFalse);
      },
    );

    testWidgets('Reel persistence preserves reel across clip navigation', (
      tester,
    ) async {
      setupDesktopWindow(tester);
      SharedPreferences.setMockInitialValues({});

      final project = RenombrataProject(
        showChapter: false,
        showPlane: false,
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(
            production: 'PROD',
            nomenclature: 'PROD',
            date: '2026-06-08',
          ),
          records: [],
        ),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001_260608AB.MP4',
        proposedFileName: 'A001C001_260608AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final prop2 = RenameProposal(
        originalFilePath: '/media/A001C002_260608AB.MP4',
        proposedFileName: 'A001C002_260608AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1, prop2]);

      await tester.pumpWidget(
        createHomeScreen(project: project, report: report),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
        await tester.pumpAndSettle();
      }

      // Select Clip 1
      await tester.tap(find.byKey(const ValueKey('studio_clip_0')));
      await tester.pumpAndSettle();

      // Modify Reel on Clip 1 to A005
      final reelField = find.byKey(const ValueKey('studio_slate_reel_field'));
      await tester.enterText(reelField, 'A005');
      await tester.pumpAndSettle();

      // Navigate to Clip 2
      await tester.tap(find.byKey(const ValueKey('studio_clip_1')));
      await tester.pumpAndSettle();

      // Reel on Clip 2 should have persisted A005
      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final reelController =
          homeState.studioReelController as TextEditingController;
      expect(reelController.text, equals('A005'));
    });

    testWidgets(
      'Clip #2 remains at position #2 when edited in Studio Mode and updates Line 2 in editor',
      (tester) async {
        setupDesktopWindow(tester);
        SharedPreferences.setMockInitialValues({});

        final project = RenombrataProject(
          showChapter: true,
          showPlane: false,
          log: ShootingLog(
            metadata: ShootingLogMetadata.empty().copyWith(
              production: 'TEST',
              nomenclature: 'TEST',
              date: '2026-06-08',
              day: '1',
              unit: '1',
            ),
            records: [],
          ),
          defaultReel: 'A001',
          activeCamera: 'A',
        );

        final prop1 = RenameProposal(
          originalFilePath: '/media/A001C001_260608AB.MP4',
          proposedFileName: 'A001C001_260608AB.MP4',
          fileReel: 'A001',
          status: ProposalStatus.unmatchedClip,
        );
        final prop2 = RenameProposal(
          originalFilePath: '/media/A001C002_260608AB.MP4',
          proposedFileName: 'A001C002_260608AB.MP4',
          fileReel: 'A001',
          status: ProposalStatus.unmatchedClip,
        );
        final prop3 = RenameProposal(
          originalFilePath: '/media/A001C003_260608AB.MP4',
          proposedFileName: 'A001C003_260608AB.MP4',
          fileReel: 'A001',
          status: ProposalStatus.unmatchedClip,
        );

        final report = DryRunReport(proposals: [prop1, prop2, prop3]);

        await tester.pumpWidget(
          createHomeScreen(project: project, report: report),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
        if (studioBtn.evaluate().isNotEmpty) {
          await tester.tap(studioBtn);
          await tester.pumpAndSettle();
        }

        // Select Clip 2 (index 1)
        await tester.tap(find.byKey(const ValueKey('studio_clip_1')));
        await tester.pumpAndSettle();

        // Edit scene to 25
        final sceneField = find.byKey(const ValueKey('studio_slate_scene_field'));
        await tester.enterText(sceneField, '25');
        await tester.pumpAndSettle();

        final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
        final editorController =
            homeState.conventionEditorController as TextEditingController;
        final lines = editorController.text.split('\n');

        // Clip 2 must update Line 2 (index 1), keeping Line 1 empty
        expect(lines.length, greaterThanOrEqualTo(2));
        expect(lines[0], equals(''));
        expect(lines[1], contains('_25_'));

        // Clip 2 must remain at position 1 in _studioMediaClips
        final mediaClips = homeState.studioMediaClips as List<RenameProposal>;
        expect(mediaClips[1].originalFilePath, equals('/media/A001C002_260608AB.MP4'));
        expect(homeState.selectedStudioClip?.originalFilePath, equals('/media/A001C002_260608AB.MP4'));
      },
    );

    testWidgets(
      'Studio Slate Card displays Escena before Capitulo when bitacoraElementOrder is [escena, capitulo, toma]',
      (tester) async {
        setupDesktopWindow(tester);
        SharedPreferences.setMockInitialValues({});

        final project = RenombrataProject(
          bitacoraElementOrder: const ['escena', 'capitulo', 'toma'],
          showChapter: true,
          showPlane: false,
          log: ShootingLog(
            metadata: ShootingLogMetadata.empty().copyWith(
              production: 'TEST',
              nomenclature: 'TEST',
              date: '2026-06-08',
            ),
            records: [],
          ),
          defaultReel: 'A001',
          activeCamera: 'A',
        );

        final prop1 = RenameProposal(
          originalFilePath: '/media/A001C001_260608AB.MP4',
          proposedFileName: 'A001C001_260608AB.MP4',
          fileReel: 'A001',
          status: ProposalStatus.unmatchedClip,
        );

        final report = DryRunReport(proposals: [prop1]);

        await tester.pumpWidget(
          createHomeScreen(project: project, report: report),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
        if (studioBtn.evaluate().isNotEmpty) {
          await tester.tap(studioBtn);
          await tester.pumpAndSettle();
        }

        // Select Clip 1
        await tester.tap(find.byKey(const ValueKey('studio_clip_0')));
        await tester.pumpAndSettle();

        final sceneFinder = find.byKey(const ValueKey('studio_slate_scene_field'));
        final capFinder = find.byKey(const ValueKey('studio_slate_chapter_field'));

        expect(sceneFinder, findsOneWidget);
        expect(capFinder, findsOneWidget);

        final sceneX = tester.getTopLeft(sceneFinder).dx;
        final capX = tester.getTopLeft(capFinder).dx;

        // Escena must appear before Capitulo on screen
        expect(sceneX, lessThan(capX));
      },
    );

    testWidgets(
      'Multi-camera take linking links Camera B clip to Camera A take in ShotRecord.cameras and populates controllers',
      (tester) async {
        setupDesktopWindow(tester);
        SharedPreferences.setMockInitialValues({});

        final existingRecord = ShotRecord(
          id: 'rec_10_1',
          chapter: '5',
          scene: '10',
          plane: '1',
          take: '1',
          reel: 'A001',
          cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: '002'),
          ],
        );

        final project = RenombrataProject(
          showChapter: true,
          showPlane: true,
          log: ShootingLog(
            metadata: ShootingLogMetadata.empty().copyWith(
              production: 'PROD',
              nomenclature: 'PROD',
              date: '2026-06-08',
              day: '1',
              unit: '1',
            ),
            records: [existingRecord],
          ),
          defaultReel: 'B001',
          activeCamera: 'B',
        );

        // Camera B clip
        final propB = RenameProposal(
          originalFilePath: '/media/B001C002_260608AB.MP4',
          proposedFileName: 'B001C002_260608AB.MP4',
          fileReel: 'B001',
          fileTcIn: '10:00:00:00',
          fileTcOut: '10:02:00:00',
          status: ProposalStatus.unmatchedClip,
        );

        final report = DryRunReport(proposals: [propB]);

        await tester.pumpWidget(
          createHomeScreen(project: project, report: report),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
        if (studioBtn.evaluate().isNotEmpty) {
          await tester.tap(studioBtn);
          await tester.pumpAndSettle();
        }

        // Select Camera B clip
        await tester.tap(find.byKey(const ValueKey('studio_clip_0')));
        await tester.pumpAndSettle();

        // Camera badge should show Camera B
        expect(find.byKey(const ValueKey('studio_camera_badge')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('studio_camera_badge')),
            matching: find.text('Cámara B'),
          ),
          findsOneWidget,
        );

        // Tap Vincular Toma button
        final linkButton = find.byKey(const ValueKey('studio_link_take_button'));
        expect(linkButton, findsOneWidget);
        await tester.tap(linkButton);
        await tester.pumpAndSettle();

        // Tap the take item for Esc. 10 - T1 (Cap. 5)
        final menuItem = find.text('Esc. 10 - T1 (Cap. 5)');
        expect(menuItem, findsOneWidget);
        await tester.tap(menuItem);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        final confirmBtn = find.byKey(const ValueKey('take_linker_confirm_button'));
        if (confirmBtn.evaluate().isNotEmpty) {
          await tester.tap(confirmBtn);
          await tester.pumpAndSettle();
        }

        final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
        final capCtrl = homeState.studioChapterController as TextEditingController;
        final sceneCtrl = homeState.studioSceneController as TextEditingController;
        final planeCtrl = homeState.studioPlaneController as TextEditingController;
        final takeCtrl = homeState.studioTakeController as TextEditingController;

        expect(capCtrl.text, equals('5'));
        expect(sceneCtrl.text, equals('10'));
        expect(planeCtrl.text, equals('1'));
        expect(takeCtrl.text, equals('1'));

        // Verify ShotRecord now has Camera B bound alongside Camera A
        final proj = homeState.project as RenombrataProject;
        final updatedRec = proj.log.records.firstWhere((r) => r.id == 'rec_10_1');
        final camB = updatedRec.cameras.firstWhere((c) => c.cameraName == 'B');
        expect(camB.clipName, equals('002'));
        expect(updatedRec.cameras.any((c) => c.cameraName == 'A'), isTrue);

        // Verify editor line 1 was updated with Camera B convention
        final editorController = homeState.conventionEditorController as TextEditingController;
        expect(editorController.text, contains('B001'));
      },
    );
  });
}
