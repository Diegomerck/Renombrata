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
  });
}
