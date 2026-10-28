import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import '../models/shooting_log.dart';
import '../utils/timecode_formatter.dart';

class BitacoraParserService {
  /// Fixes common Excel package incompatibilities with Apple Numbers and Televisa exports:
  /// 1. Strips leading slash from Target paths in xl/_rels/workbook.xml.rels
  /// 2. Strips t="inlineStr" from empty or self-closing <c> nodes that lack <is><t>
  static List<int> sanitizeExcelBytes(List<int> rawBytes) {
    try {
      var archive = ZipDecoder().decodeBytes(rawBytes);
      bool modified = false;
      var newArchive = Archive();

      for (var file in archive.files) {
        if (file.name == 'xl/_rels/workbook.xml.rels') {
          var content = utf8.decode(file.content as List<int>, allowMalformed: true);
          if (content.contains('Target="/xl/') || content.contains('Target="xl/')) {
            var fixed = content
                .replaceAll('Target="/xl/', 'Target="')
                .replaceAll('Target="xl/', 'Target="');
            newArchive.addFile(ArchiveFile(file.name, utf8.encode(fixed).length, utf8.encode(fixed)));
            modified = true;
            continue;
          }
        } else if (file.name.startsWith('xl/worksheets/sheet') && file.name.endsWith('.xml')) {
          var content = utf8.decode(file.content as List<int>, allowMalformed: true);
          if (content.contains('t="inlineStr"')) {
            var fixed = content.replaceAllMapped(
              RegExp(r'<c\s+([^>]*?)t="inlineStr"([^>]*?)(/>)'),
              (match) => '<c ${match.group(1)}${match.group(2)}/>',
            );
            fixed = fixed.replaceAllMapped(
              RegExp(r'<c\s+([^>]*?)t="inlineStr"([^>]*?)><is\s*(/|><t\s*/>)?></is></c>'),
              (match) => '<c ${match.group(1)}${match.group(2)}/>',
            );
            if (fixed != content) {
              newArchive.addFile(ArchiveFile(file.name, utf8.encode(fixed).length, utf8.encode(fixed)));
              modified = true;
              continue;
            }
          }
        }
        newArchive.addFile(file);
      }

      if (modified) {
        return ZipEncoder().encode(newArchive)!;
      }
    } catch (_) {}
    return rawBytes;
  }

  static ShootingLog parse(File file) {
    var bytes = file.readAsBytesSync();
    return parseBytes(bytes);
  }

  static ShootingLog parseBytes(List<int> bytes) {
    var fixedBytes = sanitizeExcelBytes(bytes);
    var excel = Excel.decodeBytes(fixedBytes);
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

    // 1. Search the first 12 rows for the header row containing 'CAP', 'ESCE', 'PLAN', 'TOMA', or 'CAM A'
    int headerRowIndex = -1;
    for (int r = 0; r < sheet.maxRows && r < 12; r++) {
      bool hasCapOrScene = false;
      bool hasTakeOrCam = false;
      for (int c = 0; c < sheet.maxColumns; c++) {
        final val = getCellString(c, r).toUpperCase();
        if (val.contains('CAP') || val.contains('ESCE') || val.contains('PLAN') || val.contains('SCENE')) {
          hasCapOrScene = true;
        }
        if (val.contains('TOMA') || val.contains('CAM A') || val.contains('TAKE')) {
          hasTakeOrCam = true;
        }
      }
      if (hasCapOrScene && hasTakeOrCam) {
        headerRowIndex = r;
        break;
      }
    }

    if (headerRowIndex == -1) {
      for (int r = 0; r < sheet.maxRows && r < 12; r++) {
        for (int c = 0; c < sheet.maxColumns; c++) {
          final val = getCellString(c, r).toUpperCase();
          if (val.contains('CAP') ||
              val.contains('ESCE') ||
              val.contains('PLAN') ||
              val.contains('TOMA') ||
              val.contains('CAM A')) {
            headerRowIndex = r;
            break;
          }
        }
        if (headerRowIndex != -1) break;
      }
    }

    if (headerRowIndex == -1) headerRowIndex = 6; // Default to Row 7 (index 6)

    int colCap = -1;
    int colScene = -1;
    int colPlane = -1;
    int colTake = -1;
    int colReel = -1;
    int colTcIn = -1;
    int colTcOut = -1;
    int colObs = -1;
    String? headerReel;
    Map<String, int> camCols = {};

    for (int c = 0; c < sheet.maxColumns; c++) {
      final h = getCellString(c, headerRowIndex).toUpperCase().trim();
      if (h.isEmpty) continue;

      if (h.contains('CAP')) {
        colCap = c;
      } else if (h.contains('ESCE') || h == 'SCENE') {
        colScene = c;
      } else if (h.contains('PLAN')) {
        colPlane = c;
      } else if (h.contains('TOMA') || h == 'TAKE') {
        colTake = c;
      } else if (h.contains('TC IN') || h == 'IN') {
        colTcIn = c;
      } else if (h.contains('TC OUT') || h == 'OUT') {
        colTcOut = c;
      } else if (h.contains('OBS') || h.contains('NOTAS') || h.contains('NOTES')) {
        colObs = c;
      } else if (h.contains('REEL') || h.contains('ROLLO')) {
        colReel = c;
        final rMatch = RegExp(r'(?:REEL|ROLLO)\s+([A-Za-z]?\d+)').firstMatch(h);
        if (rMatch != null) {
          headerReel ??= rMatch.group(1);
        }
      }

      final camMatch = RegExp(r'CAM(?:ARA)?\s*([A-Za-z])(?:\s+(\d+))?').firstMatch(h);
      if (camMatch != null) {
        final camName = camMatch.group(1)!;
        camCols[camName] = c;
        final rNum = camMatch.group(2);
        if (rNum != null) {
          headerReel ??= rNum;
        }
      }
    }

    if (colCap == -1) colCap = 0;
    if (colScene == -1) colScene = 1;
    if (colPlane == -1) colPlane = 2;
    if (colTake == -1) colTake = 3;
    if (camCols.isEmpty) {
      camCols = {'A': 4, 'B': 5, 'C': 6};
    }
    if (colReel == -1) colReel = 7;
    if (colTcIn == -1) colTcIn = 8;
    if (colTcOut == -1) colTcOut = 9;
    if (colObs == -1) colObs = 10;

    String normalizeKey(String s) {
      return s
          .toUpperCase()
          .replaceAll('Á', 'A')
          .replaceAll('É', 'E')
          .replaceAll('Í', 'I')
          .replaceAll('Ó', 'O')
          .replaceAll('Ú', 'U')
          .replaceAll(':', '')
          .trim();
    }

    String findMetadata(List<String> keywords, {String fallback = ''}) {
      final normKeywords = keywords.map(normalizeKey).toList();
      bool labelFound = false;

      for (int r = 0; r < headerRowIndex; r++) {
        for (int c = 0; c < sheet.maxColumns; c++) {
          final rawCell = getCellString(c, r);
          if (rawCell.isEmpty) continue;
          final cellNorm = normalizeKey(rawCell);
          for (var kw in normKeywords) {
            bool matches = false;
            if (cellNorm == kw ||
                cellNorm.startsWith('$kw ') ||
                cellNorm.startsWith('$kw:') ||
                cellNorm.startsWith(kw)) {
              if (kw.length <= 3) {
                matches = RegExp('\\b${RegExp.escape(kw)}\\b').hasMatch(cellNorm);
              } else {
                matches = true;
              }
            }

            if (matches) {
              labelFound = true;

              // 1. Colon-separated key/value in the same cell (e.g., "PRODUCCIÓN: ALCANZAR UNA ESTRELLA")
              if (rawCell.contains(':')) {
                final colonIdx = rawCell.indexOf(':');
                final afterColon = rawCell.substring(colonIdx + 1).trim();
                if (afterColon.isNotEmpty) {
                  return afterColon;
                }
              }

              // 2. Value in subsequent cells on the same row
              for (int nc = c + 1; nc < sheet.maxColumns; nc++) {
                final v = getCellString(nc, r);
                if (v.isNotEmpty) {
                  // If next cell is another label ending with ':', do not treat as value
                  if (v.trim().endsWith(':')) break;
                  return v;
                }
              }
            }
          }
        }
      }

      if (labelFound) {
        return '';
      }

      final cleanFallback = fallback.trim();
      if (cleanFallback.endsWith(':')) return '';
      return cleanFallback;
    }

    var metadata = ShootingLogMetadata(
      production: findMetadata(['PRODUCCION', 'PRODUCCION'], fallback: getCellString(1, 1)),
      producer: findMetadata(['DIR. RESPONSABLE', 'DIR RESPONSABLE', 'PRODUCTOR', 'DIRECTOR'], fallback: getCellString(1, 0)),
      nomenclature: findMetadata(['NOMENCLATURA', 'NOM'], fallback: getCellString(1, 2)),
      location: findMetadata(['LOCACION', 'LOC'], fallback: getCellString(1, 3)),
      date: findMetadata(['FECHA DE GRABACION', 'FECHA'], fallback: getCellString(1, 4)),
      unit: findMetadata(['UNIDAD', 'HORARIO', 'US'], fallback: getCellString(4, 0)),
      day: findMetadata(['GUIA DE GRABACION', 'DIA'], fallback: getCellString(4, 1)),
      audioFormat: findMetadata(['FORMATO', 'AUDIO FORMAT'], fallback: getCellString(4, 2)),
      frameRate: '',
      videoCodec: '',
      responsibleEngineer: findMetadata(['ING. RESPONSABLE', 'ING RESPONSABLE', 'INGENIERO'], fallback: getCellString(4, 3)),
      ingestor: findMetadata(['DATA MANAGER', 'INGESTADOR'], fallback: getCellString(4, 4)),
    );

    List<ShotRecord> records = [];
    int rowIndex = headerRowIndex + 1;

    String lastCap = '';
    String lastScene = '';
    String lastPlane = '';
    int emptyRowCount = 0;

    while (rowIndex < sheet.maxRows) {
      bool isEmptyRow = true;
      for (int c = 0; c < sheet.maxColumns; c++) {
        if (getCellString(c, rowIndex).isNotEmpty) {
          isEmptyRow = false;
          break;
        }
      }
      if (isEmptyRow) {
        emptyRowCount++;
        if (emptyRowCount >= 5) {
          break;
        }
        rowIndex++;
        continue;
      }
      emptyRowCount = 0;

      String cap = colCap >= 0 ? getCellString(colCap, rowIndex) : '';
      String escena = colScene >= 0 ? getCellString(colScene, rowIndex) : '';
      String plano = colPlane >= 0 ? getCellString(colPlane, rowIndex) : '';
      String toma = colTake >= 0 ? getCellString(colTake, rowIndex) : '';

      // Forward-fill for consecutive takes of the same setup
      if (cap.isNotEmpty) {
        lastCap = cap;
      } else if (lastCap.isNotEmpty && toma.isNotEmpty) {
        cap = lastCap;
      }

      if (escena.isNotEmpty && escena != lastScene) {
        // New scene starts: update lastScene and reset lastPlane to this row's plano
        lastScene = escena;
        lastPlane = plano;
      } else {
        // Same scene or empty escena: inherit lastScene if empty
        if (escena.isEmpty && lastScene.isNotEmpty && toma.isNotEmpty) {
          escena = lastScene;
        }
        if (plano.isNotEmpty) {
          lastPlane = plano;
        } else if (lastPlane.isNotEmpty && toma.isNotEmpty) {
          plano = lastPlane;
        }
      }

      if (escena.isEmpty && toma.isEmpty) {
        rowIndex++;
        continue;
      }

      List<CameraTakeRecord> cameras = [];
      void processCam(String name, String value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty ||
            trimmed == '/' ||
            trimmed == '-' ||
            trimmed == '—' ||
            trimmed == '–' ||
            RegExp(r'^[/\\-]+$').hasMatch(trimmed) ||
            trimmed.toUpperCase() == 'X' ||
            trimmed.toUpperCase() == 'N/A') {
          return;
        }
        String formattedClip = trimmed;
        if (int.tryParse(trimmed) != null) {
          formattedClip = int.parse(trimmed).toString().padLeft(3, '0');
        }
        cameras.add(CameraTakeRecord(cameraName: name, clipName: formattedClip));
      }

      for (var entry in camCols.entries) {
        processCam(entry.key, getCellString(entry.value, rowIndex));
      }

      String reel = colReel >= 0 ? getCellString(colReel, rowIndex).trim() : '';
      if (reel.isEmpty && headerReel != null && headerReel.isNotEmpty) {
        reel = headerReel.trim();
      }
      if (reel.isEmpty) {
        reel = '001';
      }
      final camReelMatch = RegExp(r'^[A-Za-z](\d+)$').firstMatch(reel);
      if (camReelMatch != null) {
        reel = camReelMatch.group(1)!;
      }

      String rawTcIn = colTcIn >= 0 ? getCellString(colTcIn, rowIndex) : '';
      String rawTcOut = colTcOut >= 0 ? getCellString(colTcOut, rowIndex) : '';
      String tcIn = rawTcIn.isNotEmpty ? TimecodeUtils.normalize(rawTcIn, '24') : '';
      String tcOut = rawTcOut.isNotEmpty ? TimecodeUtils.normalize(rawTcOut, '24') : '';
      String observaciones = colObs >= 0 ? getCellString(colObs, rowIndex) : '';

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
