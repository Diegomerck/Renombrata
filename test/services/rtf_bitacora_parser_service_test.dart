import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/services/rtf_bitacora_parser_service.dart';

void main() {
  group('RtfBitacoraParserService.extractPlainText', () {
    test('returns plain text unmodified', () {
      const text = 'TODTA_2_13_P1_T1_A001_D01_1_U1\nTODTA_2_13_P1_T2_A001_D01_2_U1';
      expect(RtfBitacoraParserService.extractPlainText(text), text);
    });

    test('strips standard RTF header, font table, and color table', () {
      const rtf = r'{\rtf1\ansi\ansicpg1252\cocoartf2639'
          r'{\fonttbl\f0\fswiss\fcharset0 Helvetica;}'
          r'{\colortbl;\red255\green255\blue255;}'
          r'{\*\expandedcolortbl;;}'
          r'\pard\tx560\tx1120\pardirnatural\partightenfactor0'
          r'\f0\fs24 \cf0 TODTA_2_13_P1_T1_A001_D01_1_U1\par'
          r'TODTA_2_13_P1_T2_A001_D01_2_U1\par'
          r'}';

      final result = RtfBitacoraParserService.extractPlainText(rtf);
      final lines = result.split(RegExp(r'\r?\n')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

      expect(lines, [
        'TODTA_2_13_P1_T1_A001_D01_1_U1',
        'TODTA_2_13_P1_T2_A001_D01_2_U1',
      ]);
    });

    test('decodes hex escapes for accented Spanish characters', () {
      const rtf = r'{\rtf1\ansi\deff0 {\fonttbl{\f0 Helvetica;}}\pard'
          r" \'e1\'e9\'ed\'f3\'fa\'f1\par}";

      final result = RtfBitacoraParserService.extractPlainText(rtf).trim();
      expect(result, 'áéíóúñ');
    });

    test('decodes unicode character escapes', () {
      const rtf = r'{\rtf1\ansi\deff0\pard \u241?test\par}';
      final result = RtfBitacoraParserService.extractPlainText(rtf).trim();
      expect(result, 'ñtest');
    });
  });

  group('RtfBitacoraParserService.parseLines', () {
    test('parses standard Televisa/ViX conventions with and without plano', () {
      const sample = '''
TODTA_2_13_P1_T1_A001_D01_1_U1
TODTA_2_13_P2_T2_A001_D01_2_U1
MNMIMAPE_15_28_T1_B001_D12_10_U2
TODTA_45Y46_30Y1Y1RC_P1_TF1_A029_D32_5_DS%A029_5_D32_DS
''';

      final entries = RtfBitacoraParserService.parseLines(sample);
      expect(entries.length, 4);

      // Entry 1
      expect(entries[0].nomenclature, 'TODTA');
      expect(entries[0].chapter, '2');
      expect(entries[0].scene, '13');
      expect(entries[0].plane, '1');
      expect(entries[0].take, 'T1');
      expect(entries[0].reel, 'A001');
      expect(entries[0].day, 'D01');
      expect(entries[0].clipIndex, '1');
      expect(entries[0].unit, 'U1');
      expect(entries[0].subConvention, isNull);
      expect(entries[0].isTf, isFalse);

      // Entry 3 (no plano)
      expect(entries[2].nomenclature, 'MNMIMAPE');
      expect(entries[2].chapter, '15');
      expect(entries[2].scene, '28');
      expect(entries[2].plane, isNull);
      expect(entries[2].take, 'T1');
      expect(entries[2].reel, 'B001');

      // Entry 4 (Toma Falsa + Driving Shot + sub-convention)
      expect(entries[3].nomenclature, 'TODTA');
      expect(entries[3].chapter, '45Y46');
      expect(entries[3].scene, '30Y1Y1RC');
      expect(entries[3].plane, '1');
      expect(entries[3].take, 'TF1');
      expect(entries[3].isTf, isTrue);
      expect(entries[3].isDs, isTrue);
      expect(entries[3].reel, 'A029');
      expect(entries[3].subConvention, 'A029_5_D32_DS');
    });

    test('detects special camera conventions: GoPro, Drone, Free Fly', () {
      const sample = '''
PROD_1_1_T1_GPR1_D01_1_U1
PROD_1_1_T2_DR1_D01_2_U1
PROD_1_1_T3_NFF_D01_3_U1
''';

      final entries = RtfBitacoraParserService.parseLines(sample);
      expect(entries.length, 3);

      expect(entries[0].isGpr, isTrue);
      expect(entries[1].isDr, isTrue);
      expect(entries[2].isFf, isTrue);
    });

    test('ignores non-convention lines and blank lines', () {
      const sample = '''
Bitacora D20 - 26/09/2021
Camara A - Sony Venice

TODTA_2_13_P1_T1_A001_D01_1_U1

Fin de bitacora
''';

      final entries = RtfBitacoraParserService.parseLines(sample);
      expect(entries.length, 1);
      expect(entries[0].take, 'T1');
    });
  });

  group('RtfBitacoraParserService.segmentByReel', () {
    test('groups entries by reel correctly', () {
      final entries = RtfBitacoraParserService.parseLines('''
TODTA_1_1_T1_A001_D1_1_U1
TODTA_1_1_T2_A001_D1_2_U1
TODTA_1_1_T1_B001_D1_1_U1
TODTA_1_1_T1_GPR1_D1_1_U1
''');

      final segmented = RtfBitacoraParserService.segmentByReel(entries);
      expect(segmented.keys.toList(), ['A001', 'B001', 'GPR1']);
      expect(segmented['A001']!.length, 2);
      expect(segmented['B001']!.length, 1);
      expect(segmented['GPR1']!.length, 1);
    });
  });

  group('RtfBitacoraParserService.toShootingLog', () {
    test('converts parsed entries to a fully configured ShootingLog', () {
      final entries = RtfBitacoraParserService.parseLines('''
TODTA_2_13_P1_T1_A001_D01_1_U1
TODTA_2_13_P1_TF2_A001_D01_2_U1
TODTA_2_14_T1_B001_D01_3_U1%B001_3_D01_U1
''');

      final log = RtfBitacoraParserService.toShootingLog(entries);

      expect(log.metadata.production, 'TODTA');
      expect(log.metadata.nomenclature, 'TODTA');
      expect(log.metadata.day, 'D01');
      expect(log.metadata.unit, 'U1');
      expect(log.records.length, 3);

      // Record 1
      expect(log.records[0].chapter, '2');
      expect(log.records[0].scene, '13');
      expect(log.records[0].plane, '1');
      expect(log.records[0].take, '1');
      expect(log.records[0].isTf, isFalse);
      expect(log.records[0].reel, 'A001');

      // Record 2 (Toma Falsa: TF2 -> clean take '2', isTf: true)
      expect(log.records[1].take, '2');
      expect(log.records[1].isTf, isTrue);

      // Record 3 (Observations populated from subConvention)
      expect(log.records[2].observations, 'B001_3_D01_U1');
      expect(log.records[2].cameras.first.cameraName, 'B');
    });
  });
}
