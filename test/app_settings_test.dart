import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/app_settings.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/settings_service.dart';
import 'package:renombrata/src/ui/bitacora_editor_tab.dart';
import 'package:renombrata/src/ui/settings_dialog.dart';

void main() {
  group('AppSettings', () {
    test('defaults to usePagesStyleLayout: true and autoSortByClip: true', () {
      final settings = AppSettings.defaults();
      expect(settings.usePagesStyleLayout, isTrue);
      expect(settings.autoSortByClip, isTrue);
    });

    test('copyWith updates properties properly', () {
      final settings = AppSettings.defaults();
      final updated = settings.copyWith(usePagesStyleLayout: false);
      expect(updated.usePagesStyleLayout, isFalse);
      expect(updated.autoSortByClip, isTrue);

      final updated2 = updated.copyWith(autoSortByClip: false);
      expect(updated2.usePagesStyleLayout, isFalse);
      expect(updated2.autoSortByClip, isFalse);
    });

    test('serializes to and from json', () {
      final settings = const AppSettings(
        usePagesStyleLayout: false,
        autoSortByClip: false,
      );
      final json = settings.toJson();
      expect(json['usePagesStyleLayout'], isFalse);
      expect(json['autoSortByClip'], isFalse);

      final deserialized = AppSettings.fromJson(json);
      expect(deserialized.usePagesStyleLayout, isFalse);
      expect(deserialized.autoSortByClip, isFalse);
    });

    test('export and import JSON preserves all settings', () async {
      final original = const AppSettings(
        usePagesStyleLayout: false,
        autoSortByClip: true,
      );

      final jsonStr = await SettingsService.exportSettingsJson(original);
      expect(jsonStr, contains('"usePagesStyleLayout": false'));
      expect(jsonStr, contains('"autoSortByClip": true'));

      final imported = SettingsService.importSettingsJson(jsonStr);
      expect(imported.usePagesStyleLayout, isFalse);
      expect(imported.autoSortByClip, isTrue);
      expect(imported, equals(original));
    });
  });

  group('SettingsDialog & Bitacora Layout Toggle Widget Tests', () {
    testWidgets('renders SettingsDialog and switches layout option', (tester) async {
      AppSettings current = AppSettings.defaults();
      AppSettings? updated;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsDialog(
              currentSettings: current,
              onSettingsChanged: (s) => updated = s,
            ),
          ),
        ),
      );

      expect(find.text('Configuración'), findsOneWidget);
      expect(find.text('Visualización de Bitácora'), findsOneWidget);
      expect(find.text('Diseño moderno (Estilo bitácora)'), findsOneWidget);
      expect(find.text('Diseño anterior (Clásico)'), findsOneWidget);

      await tester.tap(find.text('Diseño anterior (Clásico)'));
      await tester.pumpAndSettle();

      expect(updated, isNotNull);
      expect(updated!.usePagesStyleLayout, isFalse);
    });

    testWidgets('BitacoraEditorTab renders Scene Group Banners in Pages Style and individual fields in Legacy Style', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final records = [
        ShotRecord(id: 'r1', chapter: '1', scene: '101', plane: '1', take: '1', cameras: [], reel: '001'),
        ShotRecord(id: 'r2', chapter: '1', scene: '101', plane: '1', take: '2', cameras: [], reel: '001'),
      ];

      final project = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty(),
          records: records,
        ),
        defaultReel: '001',
        activeCamera: 'A',
      );

      // 1. Pages Style (usePagesStyleLayout: true)
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

      // In Pages Style, a prominent Scene Header Banner is rendered above the first take
      expect(find.text('ESCENA 101'), findsOneWidget);
      expect(find.text('CAP: 1'), findsOneWidget);
      expect(find.text('PLANO: 1'), findsOneWidget);
      expect(find.text('2 tomas'), findsOneWidget);

      // 2. Legacy Style (usePagesStyleLayout: false)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BitacoraEditorTab(
              project: project,
              settings: const AppSettings(usePagesStyleLayout: false),
              onProjectChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In legacy layout, scene banners are not rendered, and individual headers are shown
      expect(find.text('ESCENA 101'), findsNothing);
      expect(find.text('Cap'), findsWidgets);
      expect(find.text('Escena'), findsWidgets);
      expect(find.text('Plano'), findsWidgets);
    });

    testWidgets('BitacoraEditorTab updates metadata controllers when new project metadata arrives', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final emptyProject = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: '001',
        activeCamera: 'A',
      );

      final populatedProject = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(
            production: 'Mi Gran Produccion',
            day: 'D20',
            unit: 'U1',
            producer: 'Productor Ejecutivo',
            ingestor: 'Data Manager Lead',
          ),
          records: [],
        ),
        defaultReel: '001',
        activeCamera: 'A',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return BitacoraEditorTab(
                  project: emptyProject,
                  onProjectChanged: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mi Gran Produccion'), findsNothing);

      // Now update widget with populated project
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BitacoraEditorTab(
              project: populatedProject,
              onProjectChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mi Gran Produccion'), findsOneWidget);
      expect(find.text('Productor Ejecutivo'), findsOneWidget);
      expect(find.text('Data Manager Lead'), findsOneWidget);
    });
  });
}
