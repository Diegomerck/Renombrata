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

    test('generates GoPro convention with GPR1 reel and 2-digit clip padding', () {
      final result = ConventionNameGenerator.generate(
        nomenclature: 'TODTA',
        date: '010124',
        scene: '10',
        plane: '1',
        take: '1',
        reel: 'A001',
        day: 'D01',
        unit: 'U1',
        clipIndex: '2',
        isGpr: true,
      );
      expect(result, 'TODTA_010124_10_1_T1_GPR1_D01_02_U1');
    });

    test('generates Driving Shot convention with DS unit override', () {
      final result = ConventionNameGenerator.generate(
        nomenclature: 'TODTA',
        date: '010124',
        scene: '10',
        take: '1',
        reel: 'A001',
        day: 'D01',
        unit: 'U1',
        isDs: true,
      );
      expect(result, 'TODTA_010124_10_T1_A001_D01_DS');
    });

    test('generates Drone (DR1) and Free Fly (NFF) conventions', () {
      final drone = ConventionNameGenerator.generate(
        nomenclature: 'TODTA',
        date: '010124',
        scene: '10',
        take: '1',
        reel: 'A001',
        day: 'D01',
        unit: 'U1',
        isDr: true,
      );
      expect(drone, 'TODTA_010124_10_T1_DR1_D01_U1');

      final freeFly = ConventionNameGenerator.generate(
        nomenclature: 'TODTA',
        date: '010124',
        scene: '10',
        take: '1',
        reel: 'A001',
        day: 'D01',
        unit: 'U1',
        isFf: true,
      );
      expect(freeFly, 'TODTA_010124_10_T1_NFF_D01_U1');
    });

    test('generates Toma Falsa (TF) take format', () {
      final tf1 = ConventionNameGenerator.generate(
        nomenclature: 'TODTA',
        date: '010124',
        scene: '10',
        take: '1',
        reel: 'A001',
        day: 'D01',
        unit: 'U1',
        isTf: true,
      );
      expect(tf1, 'TODTA_010124_10_TF1_A001_D01_U1');

      final tfAlready = ConventionNameGenerator.generate(
        nomenclature: 'TODTA',
        date: '010124',
        scene: '10',
        take: 'TF3',
        reel: 'A001',
        day: 'D01',
        unit: 'U1',
        isTf: true,
      );
      expect(tfAlready, 'TODTA_010124_10_TF3_A001_D01_U1');
    });

    test('generates Proforma convention with % separator', () {
      final proforma = ConventionNameGenerator.generate(
        nomenclature: 'TODTA',
        date: '010124',
        scene: '10',
        take: '1',
        reel: 'A001',
        day: 'D01',
        unit: 'U1',
        clipIndex: '5',
        includeProforma: true,
      );
      expect(proforma, 'TODTA_010124_10_T1_A001_D01_5_U1%A001_5_D01_U1');
    });
  });
}
