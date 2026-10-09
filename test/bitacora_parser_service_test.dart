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
      // Usually strings, not strictly needed for the parser, but let's add them
      List<String> headers = ['CAP', 'ESCENA', 'PLANO', 'TOMA', 'CAM A', 'CAM B', 'CAM C', 'REEL', 'TC IN', 'TC OUT', 'OBSERVACIONES'];
      for (int i = 0; i < headers.length; i++) {
        sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 6), TextCellValue(headers[i]));
      }

      // Data Row 1: Valid numeric take, numeric cam A, string cam B, missing cam C
      // Row 8 -> index 7
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 7), IntCellValue(1));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 7), TextCellValue('102Y103'));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 7), IntCellValue(1)); // PLANO
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 7), IntCellValue(1)); // TOMA
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 7), IntCellValue(1)); // CAM A -> should pad to '001'
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 7), TextCellValue('X100')); // CAM B -> should be 'X100'
      // CAM C is left blank
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 7), TextCellValue('A007_1')); // REEL
      
      // Data Row 2: TF take, missing plano, empty cam A, valid cam C
      // Row 9 -> index 8
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 8), IntCellValue(1));
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 8), TextCellValue('96'));
      // PLANO is left blank
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 8), TextCellValue('TF')); // TOMA
      // CAM A is left blank
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
  });
}
