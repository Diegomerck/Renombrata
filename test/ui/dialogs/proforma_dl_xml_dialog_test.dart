import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/dialogs/proforma_dl_xml_dialog.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:renombrata/src/ui/tabs/metadata_generator_tab.dart';

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
    String production = 'INFAM',
  }) {
    return RenombrataProject(
      defaultReel: '001',
      activeCamera: 'A',
      log: ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: production,
          date: '2026-11-12',
          unit: 'U11B',
          day: 'D40',
          producer: '',
          production: production,
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

  group('ProformaDlXmlDialog Tests', () {
    testWidgets('renders neutral empty defaults when project metadata is empty', (tester) async {
      setupDesktop(tester);

      final project = buildNeutralProject();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProformaDlXmlDialog(
              project: project,
              mediaFiles: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Generador de Metadatos XML (DigitalLogic 3.2 / Proforma DL)'), findsOneWidget);
      expect(find.text('No se detectaron archivos de video en la carpeta seleccionada.'), findsOneWidget);

      // Ensure no hardcoded production strings appear anywhere
      expect(find.text('ANGEL ESTRADA DIAZ'), findsNothing);
      expect(find.text('TERMINAL DE AUTOBUSES DEL SUR'), findsNothing);
      expect(find.text('LLEGA INOCENCIA EN AUTOBUS'), findsNothing);
      expect(find.text('OK SLOG 3'), findsNothing);
      expect(find.text('MIX Y MULTITRACK'), findsNothing);
      expect(find.text('U14B'), findsNothing);
    });

    testWidgets('pulls ingestor and location from project metadata when non-empty', (tester) async {
      setupDesktop(tester);

      final project = buildNeutralProject(
        ingestor: 'Operador Bitacora',
        location: 'Foro 3',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProformaDlXmlDialog(
              project: project,
              mediaFiles: const [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Operador Bitacora'), findsOneWidget);
      expect(find.text('Foro 3'), findsOneWidget);
    });

    testWidgets('populates detected media files and dynamically derives card and unit sub-convention', (tester) async {
      setupDesktop(tester);

      final project = buildNeutralProject();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProformaDlXmlDialog(
              project: project,
              mediaFiles: const [
                '/media/INFAM_32_2_T1_PORT16_13_D40_U11B.mxf',
                '/media/INFAM_32_2_T2_CAM1_14_D40_U11B.mxf',
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 clips detectados'), findsOneWidget);
      expect(find.text('INFAM_32_2_T1_PORT16_13_D40_U11B.mxf'), findsOneWidget);
      expect(find.text('INFAM_32_2_T2_CAM1_14_D40_U11B.mxf'), findsOneWidget);
      expect(
        find.textContaining('INFAM_32_2_T1_PORT16_13_D40_U11B%16_1_D40_U11B'),
        findsOneWidget,
      );
      expect(
        find.textContaining('INFAM_32_2_T2_CAM1_14_D40_U11B%1_2_D40_U11B'),
        findsOneWidget,
      );
      expect(find.text('Ver XML'), findsNWidgets(2));
    });

    testWidgets('applying batch defaults preserves dynamic card/unit when blank and toggles take selection', (tester) async {
      setupDesktop(tester);

      final project = buildNeutralProject();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProformaDlXmlDialog(
              project: project,
              mediaFiles: const [
                '/media/INFAM_32_2_T1_PORT16_13_D40_U11B.mxf',
                '/media/INFAM_32_2_T2_CAM1_14_D40_U11B.mxf',
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Aplicar a todos los clips' with Card/Reel and Sub-Reel left blank
      final applyBtn = find.text('Aplicar a todos los clips');
      expect(applyBtn, findsOneWidget);
      await tester.tap(applyBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Se aplicaron los valores por lote a los 2 clips.'), findsOneWidget);
      expect(
        find.textContaining('INFAM_32_2_T1_PORT16_13_D40_U11B%16_1_D40_U11B'),
        findsOneWidget,
      );

      // Verify checkboxes for Toma Seleccionada exist
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsNWidgets(2));

      // Tap the first checkbox to toggle selection
      await tester.tap(checkboxes.first);
      await tester.pumpAndSettle();

      // Now we have one 'NO' and one 'SÍ'
      expect(find.text('NO'), findsOneWidget);
      expect(find.text('SÍ'), findsOneWidget);
    });

    testWidgets('HomeScreen button in Renombrador tab switches to Generador de Metadata tab', (tester) async {
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

      // Switch to the 'Renombrador' tab where the controls bar is located
      await tester.tap(find.text('Renombrador'));
      await tester.pumpAndSettle();

      final dlBtn = find.byKey(const ValueKey('open_proforma_dl_dialog_button'));
      expect(dlBtn, findsOneWidget);
      expect(find.text('Generar Metadatos XML (Proforma DL)'), findsOneWidget);

      await tester.tap(dlBtn);
      await tester.pumpAndSettle();

      // Should now be on the Generador de Metadata tab (Tab 3)
      expect(find.byType(MetadataGeneratorTab), findsOneWidget);
      expect(find.text('Generador de Metadatos XML (DigitalLogic 3.2 / Proforma DL)'), findsOneWidget);
    });
  });
}
