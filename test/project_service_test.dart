import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/project_service.dart';

void main() {
  group('ProjectService and JSON Serialization', () {
    late String testPath;

    setUp(() {
      testPath = 'test_project.renombrata';
    });

    tearDown(() {
      final file = File(testPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    test('serializes and deserializes correctly', () async {
      final log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'TEST',
          date: '010124',
          unit: 'U1',
          day: 'D1',
          producer: 'P',
          production: 'PR',
          location: 'L',
          audioFormat: 'F',
          frameRate: '24fps',
          videoCodec: 'ProRes',
          responsibleEngineer: 'E',
          ingestor: 'I',
        ),
        records: [
          ShotRecord(
            chapter: '1',
            scene: '1',
            take: '1',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
            reel: 'A007_1',
          ),
        ],
      );

      final project = RenombrataProject(
        log: log,
        defaultReel: 'A007_1',
        activeCamera: 'A',
      );

      await ProjectService.saveProject(project, testPath);

      final loadedProject = await ProjectService.loadProject(testPath);

      expect(loadedProject.version, '2.0');
      expect(loadedProject.defaultReel, 'A007_1');
      expect(loadedProject.activeCamera, 'A');
      expect(loadedProject.log.metadata.nomenclature, 'TEST');
      expect(loadedProject.showChapter, isTrue);
      expect(loadedProject.showPlane, isTrue);
      expect(loadedProject.showMos, isTrue);
      expect(loadedProject.showTcOut, isTrue);

      // Verify custom visibility flags serialize and deserialize
      final customProject = project.copyWith(
        showChapter: false,
        showPlane: false,
        showMos: false,
        showTcOut: false,
      );
      await ProjectService.saveProject(customProject, testPath);
      final loadedCustom = await ProjectService.loadProject(testPath);
      expect(loadedCustom.showChapter, isFalse);
      expect(loadedCustom.showPlane, isFalse);
      expect(loadedCustom.showMos, isFalse);
      expect(loadedCustom.showTcOut, isFalse);
    });
  });
}
