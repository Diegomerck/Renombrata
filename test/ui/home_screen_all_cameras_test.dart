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

  group('HomeScreen All Cameras (ALL) & Disk-Only Studio Filter Tests', () {
    testWidgets('ALL camera view displays [CAM X] badges on left clip items in Studio mode', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'ALL',
      );

      final propA = RenameProposal(
        originalFilePath: '/media/A001C001_260817AB.MP4',
        proposedFileName: 'A001C001_260817AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.ready,
      );

      final propB = RenameProposal(
        originalFilePath: '/media/B001C001_260817AB.MP4',
        proposedFileName: 'B001C001_260817AB.MP4',
        fileReel: 'B001',
        status: ProposalStatus.ready,
      );

      final report = DryRunReport(proposals: [propA, propB]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      // Navigate to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Enter Modo Estudio
      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      // Verify camera badges are displayed for both clips
      expect(find.text('[CAM A]'), findsOneWidget);
      expect(find.text('[CAM B]'), findsOneWidget);
    });

    testWidgets('studio mode excludes missingFile proposals (ghost files) from left clip list', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final existingProp = RenameProposal(
        originalFilePath: '/media/A001C001_260817AB.MP4',
        proposedFileName: 'A001C001_260817AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.ready,
      );

      // Missing file without originalFilePath and status missingFile
      final missingProp = RenameProposal(
        originalFilePath: null,
        proposedFileName: 'A001C002_260817AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.missingFile,
      );

      final report = DryRunReport(proposals: [existingProp, missingProp]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      // Navigate to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Verify Table View shows both (including missing file with Falta status)
      expect(find.text('A001C002_260817AB.MP4'), findsWidgets);

      // Switch to Studio Mode
      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      // In Studio Mode, Clips de Medios count should only be 1
      expect(find.text('Clips de Medios (1)'), findsOneWidget);
      expect(find.text('A001C001_260817AB.MP4'), findsWidgets);
      // Missing file must NOT appear in the left media list
      expect(find.byKey(const ValueKey('studio_clip_1')), findsNothing);
    });

    testWidgets('selecting "Todas las Cámaras" in camera dropdown updates activeCamera to ALL', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final report = DryRunReport(proposals: []);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      // Navigate to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Open camera selector dropdown
      final dropdownFinder = find.byKey(const ValueKey('camera_selector_dropdown'));
      expect(dropdownFinder, findsOneWidget);
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Tap 'Todas las Cámaras' option
      final allOptionFinder = find.text('Todas las Cámaras').last;
      expect(allOptionFinder, findsOneWidget);
      await tester.tap(allOptionFinder);
      await tester.pumpAndSettle();

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      expect(homeState.project.activeCamera, equals('ALL'));
    });
  });
}
