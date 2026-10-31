import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';

void main() {
  group('CameraConfig and CameraType Tests', () {
    test('CameraType label extension returns correct Spanish LATAM labels', () {
      expect(CameraType.regular.label, 'Regular');
      expect(CameraType.drivingShot.label, 'Driving Shots (DS)');
      expect(CameraType.freeFly.label, 'Free Fly (FF)');
      expect(CameraType.ronin.label, 'Ronin');
      expect(CameraType.goPro.label, 'GoPro (GPR)');
      expect(CameraType.drone.label, 'Drone (DR)');
    });

    test('CameraConfig serialization and deserialization works correctly', () {
      const config = CameraConfig(name: 'DR', type: CameraType.drone);
      final json = config.toJson();
      expect(json['name'], 'DR');
      expect(json['type'], 'drone');

      final deserialized = CameraConfig.fromJson(json);
      expect(deserialized.name, 'DR');
      expect(deserialized.type, CameraType.drone);
    });

    test('CameraConfig defaults to CameraType.regular for unknown types', () {
      final deserialized = CameraConfig.fromJson({
        'name': 'X',
        'type': 'unknown_type',
      });
      expect(deserialized.name, 'X');
      expect(deserialized.type, CameraType.regular);
    });

    test('RenombrataProject backward compatibility with older json containing only cameraNames', () {
      final olderJson = {
        'version': '2.0',
        'defaultReel': 'A001',
        'activeCamera': 'B',
        'cameraNames': ['A', 'B', 'DR'],
        'records': <Map<String, dynamic>>[],
      };

      final project = RenombrataProject.fromJson(olderJson);
      expect(project.cameras.length, 3);
      expect(project.cameras[0].name, 'A');
      expect(project.cameras[0].type, CameraType.regular);
      expect(project.cameras[1].name, 'B');
      expect(project.cameras[1].type, CameraType.regular);
      expect(project.cameras[2].name, 'DR');
      expect(project.cameras[2].type, CameraType.regular);

      expect(project.cameraNames, ['A', 'B', 'DR']);
      expect(project.getCameraType('DR'), CameraType.regular);
    });

    test('RenombrataProject serialization preserves cameras with specialized types', () {
      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'DR',
        cameras: const [
          CameraConfig(name: 'A', type: CameraType.regular),
          CameraConfig(name: 'B', type: CameraType.drivingShot),
          CameraConfig(name: 'DR', type: CameraType.drone),
        ],
      );

      final json = project.toJson();
      expect(json['cameras'], isA<List>());
      final camerasJson = json['cameras'] as List;
      expect(camerasJson.length, 3);
      expect(camerasJson[2]['name'], 'DR');
      expect(camerasJson[2]['type'], 'drone');

      final restored = RenombrataProject.fromJson(json);
      expect(restored.getCameraType('A'), CameraType.regular);
      expect(restored.getCameraType('B'), CameraType.drivingShot);
      expect(restored.getCameraType('DR'), CameraType.drone);
      expect(restored.getCameraType('unknown'), CameraType.regular);
    });

    test('RenombrataProject copyWith with cameras or cameraNames works seamlessly', () {
      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
        cameras: const [
          CameraConfig(name: 'A', type: CameraType.regular),
          CameraConfig(name: 'DR', type: CameraType.drone),
        ],
      );

      // copyWith preserving types when passing cameraNames
      final updatedWithNames = project.copyWith(cameraNames: ['A', 'DR', 'C']);
      expect(updatedWithNames.cameras.length, 3);
      expect(updatedWithNames.cameras[0].type, CameraType.regular);
      expect(updatedWithNames.cameras[1].type, CameraType.drone);
      expect(updatedWithNames.cameras[2].type, CameraType.regular);

      // copyWith passing new cameras list
      final updatedWithConfigs = project.copyWith(
        cameras: const [
          CameraConfig(name: 'B', type: CameraType.freeFly),
        ],
      );
      expect(updatedWithConfigs.cameras.length, 1);
      expect(updatedWithConfigs.cameras[0].name, 'B');
      expect(updatedWithConfigs.cameras[0].type, CameraType.freeFly);
    });
  });
}

