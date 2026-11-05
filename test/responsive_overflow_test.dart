import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/ui/bitacora_editor_tab.dart';
import 'package:renombrata/src/ui/home_screen.dart';

void main() {
  testWidgets('BitacoraEditorTab renders cleanly on narrow window sizes without overflow', (WidgetTester tester) async {
    // Test with minimum desktop window size (980x680)
    tester.view.physicalSize = const Size(980, 680);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final project = RenombrataProject(
      log: ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'TEST_FILM',
          date: '101026',
          unit: 'U1',
          day: 'D1',
          producer: 'Test Producer',
          production: 'Test Production',
          location: 'Studio A',
          audioFormat: '48kHz 24bit',
          frameRate: '23.98',
          videoCodec: 'ProRes 422 HQ',
          responsibleEngineer: 'Audio Eng',
          ingestor: 'Ingest Specialist',
        ),
        records: [
          ShotRecord(id: 'r1', chapter: '1', scene: '101', plane: '1', take: '1', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: 'A001_C001'),
            CameraTakeRecord(cameraName: 'B', clipName: 'B001_C001'),
            CameraTakeRecord(cameraName: 'C', clipName: 'C001_C001'),
          ], reel: 'A001', tcIn: '01:00:00:00', tcOut: '01:00:15:00', observations: 'Wide master shot'),
          ShotRecord(id: 'r2', chapter: '1', scene: '101', plane: '1', take: '2', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: 'A001_C002'),
            CameraTakeRecord(cameraName: 'B', clipName: 'B001_C002'),
            CameraTakeRecord(cameraName: 'C', clipName: 'C001_C002'),
          ], reel: 'A001', tcIn: '01:00:20:00', tcOut: '01:00:35:00', observations: 'Actor adjusted line'),
        ],
      ),
      defaultReel: 'A001',
      activeCamera: 'A',
      cameraNames: ['A', 'B', 'C'],
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

    // Verify takes are present
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);

    // Verify horizontal scroll view is present in data grid
    final horizontalScrolls = find.byWidgetPredicate(
      (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
    );
    expect(horizontalScrolls, findsWidgets);

    // Verify master checkbox is present
    expect(find.byKey(const ValueKey('master_select_all_checkbox')), findsOneWidget);

    // Verify no flutter exceptions occurred during layout
    expect(tester.takeException(), isNull);
  });

  testWidgets('HomeScreen renders without overflow at minimum window size (980x680)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(980, 680);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify both tabs render and switch properly
    expect(find.text('Bitácora Digital'), findsOneWidget);
    expect(find.text('Renombrador de Medios'), findsOneWidget);

    // Switch to Renombrador de Medios tab
    await tester.tap(find.text('Renombrador de Medios'));
    await tester.pumpAndSettle();

    // Verify controls and layout render without exceptions
    expect(find.text('Importar Excel'), findsOneWidget);
    expect(find.text('Selector de Carpeta de Medios'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BitacoraEditorTab with 5 cameras scrolls horizontally without overflow on 980x680', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(980, 680);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final project = RenombrataProject(
      log: ShootingLog(
        metadata: ShootingLogMetadata.empty(),
        records: [
          ShotRecord(id: 'r1', chapter: '1', scene: '101', plane: '1', take: '1', cameras: [
            CameraTakeRecord(cameraName: 'A', clipName: 'A001'),
            CameraTakeRecord(cameraName: 'B', clipName: 'B001'),
            CameraTakeRecord(cameraName: 'C', clipName: 'C001'),
            CameraTakeRecord(cameraName: 'D', clipName: 'D001'),
            CameraTakeRecord(cameraName: 'E', clipName: 'E001'),
          ], reel: 'A001'),
        ],
      ),
      defaultReel: 'A001',
      activeCamera: 'A',
      cameraNames: ['A', 'B', 'C', 'D', 'E'],
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

    expect(find.text('"A"'), findsOneWidget);
    expect(find.text('"E"'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HomeScreen renders with zero overflow at 1100x720 hardware-lock window size and shows table with scrollbar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final report = DryRunReport(
      proposals: [
        RenameProposal(
          originalFilePath: '/media/A001C001.mov',
          proposedFileName: 'PROJECT_101026_U1_D1_E101_T1_A.mov',
          status: ProposalStatus.ready,
          associatedRecord: ShotRecord(
            id: 'r1',
            chapter: '1',
            scene: '101',
            plane: '1',
            take: '1',
            cameras: [],
            reel: 'A001',
          ),
        ),
        RenameProposal(
          originalFilePath: '/media/A001C002.mov',
          proposedFileName: 'PROJECT_101026_U1_D1_E101_T2_A.mov',
          status: ProposalStatus.conflict,
          associatedRecord: ShotRecord(
            id: 'r2',
            chapter: '1',
            scene: '101',
            plane: '1',
            take: '2',
            cameras: [],
            reel: 'A001',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(initialReport: report, initialStudioMode: false),
      ),
    );

    await tester.pumpAndSettle();

    // Verify tabs
    expect(find.text('Bitácora Digital'), findsOneWidget);
    expect(find.text('Renombrador de Medios'), findsOneWidget);

    // Switch to Renombrador de Medios tab
    await tester.tap(find.text('Renombrador de Medios'));
    await tester.pumpAndSettle();

    // Verify table scrollbar and DataTable are present
    expect(find.byType(Scrollbar), findsWidgets);
    expect(find.byType(DataTable), findsOneWidget);

    // Verify status badges are present
    expect(find.text('Listo para renombrar'), findsOneWidget);
    expect(find.text('Conflicto'), findsOneWidget);

    // Verify buttons are present
    expect(find.text('Resolver conflictos (1)'), findsOneWidget);
    expect(find.text('Exportar Reporte'), findsOneWidget);
    expect(find.text('Renombrar archivos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HomeScreen footer responsive layout adapts between row and wrap column based on 1050px threshold', (WidgetTester tester) async {
    // 1. Narrow width < 1050px
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Renombrador de Medios'));
    await tester.pumpAndSettle();

    // In narrow mode (< 1050), footer uses Wrap
    expect(find.byType(Wrap), findsWidgets);
    expect(find.text('Renombrar archivos'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 2. Wide width >= 1050px
    tester.view.physicalSize = const Size(1200, 720);
    await tester.pumpAndSettle();

    expect(find.text('Renombrar archivos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HomeScreen displays TC Coincide and TC Diferente badges correctly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final report = DryRunReport(
      proposals: [
        RenameProposal(
          originalFilePath: '/media/A001C001.mov',
          proposedFileName: 'PROJECT_101026_U1_D1_E101_T1_A.mov',
          status: ProposalStatus.ready,
          fileTcIn: '10:00:00:00',
          fileTcOut: '10:01:00:00',
          associatedRecord: ShotRecord(
            id: 'r1',
            chapter: '1',
            scene: '101',
            plane: '1',
            take: '1',
            tcIn: '10:00:00:00',
            cameras: [],
            reel: 'A001',
          ),
        ),
        RenameProposal(
          originalFilePath: '/media/A001C002.mov',
          proposedFileName: 'PROJECT_101026_U1_D1_E101_T2_A.mov',
          status: ProposalStatus.ready,
          fileTcIn: '10:00:00:00',
          fileTcOut: '10:01:00:00',
          associatedRecord: ShotRecord(
            id: 'r2',
            chapter: '1',
            scene: '101',
            plane: '1',
            take: '2',
            tcIn: '15:30:00:00', // Different timecode
            cameras: [],
            reel: 'A001',
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(initialReport: report, initialStudioMode: false),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Renombrador de Medios'));
    await tester.pumpAndSettle();

    // Verify green TC Coincide badge is present for r1
    expect(find.text('TC Coincide'), findsOneWidget);

    // Verify amber TC Diferente badge is present for r2
    expect(find.text('TC Diferente'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
