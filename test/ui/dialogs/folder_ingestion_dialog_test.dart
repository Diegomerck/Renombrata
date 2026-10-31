import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/convention_generator_service.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/ui/dialogs/folder_ingestion_dialog.dart';

void main() {
  void setupDesktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('FolderIngestionDialog Tests', () {
    testWidgets('Existing Bitacora Mode shows Confirmar Cámara dialog and suggests camera', (tester) async {
      setupDesktop(tester);

      final project = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(nomenclature: 'TESTPROD'),
          records: [
            ShotRecord(
              chapter: '1',
              scene: '1',
              take: '1',
              cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
              reel: 'A001',
            ),
          ],
        ),
        defaultReel: 'A001',
        activeCamera: 'A',
        cameras: const [
          CameraConfig(name: 'A', type: CameraType.regular),
          CameraConfig(name: 'B', type: CameraType.freeFly),
        ],
      );

      final scannedFiles = [
        ScannedFile('/media/DJI_0001.MOV'),
        ScannedFile('/media/DJI_0002.MOV'),
      ];

      FolderIngestionResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await FolderIngestionDialog.show(
                    context: context,
                    folderPath: '/media/CARD_DRONE',
                    project: project,
                    scannedFiles: scannedFiles,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify title and content
      expect(find.text('Confirmar Cámara de la Carpeta'), findsOneWidget);
      expect(find.textContaining('CARD_DRONE'), findsOneWidget);
      expect(find.textContaining('2 clips detectados'), findsOneWidget);

      // Verify suggestion: DJI detected as Drone (DR)
      expect(find.textContaining('Cámara sugerida: Cámara DR (Drone (DR))'), findsOneWidget);

      // Verify Administrar Cámaras button exists
      expect(find.byKey(const ValueKey('manage_cameras_button')), findsOneWidget);

      // Tap Aceptar e Importar
      await tester.tap(find.byKey(const ValueKey('accept_import_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.selectedCamera, 'DR');
      expect(result!.cameraType, CameraType.drone);
    });

    testWidgets('Fresh Start Mode shows Configurar Lote de Medios and auto-fills fields reactive to CameraType', (tester) async {
      setupDesktop(tester);

      final emptyProject = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
        cameras: const [CameraConfig(name: 'A', type: CameraType.regular)],
      );

      final scannedFiles = [
        ScannedFile('/media/A001C001.MP4'),
      ];

      FolderIngestionResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await FolderIngestionDialog.show(
                    context: context,
                    folderPath: '/media/EPISODIO_101',
                    project: emptyProject,
                    scannedFiles: scannedFiles,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Title & prompt
      expect(find.text('Configurar Lote de Medios'), findsOneWidget);
      expect(find.textContaining('no hay una bitácora cargada'), findsOneWidget);

      // Check default reel and unit for Regular camera
      final reelField = find.byKey(const ValueKey('fresh_reel_field'));
      final unitField = find.byKey(const ValueKey('fresh_unit_field'));
      expect(tester.widget<TextField>(reelField).controller?.text, 'A001');
      expect(tester.widget<TextField>(unitField).controller?.text, 'U1');

      // Change camera type to Driving Shots (DS)
      final typeSelector = find.byKey(const ValueKey('fresh_camera_type_selector'));
      await tester.tap(typeSelector);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Driving Shots (DS)').last);
      await tester.pumpAndSettle();

      // Unit should auto-fill to 'DS', reel should auto-fill to '01'
      expect(tester.widget<TextField>(unitField).controller?.text, 'DS');
      expect(tester.widget<TextField>(reelField).controller?.text, '01');

      // Change camera type to Drone (DR)
      await tester.tap(typeSelector);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Drone (DR)').last);
      await tester.pumpAndSettle();

      // Unit should revert to U1, reel remains '01' for Drone
      expect(tester.widget<TextField>(unitField).controller?.text, 'U1');
      expect(tester.widget<TextField>(reelField).controller?.text, '01');

      // Confirm
      await tester.tap(find.byKey(const ValueKey('fresh_start_confirm_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.cameraType, CameraType.drone);
      expect(result!.reel, '01');
    });

    test('CameraType.drone automatically applies Drone nomenclature rules (DR1 reel)', () {
      final project = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(
            nomenclature: 'TELEVISA',
            date: '2026-06-08',
            day: '1',
            unit: '1',
          ),
          records: [],
        ),
        defaultReel: '01',
        activeCamera: 'DR',
        cameras: const [
          CameraConfig(name: 'DR', type: CameraType.drone),
        ],
      );

      final conventionName = ConventionGeneratorService.generateConventionName(
        project: project,
        chapter: '1',
        scene: '10',
        take: '1',
        reel: '01',
        camera: 'DR',
        clipIndex: 1,
      );

      // Drone reel is DR1
      expect(conventionName, 'TELEVISA_080626_1_10_T1_DR1_1_D1_U1');
    });

    test('CameraType.drivingShot automatically applies Driving Shots nomenclature rules (DS unit)', () {
      final project = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(
            nomenclature: 'TELEVISA',
            date: '2026-06-08',
            day: '1',
            unit: '1',
          ),
          records: [],
        ),
        defaultReel: '01',
        activeCamera: 'DS',
        cameras: const [
          CameraConfig(name: 'DS', type: CameraType.drivingShot),
        ],
      );

      final conventionName = ConventionGeneratorService.generateConventionName(
        project: project,
        chapter: '1',
        scene: '10',
        take: '1',
        reel: '01',
        camera: 'DS',
        clipIndex: 1,
      );

      // Unit is DS
      expect(conventionName, 'TELEVISA_080626_1_10_T1_DS001_1_D1_DS');
    });
  });
}

