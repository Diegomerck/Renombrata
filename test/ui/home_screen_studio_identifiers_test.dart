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

  group('HomeScreen Studio Slate Identifiers & Convention Banner', () {
    testWidgets('selecting a clip populates Cap, Scene, Take, and all flags', (tester) async {
      setupDesktopWindow(tester);

      final record1 = ShotRecord(
        chapter: '04',
        scene: '12',
        plane: 'P1',
        take: '2',
        cameras: [
          CameraTakeRecord(cameraName: 'A', clipName: '001'),
        ],
        reel: 'A001',
        isMos: true,
        isTf: true,
        isDs: true,
        isFf: false,
        isGpr: false,
        isDr: false,
      );

      final project = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata(
            nomenclature: 'MNLDVDL',
            date: '260817',
            unit: 'U1',
            day: 'D01',
            producer: '',
            production: 'MANOLO',
            location: '',
            audioFormat: '',
            frameRate: '23.98',
            videoCodec: '',
            responsibleEngineer: '',
            ingestor: '',
          ),
          records: [record1],
        ),
        cameras: const [CameraConfig(name: 'A', type: CameraType.drivingShot)],
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001_260817AB.MP4',
        proposedFileName: 'MNLDVDL_04_12_P1_TF2_A001_D01_01_DS.MP4',
        fileReel: 'A001',
        associatedRecord: record1,
        status: ProposalStatus.ready,
      );

      final report = DryRunReport(proposals: [prop1]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      // Navigate to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Enter Modo Estudio
      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      expect(homeState.isStudioMode, isTrue);

      // Verify text controllers populated correctly
      expect(homeState.studioChapterController.text, equals('04'));
      expect(homeState.studioSceneController.text, equals('12'));
      expect(homeState.studioPlaneController.text, equals('P1'));
      expect(homeState.studioTakeController.text, equals('2'));

      // Verify state flags populated correctly
      expect(homeState.studioIsMos, isTrue);
      expect(homeState.studioIsTf, isTrue);

      // Verify the proposed banner displays the accurate Televisa / ViX convention
      final bannerFinder = find.byKey(const ValueKey('studio_proposed_banner_text'));
      expect(bannerFinder, findsOneWidget);
      final bannerText = tester.widget<Text>(bannerFinder).data;
      expect(bannerText, equals('MNLDVDL_04_12_P1_TF2_A001_D01_01_DS.MP4'));
    });

    testWidgets('toggling TF reactively updates the proposed banner with TF take prefix', (tester) async {
      setupDesktopWindow(tester);

      final record = ShotRecord(
        chapter: '01',
        scene: '20',
        plane: '1',
        take: '1',
        cameras: [
          CameraTakeRecord(cameraName: 'A', clipName: '001'),
        ],
        reel: 'A001',
        isMos: false,
        isTf: false,
      );

      final project = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata(
            nomenclature: 'SERIE',
            date: '260817',
            unit: 'U1',
            day: 'D01',
            producer: '',
            production: 'SERIE',
            location: '',
            audioFormat: '',
            frameRate: '23.98',
            videoCodec: '',
            responsibleEngineer: '',
            ingestor: '',
          ),
          records: [record],
        ),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop = RenameProposal(
        originalFilePath: '/media/A001C001_260817AB.MP4',
        proposedFileName: 'SERIE_01_20_1_T1_A001_D01_01_U1.MP4',
        fileReel: 'A001',
        associatedRecord: record,
        status: ProposalStatus.ready,
      );

      final report = DryRunReport(proposals: [prop]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final bannerFinder = find.byKey(const ValueKey('studio_proposed_banner_text'));
      expect(tester.widget<Text>(bannerFinder).data, equals('SERIE_01_20_1_T1_A001_D01_01_U1.MP4'));

      // Toggle TF on
      final tfChipFinder = find.byKey(const ValueKey('studio_flag_tf'));
      expect(tfChipFinder, findsOneWidget);
      await tester.tap(tfChipFinder);
      await tester.pumpAndSettle();

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      expect(homeState.studioIsTf, isTrue);
      expect(tester.widget<Text>(bannerFinder).data, equals('SERIE_01_20_1_TF1_A001_D01_01_U1.MP4'));

      // Toggle TF off
      await tester.tap(tfChipFinder);
      await tester.pumpAndSettle();

      expect(homeState.studioIsTf, isFalse);
      expect(tester.widget<Text>(bannerFinder).data, equals('SERIE_01_20_1_T1_A001_D01_01_U1.MP4'));
    });

    testWidgets('toggling special flags (DS, GPR, DR, FF) and editing Cap updates banner reactively', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata(
            nomenclature: 'TESTPROD',
            date: '260817',
            unit: 'U1',
            day: 'D01',
            producer: '',
            production: 'TESTPROD',
            location: '',
            audioFormat: '',
            frameRate: '23.98',
            videoCodec: '',
            responsibleEngineer: '',
            ingestor: '',
          ),
          records: [],
        ),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop = RenameProposal(
        originalFilePath: '/media/A001C001_260817AB.MP4',
        proposedFileName: 'TESTPROD_1_1_T1_A001_D01_01_U1.MP4',
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

      final bannerFinder = find.byKey(const ValueKey('studio_proposed_banner_text'));

      // 1. Edit Cap
      final capFieldFinder = find.widgetWithText(TextField, 'Cap');
      expect(capFieldFinder, findsOneWidget);
      await tester.enterText(capFieldFinder, '15');
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(bannerFinder).data, contains('_15_'));

      // 2. Toggle TF
      await tester.tap(find.byKey(const ValueKey('studio_flag_tf')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(bannerFinder).data, contains('_TF1_'));

      // 3. Special camera flags are no longer on the slate card
      expect(find.byKey(const ValueKey('studio_flag_ds')), findsNothing);
      expect(find.byKey(const ValueKey('studio_flag_dr')), findsNothing);
      expect(find.byKey(const ValueKey('studio_flag_ff')), findsNothing);
      expect(find.byKey(const ValueKey('studio_flag_gpr')), findsNothing);
    });

    testWidgets('selecting a clip sets text selection to the matching line in the convention editor', (tester) async {
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

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;

      // Populate convention text in the editor
      const line1 = 'PROD_01_10_T1_A001_D01_01_U1';
      const line2 = 'PROD_01_10_T2_A001_D01_02_U1';
      const editorText = '$line1\n$line2';

      homeState.conventionEditorController.text = editorText;
      homeState.onConventionTextChanged(editorText);
      await tester.pumpAndSettle();

      // Tap on second clip in the left media list
      final secondClipFinder = find.byKey(const ValueKey('studio_clip_1'));
      expect(secondClipFinder, findsOneWidget);
      await tester.tap(secondClipFinder);
      await tester.pumpAndSettle();

      // Check text selection in editor controller
      final selection = homeState.conventionEditorController.selection as TextSelection;
      expect(selection.isCollapsed, isFalse);

      final selectedSubstring = editorText.substring(selection.baseOffset, selection.extentOffset);
      expect(selectedSubstring, equals(line2));
    });

    testWidgets('saving studio slate updates ShotRecord with chapter and flags', (tester) async {
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

      // Enter slate fields
      await tester.enterText(find.widgetWithText(TextField, 'Cap'), '08');
      await tester.enterText(find.widgetWithText(TextField, 'Escena'), '42');
      await tester.enterText(find.widgetWithText(TextField, 'Toma'), '5');
      await tester.enterText(find.widgetWithText(TextField, 'Plano'), '2');

      // Toggle flags
      await tester.tap(find.byKey(const ValueKey('studio_flag_tf')));
      await tester.tap(find.byKey(const ValueKey('studio_flag_mos')));
      await tester.pumpAndSettle();

      // Tap Guardado button
      await tester.tap(find.byKey(const ValueKey('studio_save_slate_button')));
      await tester.pumpAndSettle();

      expect(find.text('Metadatos de claqueta actualizados'), findsOneWidget);

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final updatedProject = homeState.project as RenombrataProject;
      expect(updatedProject.log.records.length, equals(1));

      final saved = updatedProject.log.records.first;
      expect(saved.chapter, equals('08'));
      expect(saved.scene, equals('42'));
      expect(saved.take, equals('5'));
      expect(saved.plane, equals('2'));
      expect(saved.isTf, isTrue);
      expect(saved.isMos, isTrue);
    });
  });
}
