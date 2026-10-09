import 'dart:io';
import 'package:excel/excel.dart';
import '../models/shooting_log.dart';

class BitacoraParserService {
  static ShootingLog parse(File file) {
    var bytes = file.readAsBytesSync();
    var excel = Excel.decodeBytes(bytes);
    return parseExcel(excel);
  }

  static ShootingLog parseExcel(Excel excel) {
    var sheetName = excel.tables.keys.first;
    var sheet = excel.tables[sheetName]!;

    String getCellString(int col, int row) {
      if (row >= sheet.maxRows || col >= sheet.maxColumns) return '';
      var val = sheet.rows[row][col]?.value;
      if (val == null) return '';
      return val.toString().trim();
    }

    // Extract Metadata
    var metadata = ShootingLogMetadata(
      producer: getCellString(1, 0), // B1
      production: getCellString(1, 1), // B2
      nomenclature: getCellString(1, 2), // B3
      location: getCellString(1, 3), // B4
      date: getCellString(1, 4), // B5
      unit: getCellString(4, 0), // E1
      day: getCellString(4, 1), // E2
      format: getCellString(4, 2), // E3
      responsibleEngineer: getCellString(4, 3), // E4
      ingestor: getCellString(4, 4), // E5
    );

    // Extract Records starting from Row 8 (index 7)
    List<ShotRecord> records = [];
    int rowIndex = 7;

    while (rowIndex < sheet.maxRows) {
      // Check if entire row is essentially empty
      bool isEmptyRow = true;
      for (int c = 0; c <= 10; c++) {
        if (getCellString(c, rowIndex).isNotEmpty) {
          isEmptyRow = false;
          break;
        }
      }
      
      if (isEmptyRow) {
        // Stop parsing when entirely blank row is encountered
        break;
      }

      String cap = getCellString(0, rowIndex);
      String escena = getCellString(1, rowIndex);
      String plano = getCellString(2, rowIndex);
      String toma = getCellString(3, rowIndex);
      
      String camA = getCellString(4, rowIndex);
      String camB = getCellString(5, rowIndex);
      String camC = getCellString(6, rowIndex);
      
      String reel = getCellString(7, rowIndex);
      String tcIn = getCellString(8, rowIndex);
      String tcOut = getCellString(9, rowIndex);
      String observaciones = getCellString(10, rowIndex);

      // Process cameras
      List<CameraTakeRecord> cameras = [];
      void processCam(String name, String value) {
        if (value.isNotEmpty) {
          // Pad numeric clip to 3 digits
          String formattedClip = value;
          if (int.tryParse(value) != null) {
            formattedClip = int.parse(value).toString().padLeft(3, '0');
          }
          cameras.add(CameraTakeRecord(cameraName: name, clipName: formattedClip));
        }
      }

      processCam('A', camA);
      processCam('B', camB);
      processCam('C', camC);

      records.add(ShotRecord(
        chapter: cap,
        scene: escena,
        plane: plano.isNotEmpty ? plano : null,
        take: toma,
        cameras: cameras,
        reel: reel,
        tcIn: tcIn.isNotEmpty ? tcIn : null,
        tcOut: tcOut.isNotEmpty ? tcOut : null,
        observations: observaciones.isNotEmpty ? observaciones : null,
      ));

      rowIndex++;
    }

    return ShootingLog(
      metadata: metadata,
      records: records,
    );
  }
}
