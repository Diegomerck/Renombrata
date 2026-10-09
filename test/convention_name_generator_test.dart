import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/services/convention_name_generator.dart';

void main() {
  group('ConventionNameGenerator', () {
    test('generates correctly with Plano and numeric Toma', () {
      final result = ConventionNameGenerator.generate(
        nomenclature: 'MNLDVDL',
        date: '071026',
        scene: '102Y103',
        plane: '1',
        take: '1',
        reel: 'A007_1',
        day: 'D3',
        unit: 'U3',
      );
      expect(result, 'MNLDVDL_071026_102Y103_1_T1_A007_1_D3_U3');
    });

    test('generates correctly without Plano and string Toma (TF)', () {
      final result = ConventionNameGenerator.generate(
        nomenclature: 'MNLDVDL',
        date: '071026',
        scene: '96',
        plane: '',
        take: 'TF',
        reel: 'A007_1',
        day: 'D3',
        unit: 'U3',
      );
      expect(result, 'MNLDVDL_071026_96_TF_A007_1_D3_U3');
    });

    test('generates correctly without Plano (null) and string Toma', () {
      final result = ConventionNameGenerator.generate(
        nomenclature: 'MNLDVDL',
        date: '071026',
        scene: '96',
        plane: null,
        take: 'TF',
        reel: 'A007_1',
        day: 'D3',
        unit: 'U3',
      );
      expect(result, 'MNLDVDL_071026_96_TF_A007_1_D3_U3');
    });

    test('handles whitespace padding gracefully', () {
      final result = ConventionNameGenerator.generate(
        nomenclature: ' MNLDVDL ',
        date: ' 071026 ',
        scene: ' 102Y103 ',
        plane: ' 1 ',
        take: ' 1 ',
        reel: ' A007_1 ',
        day: ' D3 ',
        unit: ' U3 ',
      );
      expect(result, 'MNLDVDL_071026_102Y103_1_T1_A007_1_D3_U3');
    });
    test('normalizes reel with leading letter to active camera', () {
      final result = ConventionNameGenerator.generate(
        nomenclature: 'TEST', date: '010124', scene: '1', take: '1',
        reel: 'A007_1', day: 'D1', unit: 'U1', activeCamera: 'B',
      );
      expect(result, 'TEST_010124_1_T1_B007_1_D1_U1');
    });

    test('normalizes reel starting with digit by prepending active camera', () {
      final result = ConventionNameGenerator.generate(
        nomenclature: 'TEST', date: '010124', scene: '1', take: '1',
        reel: '007_1', day: 'D1', unit: 'U1', activeCamera: 'C',
      );
      expect(result, 'TEST_010124_1_T1_C007_1_D1_U1');
    });

    test('falls back to activeCamera + 001 if reel is empty', () {
      final result = ConventionNameGenerator.generate(
        nomenclature: 'TEST', date: '010124', scene: '1', take: '1',
        reel: '', day: 'D1', unit: 'U1', activeCamera: 'B',
      );
      expect(result, 'TEST_010124_1_T1_B001_D1_U1');
    });

    test('reelOverride overrides whatever logic applies', () {
      final result = ConventionNameGenerator.generate(
        nomenclature: 'TEST', date: '010124', scene: '1', take: '1',
        reel: 'A007_1', day: 'D1', unit: 'U1', activeCamera: 'B', reelOverride: 'Z999_2',
      );
      expect(result, 'TEST_010124_1_T1_Z999_2_D1_U1');
    });
  });
}
