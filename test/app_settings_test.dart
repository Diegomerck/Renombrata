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
    test('defaults to usePagesStyleLayout: true, autoSortByClip: true, renamerPaneLayout: media_left, pauseVideoOnTabSwitch: true', () {
      final settings = AppSettings.defaults();
      expect(settings.usePagesStyleLayout, isTrue);
      expect(settings.autoSortByClip, isTrue);
      expect(settings.renamerPaneLayout, 'media_left');
      expect(settings.pauseVideoOnTabSwitch, isTrue);
    });

    test('copyWith updates properties properly', () {
      final settings = AppSettings.defaults();
      final updated = settings.copyWith(usePagesStyleLayout: false);
      expect(updated.usePagesStyleLayout, isFalse);
      expect(updated.autoSortByClip, isTrue);
      expect(updated.renamerPaneLayout, 'media_left');
      expect(updated.pauseVideoOnTabSwitch, isTrue);

      final updated2 = updated.copyWith(
        autoSortByClip: false,
        renamerPaneLayout: 'media_right',
        pauseVideoOnTabSwitch: false,
      );
      expect(updated2.usePagesStyleLayout, isFalse);
      expect(updated2.autoSortByClip, isFalse);
      expect(updated2.renamerPaneLayout, 'media_right');
      expect(updated2.pauseVideoOnTabSwitch, isFalse);
    });

    test('defaults include shortcuts map with expected default keys', () {
      final settings = AppSettings.defaults();
      expect(settings.shortcuts, equals(AppSettings.defaultShortcuts));
      expect(settings.shortcuts['new_take'], 'Ctrl+N');
      expect(settings.shortcuts['duplicate_take'], 'Ctrl+D');
      expect(settings.shortcuts['stamp_cut'], 'Ctrl+K');
      expect(settings.shortcuts['undo_delete'], 'Ctrl+Z');
      expect(settings.shortcuts['save_project'], 'Ctrl+S');
    });

    test('copyWith updates shortcuts properly', () {
      final settings = AppSettings.defaults();
      final updated = settings.copyWith(
        shortcuts: {'new_take': 'Ctrl+T', 'stamp_cut': 'F5'},
      );
      expect(updated.shortcuts['new_take'], 'Ctrl+T');
      expect(updated.shortcuts['stamp_cut'], 'F5');
    });

    test('serializes to and from json including shortcuts and pauseVideoOnTabSwitch', () {
      final settings = const AppSettings(
        usePagesStyleLayout: false,
        autoSortByClip: false,
        pauseVideoOnTabSwitch: false,
        shortcuts: {
          'new_take': 'Ctrl+Shift+N',
          'duplicate_take': 'Ctrl+D',
          'stamp_cut': 'Ctrl+K',
          'undo_delete': 'Ctrl+Z',
          'save_project': 'Ctrl+S',
        },
      );
      final json = settings.toJson();
      expect(json['usePagesStyleLayout'], isFalse);
      expect(json['autoSortByClip'], isFalse);
      expect(json['pauseVideoOnTabSwitch'], isFalse);
      expect(json['shortcuts']['new_take'], 'Ctrl+Shift+N');

      final deserialized = AppSettings.fromJson(json);
      expect(deserialized.usePagesStyleLayout, isFalse);
      expect(deserialized.autoSortByClip, isFalse);
      expect(deserialized.pauseVideoOnTabSwitch, isFalse);
      expect(deserialized.shortcuts['new_take'], 'Ctrl+Shift+N');
    });

    test('export and import JSON preserves all settings and shortcuts', () async {
      final original = const AppSettings(
        usePagesStyleLayout: false,
        autoSortByClip: true,
        pauseVideoOnTabSwitch: false,
        shortcuts: {
          'new_take': 'Ctrl+N',
          'duplicate_take': 'Ctrl+D',
          'stamp_cut': 'Ctrl+Space',
          'undo_delete': 'Ctrl+Z',
          'save_project': 'Ctrl+S',
        },
      );

      final jsonStr = await SettingsService.exportSettingsJson(original);
      expect(jsonStr, contains('"usePagesStyleLayout": false'));
      expect(jsonStr, contains('"autoSortByClip": true'));
      expect(jsonStr, contains('"pauseVideoOnTabSwitch": false'));
      expect(jsonStr, contains('"stamp_cut": "Ctrl+Space"'));

      final imported = SettingsService.importSettingsJson(jsonStr);
      expect(imported.usePagesStyleLayout, isFalse);
      expect(imported.autoSortByClip, isTrue);
      expect(imported.pauseVideoOnTabSwitch, isFalse);
      expect(imported.shortcuts['stamp_cut'], 'Ctrl+Space');
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

    testWidgets('renders SettingsDialog and switches renamerPaneLayout option', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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

      expect(find.text('Orientación del Renombrador de Medios'), findsOneWidget);
      expect(find.text('Medios a la izquierda, Nombres a la derecha (Estilo Finder)'), findsOneWidget);
      expect(find.text('Nombres a la izquierda, Medios a la derecha'), findsOneWidget);

      await tester.ensureVisible(find.text('Nombres a la izquierda, Medios a la derecha'));
      await tester.tap(find.text('Nombres a la izquierda, Medios a la derecha'));
      await tester.pumpAndSettle();

      expect(updated, isNotNull);
      expect(updated!.renamerPaneLayout, 'media_right');
    });

    testWidgets('SettingsDialog renders 4 tabs and switches between General, Bitacora, Atajos, and Reproductor', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final current = AppSettings.defaults();
      RenombrataProject project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: '001',
        activeCamera: 'A',
      );
      RenombrataProject? updatedProject;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsDialog(
              currentSettings: current,
              onSettingsChanged: (_) {},
              project: project,
              onProjectChanged: (p) => updatedProject = p,
            ),
          ),
        ),
      );

      // Verify all 4 tab labels
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Bitácora'), findsOneWidget);
      expect(find.text('Atajos'), findsOneWidget);
      expect(find.text('Reproductor de Video'), findsOneWidget);

      // Switch to Bitacora tab
      await tester.tap(find.text('Bitácora'));
      await tester.pumpAndSettle();

      expect(find.text('Columnas y Campos Visibles'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Capítulo'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Plano'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'MOS (Sin Sonido)'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'TC Out'), findsOneWidget);
      expect(find.text('Configuración de Cámaras'), findsOneWidget);

      // Toggle Capítulo (was true by default, now false)
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Capítulo'));
      await tester.pumpAndSettle();

      expect(updatedProject, isNotNull);
      expect(updatedProject!.showChapter, isFalse);

      // Switch to Atajos tab
      await tester.tap(find.text('Atajos'));
      await tester.pumpAndSettle();

      expect(find.text('Nueva Toma'), findsOneWidget);
      expect(find.text('Duplicar Toma'), findsOneWidget);
      expect(find.text('Marcar Corte'), findsOneWidget);
      expect(find.text('Deshacer Eliminación'), findsOneWidget);
      expect(find.text('Guardar Proyecto'), findsOneWidget);
      expect(find.text('Restablecer atajos'), findsOneWidget);

      // Switch to Reproductor de Video tab
      await tester.tap(find.text('Reproductor de Video'));
      await tester.pumpAndSettle();

      expect(find.text('Comportamiento de Reproducción'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings_pause_video_on_tab_switch_tile')), findsOneWidget);
    });

    testWidgets('SettingsDialog opens directly to Bitacora tab with initialTabIndex: 1', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final current = AppSettings.defaults();
      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: '001',
        activeCamera: 'A',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsDialog(
              currentSettings: current,
              onSettingsChanged: (_) {},
              project: project,
              onProjectChanged: (_) {},
              initialTabIndex: 1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bitacora tab content should be visible immediately
      expect(find.text('Columnas y Campos Visibles'), findsOneWidget);
      expect(find.text('Configuración de Cámaras'), findsOneWidget);
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

    test('ShotRecord supports isDs, isFf, isGpr defaults, copyWith, and json serialization', () {
      final defaultRecord = ShotRecord(
        id: 'rec_1',
        chapter: '1',
        scene: '10',
        take: '1',
        cameras: [],
        reel: '001',
      );

      expect(defaultRecord.isDs, isFalse);
      expect(defaultRecord.isFf, isFalse);
      expect(defaultRecord.isGpr, isFalse);

      final modified = defaultRecord.copyWith(
        isDs: true,
        isFf: true,
        isGpr: true,
      );
      expect(modified.isDs, isTrue);
      expect(modified.isFf, isTrue);
      expect(modified.isGpr, isTrue);

      final json = modified.toJson();
      expect(json['isDs'], isTrue);
      expect(json['isFf'], isTrue);
      expect(json['isGpr'], isTrue);

      final deserialized = ShotRecord.fromJson(json);
      expect(deserialized.isDs, isTrue);
      expect(deserialized.isFf, isTrue);
      expect(deserialized.isGpr, isTrue);
    });

    test('RenombrataProject supports showDs, showFf, showGpr, bitacoraElementOrder, and conventionNameOrder', () {
      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: '001',
        activeCamera: 'A',
      );

      expect(project.showDs, isTrue);
      expect(project.showFf, isTrue);
      expect(project.showGpr, isTrue);
      expect(project.showDr, isTrue);
      expect(project.showTf, isTrue);
      expect(project.bitacoraElementOrder, ['capitulo', 'escena', 'plano', 'toma']);
      expect(project.conventionNameOrder, ['capitulo', 'escena', 'plano', 'toma']);

      final updated = project.copyWith(
        showDs: false,
        showFf: false,
        showGpr: false,
        showDr: false,
        showTf: false,
        bitacoraElementOrder: ['escena', 'toma', 'capitulo', 'plano'],
        conventionNameOrder: ['escena', 'plano', 'toma', 'capitulo'],
      );

      expect(updated.showDs, isFalse);
      expect(updated.showFf, isFalse);
      expect(updated.showGpr, isFalse);
      expect(updated.showDr, isFalse);
      expect(updated.showTf, isFalse);
      expect(updated.bitacoraElementOrder, ['escena', 'toma', 'capitulo', 'plano']);
      expect(updated.conventionNameOrder, ['escena', 'plano', 'toma', 'capitulo']);

      final json = updated.toJson();
      expect(json['showDs'], isFalse);
      expect(json['showFf'], isFalse);
      expect(json['showGpr'], isFalse);
      expect(json['showDr'], isFalse);
      expect(json['showTf'], isFalse);
      expect(json['bitacoraElementOrder'], ['escena', 'toma', 'capitulo', 'plano']);
      expect(json['conventionNameOrder'], ['escena', 'plano', 'toma', 'capitulo']);

      final deserialized = RenombrataProject.fromJson(json);
      expect(deserialized.showDs, isFalse);
      expect(deserialized.showFf, isFalse);
      expect(deserialized.showGpr, isFalse);
      expect(deserialized.showDr, isFalse);
      expect(deserialized.showTf, isFalse);
      expect(deserialized.bitacoraElementOrder, ['escena', 'toma', 'capitulo', 'plano']);
      expect(deserialized.conventionNameOrder, ['escena', 'plano', 'toma', 'capitulo']);
    });

    test('ShotRecord supports isDr and isTf with defaults, copyWith, and json serialization', () {
      final record = ShotRecord(
        id: 'rec_1',
        chapter: '1',
        scene: '2',
        plane: '3',
        take: '4',
        cameras: [],
        reel: '001',
      );

      expect(record.isDr, isFalse);
      expect(record.isTf, isFalse);

      final updated = record.copyWith(isDr: true, isTf: true);
      expect(updated.isDr, isTrue);
      expect(updated.isTf, isTrue);

      final json = updated.toJson();
      expect(json['isDr'], isTrue);
      expect(json['isTf'], isTrue);

      final fromJson = ShotRecord.fromJson(json);
      expect(fromJson.isDr, isTrue);
      expect(fromJson.isTf, isTrue);
    });

    testWidgets('SettingsDialog Bitácora Tab renders DS/FF/GPR/DR/TF toggles and draggable element blocks', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      RenombrataProject? updatedProject;
      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: '001',
        activeCamera: 'A',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsDialog(
              currentSettings: AppSettings.defaults(),
              onSettingsChanged: (_) {},
              project: project,
              onProjectChanged: (p) => updatedProject = p,
              initialTabIndex: 1, // Open Bitácora Tab directly
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check for DS, FF, GPR, DR, TF CheckboxListTiles
      expect(find.text('DS (Driving Shot)'), findsOneWidget);
      expect(find.text('FF (Free Fly)'), findsOneWidget);
      expect(find.text('GPR (GoPro)'), findsOneWidget);
      expect(find.text('DR (Drone)'), findsOneWidget);
      expect(find.text('TF (Toma Falsa)'), findsOneWidget);

      // Check for Reorderable block headings
      expect(find.text('Orden de elementos en la bitácora'), findsOneWidget);
      expect(find.text('Orden de elementos en el nombre de convención'), findsOneWidget);

      // Check that block labels are rendered (each in bitacora and convention lists = 2 times)
      expect(find.text('Capítulo'), findsWidgets);
      expect(find.text('Escena'), findsWidgets);
      expect(find.text('Plano'), findsWidgets);
      expect(find.text('Toma'), findsWidgets);

      // Toggle DR checkbox
      await tester.ensureVisible(find.text('DR (Drone)'));
      await tester.tap(find.text('DR (Drone)'));
      await tester.pumpAndSettle();

      expect(updatedProject, isNotNull);
      expect(updatedProject!.showDr, isFalse);

      // Toggle TF checkbox
      await tester.ensureVisible(find.text('TF (Toma Falsa)'));
      await tester.tap(find.text('TF (Toma Falsa)'));
      await tester.pumpAndSettle();

      expect(updatedProject!.showTf, isFalse);
    });
  });
}
