import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/app_settings.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/bitacora_editor_tab.dart';

void main() {
  group('BitacoraEditorTab - Scene Group Banners & Scroll Stability', () {
    testWidgets('identifies scene clusters and renders Scene Group Banners with correct take counts', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final records = [
        ShotRecord(id: 'r1', chapter: '1', scene: '10', plane: '1', take: '1', cameras: [], reel: '001'),
        ShotRecord(id: 'r2', chapter: '1', scene: '10', plane: '1', take: '2', cameras: [], reel: '001'),
        ShotRecord(id: 'r3', chapter: '1', scene: '10', plane: '1', take: '3', cameras: [], reel: '001'),
        ShotRecord(id: 'r4', chapter: '1', scene: '11', plane: 'A', take: '1', cameras: [], reel: '001'),
      ];

      final project = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty(),
          records: records,
        ),
        defaultReel: '001',
        activeCamera: 'A',
        cameraNames: ['A'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BitacoraEditorTab(
              project: project,
              settings: const AppSettings(usePagesStyleLayout: true),
              onProjectChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Cluster 1 (Scene 10, Plane 1): 3 takes
      expect(find.text('ESCENA 10'), findsOneWidget);
      expect(find.text('CAP: 1'), findsNWidgets(2)); // Scene 10 banner and Scene 11 banner
      expect(find.text('PLANO: 1'), findsOneWidget);
      expect(find.text('3 tomas'), findsOneWidget);

      // Cluster 2 (Scene 11, Plane A): 1 take
      expect(find.text('ESCENA 11'), findsOneWidget);
      expect(find.text('PLANO: A'), findsOneWidget);
      expect(find.text('1 toma'), findsOneWidget);

      // Verify grid Card key is stable and does NOT contain records.length
      expect(find.byKey(const ValueKey('grid_card_A')), findsOneWidget);
    });

    testWidgets('adding and duplicating takes maintains stable keys and invokes onProjectChanged', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      RenombrataProject currentProject = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty(),
          records: [
            ShotRecord(id: 'r1', chapter: '1', scene: '10', plane: '1', take: '1', cameras: [], reel: '001'),
          ],
        ),
        defaultReel: '001',
        activeCamera: 'A',
        cameraNames: ['A'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return BitacoraEditorTab(
                  project: currentProject,
                  settings: const AppSettings(usePagesStyleLayout: true),
                  onProjectChanged: (updated) {
                    setState(() {
                      currentProject = updated;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(currentProject.log.records.length, 1);
      expect(find.byKey(const ValueKey('grid_card_A')), findsOneWidget);

      // Tap Nueva Toma
      await tester.tap(find.widgetWithText(ElevatedButton, 'Nueva Toma'));
      await tester.pumpAndSettle();

      expect(currentProject.log.records.length, 2);
      expect(find.byKey(const ValueKey('grid_card_A')), findsOneWidget);

      // Tap Duplicar última toma
      await tester.tap(find.widgetWithText(ElevatedButton, 'Duplicar última toma'));
      await tester.pumpAndSettle();

      expect(currentProject.log.records.length, 3);
      expect(find.byKey(const ValueKey('grid_card_A')), findsOneWidget);
    });

    testWidgets('bypasses horizontal SingleChildScrollView on wide viewports and enables it on narrow viewports', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final project = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty(),
          records: [
            ShotRecord(id: 'r1', chapter: '1', scene: '10', plane: '1', take: '1', cameras: [], reel: '001'),
          ],
        ),
        defaultReel: '001',
        activeCamera: 'A',
        cameraNames: ['A'],
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

      // On wide screen (1920px), no horizontal SingleChildScrollView exists in grid_card_A
      final gridHorizontalScrollFinder = find.descendant(
        of: find.byKey(const ValueKey('grid_card_A')),
        matching: find.byWidgetPredicate(
          (widget) => widget is SingleChildScrollView && widget.scrollDirection == Axis.horizontal,
        ),
      );
      expect(gridHorizontalScrollFinder, findsNothing);

      // Resize to narrow screen (500px)
      tester.view.physicalSize = const Size(500, 800);
      await tester.pumpAndSettle();

      // Now horizontal SingleChildScrollView is rendered in grid_card_A with ClampingScrollPhysics
      expect(gridHorizontalScrollFinder, findsOneWidget);
      final scrollView = tester.widget<SingleChildScrollView>(gridHorizontalScrollFinder);
      expect(scrollView.physics, isA<ClampingScrollPhysics>());
      expect(scrollView.dragStartBehavior, DragStartBehavior.down);
    });

    testWidgets('adding Nueva Toma creates an independent scene banner and typing does not drop focus', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      RenombrataProject currentProject = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty(),
          records: [
            ShotRecord(id: 'r1', chapter: '15', scene: '3', plane: '1', take: '1', cameras: [], reel: '001'),
          ],
        ),
        defaultReel: '001',
        activeCamera: 'A',
        cameraNames: ['A'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return BitacoraEditorTab(
                  project: currentProject,
                  settings: const AppSettings(usePagesStyleLayout: true),
                  onProjectChanged: (updated) {
                    setState(() {
                      currentProject = updated;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially 1 banner for Scene 3
      expect(find.text('ESCENA 3'), findsOneWidget);

      // Tap Nueva Toma
      await tester.tap(find.widgetWithText(ElevatedButton, 'Nueva Toma'));
      await tester.pumpAndSettle();

      // Verify that Nueva Toma (with chapter='' and scene='') gets its OWN separator banner immediately
      expect(find.text('ESCENA S/E'), findsOneWidget);
      expect(find.text('ESCENA 3'), findsOneWidget);

      // Verify take defaults to '1'
      expect(currentProject.log.records.last.take, '1');

      // Verify that Cap field is present and can be typed into without dropping
      final newRecordId = currentProject.log.records.last.id;
      final capFinder = find.byKey(ValueKey('${newRecordId}_tier2_cap'));
      expect(capFinder, findsOneWidget);

      await tester.tap(capFinder);
      await tester.pump();

      await tester.enterText(capFinder, '16');
      await tester.pump();

      expect(find.widgetWithText(TextFormField, '16'), findsOneWidget);
      expect(currentProject.log.records.last.chapter, '16');
    });

    testWidgets('Configurar button opens dialog and toggles column visibility properly', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      RenombrataProject currentProject = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty(),
          records: [
            ShotRecord(id: 'r1', chapter: '15', scene: '3', plane: '1', take: '1', cameras: [], reel: '001', tcIn: '10:00:00:00', tcOut: '10:05:00:00'),
          ],
        ),
        defaultReel: '001',
        activeCamera: 'A',
        cameraNames: ['A'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return BitacoraEditorTab(
                  project: currentProject,
                  settings: const AppSettings(usePagesStyleLayout: true),
                  onProjectChanged: (updated) {
                    setState(() {
                      currentProject = updated;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially, TC Out (header + cell) and banner badges are visible
      expect(find.text('TC Out'), findsNWidgets(2));
      expect(find.text('CAP: 15'), findsOneWidget);
      expect(find.text('PLANO: 1'), findsOneWidget);

      // Tap solid "Configurar" button
      final configBtn = find.widgetWithText(FilledButton, 'Configurar');
      expect(configBtn, findsOneWidget);
      await tester.tap(configBtn);
      await tester.pumpAndSettle();

      // Verify Dialog opens
      expect(find.text('Configuración de Bitácora'), findsOneWidget);
      expect(find.text('Columnas y Campos Visibles'), findsOneWidget);

      // Uncheck Capítulo and TC Out inside Dialog
      final dialogFinder = find.byType(AlertDialog);
      await tester.tap(find.descendant(of: dialogFinder, matching: find.text('Capítulo')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: dialogFinder, matching: find.text('TC Out')));
      await tester.pumpAndSettle();

      // Save Dialog
      await tester.tap(find.descendant(of: dialogFinder, matching: find.widgetWithText(FilledButton, 'Guardar')));
      await tester.pumpAndSettle();

      // Verify updated flags on project
      expect(currentProject.showChapter, isFalse);
      expect(currentProject.showTcOut, isFalse);

      // Verify TC Out header and CAP badge are hidden
      expect(find.text('TC Out'), findsNothing);
      expect(find.text('CAP: 15'), findsNothing);
      // Plano badge still visible
      expect(find.text('PLANO: 1'), findsOneWidget);

      // Adding new record now targets 'scene' for autofocus
      await tester.tap(find.widgetWithText(ElevatedButton, 'Nueva Toma'));
      await tester.pumpAndSettle();

      final newRecordId = currentProject.log.records.last.id;
      final sceneFinder = find.byKey(ValueKey('${newRecordId}_tier2_scene'));
      expect(sceneFinder, findsOneWidget);
      // Cap in tier 2 is hidden because showChapter is false
      expect(find.byKey(ValueKey('${newRecordId}_tier2_cap')), findsNothing);
    });

    testWidgets('guarantees instant autofocus on Nueva Toma on empty bitácora allowing immediate typing without manual click', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var currentProject = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty(),
          records: [],
        ),
        defaultReel: '001',
        activeCamera: 'A',
        cameraNames: ['A'],
        showChapter: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return BitacoraEditorTab(
                  project: currentProject,
                  settings: const AppSettings(usePagesStyleLayout: true),
                  onProjectChanged: (updated) {
                    setState(() {
                      currentProject = updated;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Agregar Primera Toma" on empty state
      final addBtn = find.text('Agregar Primera Toma');
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      // Verify record creation
      expect(currentProject.log.records.length, 1);
      final newRecord = currentProject.log.records.first;
      expect(find.byKey(ValueKey('${newRecord.id}_tier2_cap')), findsOneWidget);

      // Verify that primaryFocus is active
      expect(FocusManager.instance.primaryFocus, isNotNull);

      // Type directly without tapping the input field
      tester.testTextInput.enterText('101');
      await tester.pumpAndSettle();

      // Verify that text arrived in project state
      expect(currentProject.log.records.first.chapter, '101');
    });
  });
}
