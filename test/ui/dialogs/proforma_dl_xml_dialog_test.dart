import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/dialogs/proforma_dl_xml_dialog.dart';
import 'package:renombrata/src/ui/home_screen.dart';

void main() {
  void setupDesktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('ProformaDlXmlDialog Tests', () {
    testWidgets('renders dialog title, batch defaults, and empty state when no files', (tester) async {
      setupDesktop(tester);

      final project = RenombrataProject(
        defaultReel: '001',
        activeCamera: 'A',
        log: ShootingLog(
          metadata: ShootingLogMetadata(
            nomenclature: 'INOCENCIA',
            date: '2026-11-12',
            unit: 'UCR14',
            day: 'D03',
            producer: 'Televisa',
            production: 'INOCENCIA',
            location: 'TERMINAL DE AUTOBUSES DEL SUR',
            audioFormat: '48kHz 24bit',
            frameRate: '23.98',
            videoCodec: 'XAVC',
            responsibleEngineer: 'Ing. Test',
            ingestor: 'ANGEL ESTRADA DIAZ',
          ),
          records: [],
        ),
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

      expect(find.text('Generador de Metadatos XML (DigitalLogic 3.2 / Proforma DL)'), findsOneWidget);
      expect(find.text('ANGEL ESTRADA DIAZ'), findsOneWidget);
      expect(find.text('TERMINAL DE AUTOBUSES DEL SUR'), findsOneWidget);
      expect(find.text('No se detectaron archivos de video en la carpeta seleccionada.'), findsOneWidget);
    });

    testWidgets('populates detected media files, shows parsed convention, and displays clip items', (tester) async {
      setupDesktop(tester);

      final project = RenombrataProject(
        defaultReel: '001',
        activeCamera: 'A',
        log: ShootingLog(
          metadata: ShootingLogMetadata(
            nomenclature: 'INOCENCIA',
            date: '2026-11-12',
            unit: 'UCR14',
            day: 'D03',
            producer: 'Televisa',
            production: 'INOCENCIA',
            location: 'TERMINAL DE AUTOBUSES DEL SUR',
            audioFormat: '48kHz',
            frameRate: '23.98',
            videoCodec: 'XAVC',
            responsibleEngineer: 'Ing. Test',
            ingestor: 'ANGEL ESTRADA DIAZ',
          ),
          records: [],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProformaDlXmlDialog(
              project: project,
              mediaFiles: const [
                '/media/INOCENCIA_01_15_PROT1_CAM1_D03_UCR14.mxf',
                '/media/INOCENCIA_01_15_PROT2_CAM1_D03_UCR14.mxf',
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 clips detectados'), findsOneWidget);
      expect(find.text('INOCENCIA_01_15_PROT1_CAM1_D03_UCR14.mxf'), findsOneWidget);
      expect(find.text('INOCENCIA_01_15_PROT2_CAM1_D03_UCR14.mxf'), findsOneWidget);
      expect(find.textContaining('INOCENCIA_01_15_PROT1_CAM1_D03_UCR14%1_1_D03_U14B'), findsOneWidget);
      expect(find.text('Ver XML'), findsNWidgets(2));
    });

    testWidgets('applying batch defaults updates all clips and toggling take selection changes state', (tester) async {
      setupDesktop(tester);

      final project = RenombrataProject(
        defaultReel: '001',
        activeCamera: 'A',
        log: ShootingLog(
          metadata: ShootingLogMetadata(
            nomenclature: 'INOCENCIA',
            date: '2026-11-12',
            unit: 'UCR14',
            day: 'D03',
            producer: 'Televisa',
            production: 'INOCENCIA',
            location: 'TERMINAL DE AUTOBUSES DEL SUR',
            audioFormat: '48kHz',
            frameRate: '23.98',
            videoCodec: 'XAVC',
            responsibleEngineer: 'Ing. Test',
            ingestor: 'ANGEL ESTRADA DIAZ',
          ),
          records: [],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProformaDlXmlDialog(
              project: project,
              mediaFiles: const [
                '/media/INOCENCIA_01_15_PROT1_CAM1_D03_UCR14.mxf',
                '/media/INOCENCIA_01_15_PROT2_CAM1_D03_UCR14.mxf',
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Aplicar a todos los clips'
      final applyBtn = find.text('Aplicar a todos los clips');
      expect(applyBtn, findsOneWidget);
      await tester.tap(applyBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('Se aplicaron los valores por lote a los 2 clips.'), findsOneWidget);

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

    testWidgets('HomeScreen renders Generar Metadatos XML button and opens ProformaDlXmlDialog', (tester) async {
      setupDesktop(tester);

      final project = RenombrataProject(
        defaultReel: '001',
        activeCamera: 'A',
        log: ShootingLog(
          metadata: ShootingLogMetadata(
            nomenclature: 'INOCENCIA',
            date: '2026-11-12',
            unit: 'UCR14',
            day: 'D03',
            producer: 'Televisa',
            production: 'INOCENCIA',
            location: 'TERMINAL DE AUTOBUSES DEL SUR',
            audioFormat: '48kHz',
            frameRate: '23.98',
            videoCodec: 'XAVC',
            responsibleEngineer: 'Ing. Test',
            ingestor: 'ANGEL ESTRADA DIAZ',
          ),
          records: [],
        ),
      );

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

      // Switch to the 'Renombrador de Medios' tab where the controls bar is located
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final dlBtn = find.byKey(const ValueKey('open_proforma_dl_dialog_button'));
      expect(dlBtn, findsOneWidget);
      expect(find.text('Generar Metadatos XML (Proforma DL)'), findsOneWidget);

      await tester.tap(dlBtn);
      await tester.pumpAndSettle();

      expect(find.text('Generador de Metadatos XML (DigitalLogic 3.2 / Proforma DL)'), findsOneWidget);
    });
  });
}
