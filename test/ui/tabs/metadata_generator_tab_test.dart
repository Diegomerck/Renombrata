import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:renombrata/src/ui/tabs/metadata_generator_tab.dart';

class _FakeDropItem implements DropItem {
  @override
  final String path;

  @override
  String get name => p.basename(path);

  _FakeDropItem(this.path);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  void setupDesktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  RenombrataProject buildNeutralProject({
    String ingestor = '',
    String location = '',
  }) {
    return RenombrataProject(
      defaultReel: '001',
      activeCamera: 'A',
      log: ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'INFAM',
          date: '2026-11-12',
          unit: 'U11B',
          day: 'D40',
          producer: '',
          production: 'INFAM',
          location: location,
          audioFormat: '48kHz 24bit',
          frameRate: '23.98',
          videoCodec: 'XAVC',
          responsibleEngineer: '',
          ingestor: ingestor,
        ),
        records: [],
      ),
    );
  }

  group('HomeScreen 3-Tab Structure & MetadataGeneratorTab', () {
    testWidgets('HomeScreen renders all 3 tabs and navigates to Generador de Metadata', (tester) async {
      setupDesktop(tester);

      final project = buildNeutralProject();
      final report = DryRunReport(proposals: []);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            initialStudioMode: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Tab, 'Bitácora Digital'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Renombrador'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Generador de Metadata'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, 'Generador de Metadata'));
      await tester.pumpAndSettle();

      expect(find.byType(MetadataGeneratorTab), findsOneWidget);
      expect(find.text('Valores por Lote'), findsOneWidget);
      expect(find.text('Generar XMLs Sidecar'), findsOneWidget);
    });

    testWidgets('MetadataGeneratorTab shows collapsible batch panel with empty fields and subtle hints', (tester) async {
      setupDesktop(tester);

      final project = buildNeutralProject();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MetadataGeneratorTab(
              project: project,
              mediaFiles: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Valores por Lote'), findsOneWidget);
      expect(find.text('Nombre del operador'), findsOneWidget);
      expect(find.text('Locación o set'), findsOneWidget);
      expect(find.text('Auto (de cámara)'), findsOneWidget);
      expect(find.text('Auto (de unidad)'), findsOneWidget);

      // Collapse batch panel
      await tester.tap(find.byKey(const ValueKey('toggle_batch_panel_button')));
      await tester.pumpAndSettle();
      expect(find.text('Aplicar a todos los clips'), findsNothing);

      // Expand batch panel again
      await tester.tap(find.byKey(const ValueKey('toggle_batch_panel_button')));
      await tester.pumpAndSettle();
      expect(find.text('Aplicar a todos los clips'), findsOneWidget);
    });

    testWidgets('MetadataGeneratorTab inspects XML and writes sidecars to disk', (tester) async {
      setupDesktop(tester);

      final tempDir = Directory.systemTemp.createTempSync('metadata_tab_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final mediaFile = File(p.join(tempDir.path, 'INFAM_32_2_T1_PORT16_13_D40_U11B.mxf'));
      mediaFile.writeAsStringSync('dummy video');

      int? generatedCount;
      final project = buildNeutralProject();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MetadataGeneratorTab(
              initialFolderPath: tempDir.path,
              project: project,
              onGenerated: (count) => generatedCount = count,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 clips detectados'), findsOneWidget);
      expect(find.text('ClipName: INFAM_32_2_T1_PORT16_13_D40_U11B'), findsOneWidget);
      expect(
        find.text('INFAM_32_2_T1_PORT16_13_D40_U11B%16_1_D40_U11B'),
        findsOneWidget,
      );

      // Open Ver XML inspector
      await tester.tap(find.text('Ver XML'));
      await tester.pumpAndSettle();

      expect(find.textContaining('<lugar></lugar>'), findsOneWidget);
      expect(find.textContaining('<sinopsis></sinopsis>'), findsOneWidget);
      expect(find.textContaining('<operadorIngesta></operadorIngesta>'), findsOneWidget);
      expect(find.textContaining('<observacionesVideo></observacionesVideo>'), findsOneWidget);
      expect(find.textContaining('<observacionesAudio></observacionesAudio>'), findsOneWidget);

      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      // Generate XML sidecars (runAsync needed for real dart:io async File I/O inside testWidgets)
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('generate_sidecars_confirm_button')));
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(generatedCount, equals(1));
      expect(find.text('¡Éxito! Se generaron 1 archivos XML sidecar.'), findsOneWidget);

      final xmlFile = File(p.join(tempDir.path, 'INFAM_32_2_T1_PORT16_13_D40_U11B.xml'));
      expect(xmlFile.existsSync(), isTrue);
      final xmlContent = xmlFile.readAsStringSync();
      expect(
        xmlContent,
        contains('<convencionNombre>INFAM_32_2_T1_PORT16_13_D40_U11B%16_1_D40_U11B</convencionNombre>'),
      );
    });

    testWidgets('MetadataGeneratorTab supports drag and drop of a media folder', (tester) async {
      setupDesktop(tester);

      final tempDir = Directory.systemTemp.createTempSync('metadata_tab_drop_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final mediaFile = File(p.join(tempDir.path, 'INFAM_32_2_T1_PORT16_13_D40_U11B.mxf'));
      mediaFile.writeAsStringSync('dummy video');

      final project = buildNeutralProject();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MetadataGeneratorTab(
              project: project,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 clips detectados'), findsOneWidget);

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      dropTarget.onDragDone?.call(
        DropDoneDetails(
          files: [_FakeDropItem(tempDir.path)],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 clips detectados'), findsOneWidget);
      expect(find.text('INFAM_32_2_T1_PORT16_13_D40_U11B.mxf'), findsOneWidget);
    });
  });
}
