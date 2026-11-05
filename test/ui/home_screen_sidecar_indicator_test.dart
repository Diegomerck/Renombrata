import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('renombrata_sidecar_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

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

  RenombrataProject buildTestProject({
    required List<ShotRecord> records,
    List<CameraConfig>? cameras,
    String defaultReel = 'A001',
    String activeCamera = 'A',
  }) {
    return RenombrataProject(
      log: ShootingLog(
        metadata: ShootingLogMetadata.empty().copyWith(
          nomenclature: 'PRJ',
          date: '260817',
          unit: 'U1',
          day: 'D01',
          production: 'PRJ',
        ),
        records: records,
      ),
      cameras: cameras ?? const [
        CameraConfig(name: 'A', type: CameraType.regular),
        CameraConfig(name: 'B', type: CameraType.regular),
      ],
      defaultReel: defaultReel,
      activeCamera: activeCamera,
    );
  }

  group('HomeScreen Sidecar Indicator & File Details Tests', () {
    testWidgets('displays XML badge and Sin XML badge on studio clip cards', (tester) async {
      setupDesktopWindow(tester);

      final videoPath1 = '${tempDir.path}/A001C001_260817AB.MP4';
      final xmlPath1 = '${tempDir.path}/A001C001_260817AB.XML';
      final videoPath2 = '${tempDir.path}/B001C001_260817AB.MP4';

      File(videoPath1).writeAsBytesSync(List.filled(4096, 0));
      File(xmlPath1).writeAsStringSync('<xml></xml>');
      File(videoPath2).writeAsBytesSync(List.filled(2048, 0));

      final rec1 = ShotRecord(
        id: 'rec-1',
        chapter: '01',
        scene: '10',
        plane: 'P1',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
        reel: 'A001',
      );
      final rec2 = ShotRecord(
        id: 'rec-2',
        chapter: '01',
        scene: '10',
        plane: 'P1',
        take: '2',
        cameras: [CameraTakeRecord(cameraName: 'B', clipName: '001')],
        reel: 'B001',
      );

      final project = buildTestProject(records: [rec1, rec2]);

      final prop1 = RenameProposal(
        originalFilePath: videoPath1,
        proposedFileName: 'PRJ_01_10_P1_1_A001_D01_01_U1.MP4',
        fileReel: 'A001',
        associatedRecord: rec1,
        status: ProposalStatus.ready,
        companionFilePath: xmlPath1,
      );

      final xmlProp1 = RenameProposal(
        originalFilePath: xmlPath1,
        proposedFileName: 'PRJ_01_10_P1_1_A001_D01_01_U1.XML',
        fileReel: 'A001',
        status: ProposalStatus.ready,
        isCompanionFile: true,
        companionFilePath: videoPath1,
      );

      final prop2 = RenameProposal(
        originalFilePath: videoPath2,
        proposedFileName: 'PRJ_01_10_P1_2_B001_D01_01_U1.MP4',
        fileReel: 'B001',
        associatedRecord: rec2,
        status: ProposalStatus.ready,
      );

      final report = DryRunReport(proposals: [prop1, xmlProp1, prop2]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      // Navigate to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Enter Modo Estudio
      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      // Verify that XML badge with 'XML' exists for prop1
      final xmlBadge1 = find.byKey(ValueKey('xml_badge_$videoPath1'));
      expect(xmlBadge1, findsOneWidget);
      expect(find.descendant(of: xmlBadge1, matching: find.text('XML')), findsOneWidget);

      // Verify that XML badge with 'Sin XML' exists for prop2
      final xmlBadge2 = find.byKey(ValueKey('xml_badge_$videoPath2'));
      expect(xmlBadge2, findsOneWidget);
      expect(find.descendant(of: xmlBadge2, matching: find.text('Sin XML')), findsOneWidget);

      // Verify that the Studio Inspector renders the studio_file_details_header
      final headerFinder = find.byKey(const ValueKey('studio_file_details_header'));
      expect(headerFinder, findsOneWidget);

      // The first selected clip is prop1, which has companion xmlPath1
      expect(
        find.descendant(of: headerFinder, matching: find.text('Sidecar: A001C001_260817AB.XML')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: headerFinder, matching: find.text('4 KB')),
        findsOneWidget,
      );

      // Select prop2 in the list
      await tester.tap(find.text('B001C001_260817AB.MP4'));
      await tester.pumpAndSettle();

      // For prop2, inspector header should now show 'Sin archivo XML'
      expect(
        find.descendant(of: headerFinder, matching: find.text('Sin archivo XML')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: headerFinder, matching: find.text('2 KB')),
        findsOneWidget,
      );
    });

    testWidgets('TC In/Out sync updates empty bitácora records automatically', (tester) async {
      setupDesktopWindow(tester);

      final videoPath = '${tempDir.path}/A001C001_260817AB.MP4';
      File(videoPath).writeAsBytesSync(List.filled(1024, 0));

      final rec = ShotRecord(
        id: 'rec-empty-tc',
        chapter: '01',
        scene: '10',
        plane: 'P1',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
        reel: 'A001',
        tcIn: '',
        tcOut: '',
      );

      final project = buildTestProject(records: [rec]);

      final prop = RenameProposal(
        originalFilePath: videoPath,
        proposedFileName: 'PRJ_01_10_P1_1_A001_D01_01_U1.MP4',
        fileReel: 'A001',
        associatedRecord: rec,
        status: ProposalStatus.ready,
        fileTcIn: '10:00:00:00',
        fileTcOut: '10:01:30:12',
      );

      final report = DryRunReport(proposals: [prop]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      // Directly invoke checkAndSyncTimecodes
      await homeState.checkAndSyncTimecodes(report);
      await tester.pumpAndSettle();

      final updatedRec = (homeState.project as RenombrataProject).log.records.first;
      expect(updatedRec.tcIn, equals('10:00:00:00'));
      expect(updatedRec.tcOut, equals('10:01:30:12'));
    });

    testWidgets('TC In/Out sync prompts dialog when record TC differs and updates on confirmation', (tester) async {
      setupDesktopWindow(tester);

      final videoPath = '${tempDir.path}/A001C001_260817AB.MP4';
      File(videoPath).writeAsBytesSync(List.filled(1024, 0));

      final rec = ShotRecord(
        id: 'rec-diff-tc',
        chapter: '01',
        scene: '10',
        plane: 'P1',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
        reel: 'A001',
        tcIn: '09:00:00:00',
        tcOut: '09:01:00:00',
      );

      final project = buildTestProject(records: [rec]);

      final prop = RenameProposal(
        originalFilePath: videoPath,
        proposedFileName: 'PRJ_01_10_P1_1_A001_D01_01_U1.MP4',
        fileReel: 'A001',
        associatedRecord: rec,
        status: ProposalStatus.ready,
        fileTcIn: '10:00:00:00',
        fileTcOut: '10:01:30:12',
      );

      final report = DryRunReport(proposals: [prop]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;

      // Start checkAndSyncTimecodes asynchronously because it displays a dialog
      var syncFuture = homeState.checkAndSyncTimecodes(report);
      await tester.pumpAndSettle();

      // Verify dialog is shown
      expect(find.text('Actualizar Timecodes desde Archivos'), findsOneWidget);
      expect(
        find.textContaining('Se detectaron timecodes en los archivos importados (ej. TC In: 10:00:00:00)'),
        findsOneWidget,
      );

      // Tap 'No, mantener bitácora'
      await tester.tap(find.text('No, mantener bitácora'));
      await tester.pumpAndSettle();
      await syncFuture;

      var currentRec = (homeState.project as RenombrataProject).log.records.first;
      expect(currentRec.tcIn, equals('09:00:00:00')); // Unchanged

      // Now test accepting the update
      syncFuture = homeState.checkAndSyncTimecodes(report);
      await tester.pumpAndSettle();

      expect(find.text('Actualizar Timecodes desde Archivos'), findsOneWidget);
      await tester.tap(find.text('Sí, actualizar timecodes'));
      await tester.pumpAndSettle();
      await syncFuture;

      currentRec = (homeState.project as RenombrataProject).log.records.first;
      expect(currentRec.tcIn, equals('10:00:00:00')); // Updated!
      expect(currentRec.tcOut, equals('10:01:30:12'));
    });
  });
}
