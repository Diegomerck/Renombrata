import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/app_settings.dart';
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
      home: HomeScreen(
        initialProject: project,
        initialReport: report,
        initialStudioMode: false,
      ),
    );
  }

  group('HomeScreen Studio View Settings Sync & Layout', () {
    testWidgets('Test 1: renamerPaneLayout media_right places Convention Editor on left and Media List on right', (tester) async {
      setupDesktopWindow(tester);

      SharedPreferences.setMockInitialValues({
        'app_settings': jsonEncode(const AppSettings(renamerPaneLayout: 'media_right').toJson()),
      });

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

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      expect(homeState.isStudioMode, isTrue);

      final editorFinder = find.text('Convención de Texto');
      final mediaListFinder = find.text('Clips de Medios (1)');

      expect(editorFinder, findsOneWidget);
      expect(mediaListFinder, findsOneWidget);

      final editorDx = tester.getTopLeft(editorFinder).dx;
      final mediaListDx = tester.getTopLeft(mediaListFinder).dx;

      expect(editorDx, lessThan(mediaListDx));
    });

    testWidgets('Test 2: showChapter false hides the Cap field', (tester) async {
      setupDesktopWindow(tester);

      SharedPreferences.setMockInitialValues({});

      final project = RenombrataProject(
        showChapter: false,
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

      expect(find.widgetWithText(TextField, 'Cap'), findsNothing);
      expect(find.widgetWithText(TextField, 'Escena'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Toma'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Plano'), findsOneWidget);
    });

    testWidgets('Test 3: showPlane false hides the Plano field', (tester) async {
      setupDesktopWindow(tester);

      SharedPreferences.setMockInitialValues({});

      final project = RenombrataProject(
        showPlane: false,
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

      expect(find.widgetWithText(TextField, 'Plano'), findsNothing);
      expect(find.widgetWithText(TextField, 'Cap'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Escena'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Toma'), findsOneWidget);
    });

    testWidgets('Test 4: disabled flags hide their respective FilterChips', (tester) async {
      setupDesktopWindow(tester);

      SharedPreferences.setMockInitialValues({});

      final project = RenombrataProject(
        showMos: false,
        showTf: false,
        showDs: true,
        showFf: true,
        showGpr: false,
        showDr: false,
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

      expect(find.byKey(const ValueKey('studio_flag_mos')), findsNothing);
      expect(find.byKey(const ValueKey('studio_flag_tf')), findsNothing);
      expect(find.byKey(const ValueKey('studio_flag_gpr')), findsNothing);
      expect(find.byKey(const ValueKey('studio_flag_dr')), findsNothing);
      expect(find.byKey(const ValueKey('studio_flag_ds')), findsNothing);
      expect(find.byKey(const ValueKey('studio_flag_ff')), findsNothing);
    });

    testWidgets('Test 5: proposed banner sits above video player and updates reactively live', (tester) async {
      setupDesktopWindow(tester);

      SharedPreferences.setMockInitialValues({});

      final project = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata(
            nomenclature: 'STUDIOPROD',
            date: '260817',
            unit: 'U1',
            day: 'D01',
            producer: '',
            production: 'STUDIOPROD',
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

      final bannerFinder = find.byKey(const ValueKey('studio_proposed_banner'));
      final videoContainerFinder = find.byKey(const ValueKey('studio_video_player_container'));

      expect(bannerFinder, findsOneWidget);
      expect(videoContainerFinder, findsOneWidget);

      final bannerDy = tester.getTopLeft(bannerFinder).dy;
      final videoDy = tester.getTopLeft(videoContainerFinder).dy;

      // Banner sits above video player
      expect(bannerDy, lessThan(videoDy));

      // Edit Escena
      final sceneField = find.widgetWithText(TextField, 'Escena');
      await tester.enterText(sceneField, '88');
      await tester.pumpAndSettle();

      final bannerText1 = tester.widget<Text>(find.byKey(const ValueKey('studio_proposed_banner_text'))).data;
      expect(bannerText1, contains('_88_'));

      // Edit Toma
      final takeField = find.widgetWithText(TextField, 'Toma');
      await tester.enterText(takeField, '9');
      await tester.pumpAndSettle();

      final bannerText2 = tester.widget<Text>(find.byKey(const ValueKey('studio_proposed_banner_text'))).data;
      expect(bannerText2, contains('_T9_'));
    });

    testWidgets('Test 6: Observaciones / Notas is a single-line TextField', (tester) async {
      setupDesktopWindow(tester);

      SharedPreferences.setMockInitialValues({});

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

      final notesFinder = find.widgetWithText(TextField, 'Observaciones / Notas');
      expect(notesFinder, findsOneWidget);

      final notesWidget = tester.widget<TextField>(notesFinder);
      expect(notesWidget.maxLines, equals(1));
    });
  });
}
