import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/bitacora_parser_service.dart';

void main() {
  group('BitacoraParserService', () {
    test('parses metadata and shot records correctly', () {
      var excel = Excel.createExcel();
      var sheetName = excel.tables.keys.first;
      var sheet = excel[sheetName];

      // Metadata
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0), TextCellValue('Producer Name')); // B1
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1), TextCellValue('Production Title')); // B2
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2), TextCellValue('MNLDVDL')); // B3
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3), TextCellValue('Location A')); // B4
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 4), TextCellValue('071026')); // B5

      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0), TextCellValue('U3')); // E1
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1), TextCellValue('D3')); // E2
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 2), TextCellValue('Format X')); // E3
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 3), TextCellValue('Eng Name')); // E4
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 4), TextCellValue('Ingestor Name')); // E5

      // Header row (Row 7 -> index 6)
      List<String> headers = ['CAP', 'ESCENA', 'PLANO', 'TOMA', 'CAM A', 'CAM B', 'CAM C', 'REEL', 'TC IN', 'TC OUT', 'OBSERVACIONES'];
      for (int i = 0; i < headers.length; i++) {
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 6), TextCellValue(headers[i]));
      }

      // Data Row 1: Valid numeric take, numeric cam A, string cam B, missing cam C
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 7), IntCellValue(1));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 7), TextCellValue('102Y103'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 7), IntCellValue(1)); // PLANO
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 7), IntCellValue(1)); // TOMA
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 7), IntCellValue(1)); // CAM A -> should pad to '001'
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 7), TextCellValue('X100')); // CAM B -> should be 'X100'
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 7), TextCellValue('A007_1')); // REEL
      
      // Data Row 2: TF take, missing plano, empty cam A, valid cam C
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 8), IntCellValue(1));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 8), TextCellValue('96'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 8), TextCellValue('TF')); // TOMA
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 8), TextCellValue('')); // CAM B is empty string
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 8), IntCellValue(2)); // CAM C -> should pad to '002'
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 8), TextCellValue('A007_1')); // REEL

      ShootingLog log = BitacoraParserService.parseExcel(excel);

      // Verify metadata
      expect(log.metadata.nomenclature, 'MNLDVDL');
      expect(log.metadata.date, '071026');
      expect(log.metadata.unit, 'U3');
      expect(log.metadata.day, 'D3');
      expect(log.metadata.producer, 'Producer Name');

      // Verify records length
      expect(log.records.length, 2);

      // Verify Record 1
      var r1 = log.records[0];
      expect(r1.scene, '102Y103');
      expect(r1.plane, '1');
      expect(r1.take, '1');
      expect(r1.reel, 'A007_1');
      expect(r1.cameras.length, 2);
      expect(r1.cameras[0].cameraName, 'A');
      expect(r1.cameras[0].clipName, '001'); // Zero padded
      expect(r1.cameras[1].cameraName, 'B');
      expect(r1.cameras[1].clipName, 'X100'); // Literal

      // Verify Record 2
      var r2 = log.records[1];
      expect(r2.scene, '96');
      expect(r2.plane, isNull);
      expect(r2.take, 'TF');
      expect(r2.cameras.length, 1);
      expect(r2.cameras[0].cameraName, 'C');
      expect(r2.cameras[0].clipName, '002'); // Zero padded
    });

    test('parses TelevisaUnivision REPORTE D20.xlsx correctly with inheritance and markers', () {
      final file = File('Test Files/REPORTE D20.xlsx');
      expect(file.existsSync(), isTrue);

      final log = BitacoraParserService.parse(file);

      // Verify metadata
      expect(log.metadata.production, 'ALCANZAR UNA ESTRELLA');
      expect(log.metadata.date, '10-10-2026');
      expect(log.metadata.unit, 'US:1');
      expect(log.metadata.day, 'D20');
      expect(log.metadata.ingestor, 'OMAR CURIEL');
      expect(log.metadata.responsibleEngineer, 'ALFONSO PALACIOS');
      expect(log.metadata.producer, isEmpty);

      // Verify records length
      expect(log.records.isNotEmpty, isTrue);

      // Verify Row 1: Cap 15, Scene 3, Plane 1, Take 1, Reel 038, TC In 15:01, TC Out 15:04
      final r1 = log.records[0];
      expect(r1.chapter, '15');
      expect(r1.scene, '3');
      expect(r1.plane, '1');
      expect(r1.take, '1');
      expect(r1.reel, '038');
      expect(r1.tcIn, '15:01:00:00');
      expect(r1.tcOut, '15:04:00:00');

      // Verify Row 2 inherits: Cap 15, Scene 3, Plane 1, Take 2, Reel 038
      final r2 = log.records[1];
      expect(r2.chapter, '15');
      expect(r2.scene, '3');
      expect(r2.plane, '1');
      expect(r2.take, '2');
      expect(r2.reel, '038');

      // Verify Camera clip with '/' is not added to cameras list
      // In REPORTE D20.xlsx, row index 6 (take 2 of scene 31Y33) has '/' on CAM A
      final takeWithSlash = log.records.firstWhere(
        (r) => r.scene == '31Y33' && r.take == '2',
      );
      expect(takeWithSlash.cameras.any((c) => c.cameraName == 'A'), isFalse);
      expect(takeWithSlash.cameras.any((c) => c.clipName.contains('/')), isFalse);
      expect(takeWithSlash.cameras.length, 2); // B and C only
    });

    test('parses colon-separated key-value metadata in the same cell and keyword variants', () {
      var excel = Excel.createExcel();
      var sheetName = excel.tables.keys.first;
      var sheet = excel[sheetName];

      // Single-cell colon separated metadata
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0), TextCellValue('PRODUCCIÓN: SERIE LATAM'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0), TextCellValue('DIR. RESPONSABLE: GUILLERMO DEL TORO'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1), TextCellValue('LOCACIÓN: FORO 3'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1), TextCellValue('FECHA DE GRABACIÓN: 121026'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2), TextCellValue('GUÍA DE GRABACIÓN: D05'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 2), TextCellValue('HORARIO: US:2'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3), TextCellValue('DATA MANAGER: MARIANA SOSA'));

      // Header row at row 5
      List<String> headers = ['CAP', 'ESCENA', 'PLANO', 'TOMA', 'CAM A 042', 'REEL 042'];
      for (int i = 0; i < headers.length; i++) {
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 5), TextCellValue(headers[i]));
      }

      // Row 6
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 6), TextCellValue('1'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 6), TextCellValue('10'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 6), TextCellValue('1'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 6), TextCellValue('1'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 6), TextCellValue('1'));

      final log = BitacoraParserService.parseExcel(excel);

      expect(log.metadata.production, 'SERIE LATAM');
      expect(log.metadata.producer, 'GUILLERMO DEL TORO');
      expect(log.metadata.location, 'FORO 3');
      expect(log.metadata.date, '121026');
      expect(log.metadata.day, 'D05');
      expect(log.metadata.unit, 'US:2');
      expect(log.metadata.ingestor, 'MARIANA SOSA');
      expect(log.records.first.reel, '042');
    });

    test('strips camera letter prefix from reel in Excel row', () {
      var excel = Excel.createExcel();
      var sheetName = excel.tables.keys.first;
      var sheet = excel[sheetName];

      List<String> headers = ['CAP', 'ESCENA', 'TOMA', 'CAM A', 'REEL'];
      for (int i = 0; i < headers.length; i++) {
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0), TextCellValue(headers[i]));
      }

      // Row 1 with A001
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1), TextCellValue('1'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1), TextCellValue('10'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1), TextCellValue('1'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1), TextCellValue('1'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1), TextCellValue('A001'));

      // Row 2 with B002
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2), TextCellValue('1'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2), TextCellValue('10'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2), TextCellValue('2'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 2), TextCellValue('2'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 2), TextCellValue('B002'));

      final log = BitacoraParserService.parseExcel(excel);
      expect(log.records.length, 2);
      expect(log.records[0].reel, '001');
      expect(log.records[1].reel, '002');
    });
  });
}

