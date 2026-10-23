import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/models/dry_run_report.dart';

class ReportExportService {
  static Future<String> exportReport({
    required String mediaFolderPath,
    required ShootingLog log,
    required DryRunReport report,
    required String activeCamera,
  }) async {
    final metadata = log.metadata;
    final String baseFileName = 'Reporte_Renombrata_${metadata.nomenclature}_${metadata.date}_${metadata.day}_Cam$activeCamera';
    final String xlsxPath = p.join(mediaFolderPath, '$baseFileName.xlsx');
    final String csvPath = p.join(mediaFolderPath, '$baseFileName.csv');

    // Filter proposals: only video files (ignore XML for the report rows to avoid duplication, 
    // or just list them all? Usually, we just want to list the clip entries).
    // Let's list one row per video proposal, ignoring the companion XMLs to keep the report clean.
    final List<RenameProposal> videoProposals = report.proposals.where((p) => !p.isCompanionFile).toList();

    // 1. Generate Excel
    var excel = Excel.createExcel();
    var sheet = excel['Reporte'];
    excel.delete('Sheet1'); // Remove default sheet

    // Set Column Widths
    sheet.setColumnWidth(0, 24.0);
    sheet.setColumnWidth(1, 52.0);
    sheet.setColumnWidth(2, 52.0);
    sheet.setColumnWidth(3, 16.0);
    sheet.setColumnWidth(4, 12.0);
    sheet.setColumnWidth(5, 12.0);
    sheet.setColumnWidth(6, 14.0);
    sheet.setColumnWidth(7, 14.0);
    sheet.setColumnWidth(8, 16.0);
    sheet.setColumnWidth(9, 18.0);
    sheet.setColumnWidth(10, 18.0);
    sheet.setColumnWidth(11, 12.0);
    sheet.setColumnWidth(12, 40.0);

    final now = DateTime.now();
    final formattedTimestamp = 
        "${now.year.toString().padLeft(4, '0')}-"
        "${now.month.toString().padLeft(2, '0')}-"
        "${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:"
        "${now.minute.toString().padLeft(2, '0')}:"
        "${now.second.toString().padLeft(2, '0')}";

    // Header Block
    sheet.appendRow([TextCellValue('PRODUCCIÓN:'), TextCellValue(metadata.production), TextCellValue('UNIDAD:'), TextCellValue(metadata.unit)]);
    sheet.appendRow([TextCellValue('PRODUCTOR:'), TextCellValue(metadata.producer), TextCellValue('DÍA:'), TextCellValue(metadata.day)]);
    sheet.appendRow([TextCellValue('NOMENCLATURA:'), TextCellValue(metadata.nomenclature), TextCellValue('FRAME RATE:'), TextCellValue(metadata.frameRate)]);
    sheet.appendRow([TextCellValue('LOCACIÓN:'), TextCellValue(metadata.location), TextCellValue('VIDEO CODEC:'), TextCellValue(metadata.videoCodec)]);
    sheet.appendRow([TextCellValue('FECHA:'), TextCellValue(metadata.date), TextCellValue('AUDIO FORMAT:'), TextCellValue(metadata.audioFormat)]);
    sheet.appendRow([TextCellValue('ING. RESPONSABLE:'), TextCellValue(metadata.responsibleEngineer), TextCellValue('INGESTADOR:'), TextCellValue(metadata.ingestor)]);
    sheet.appendRow([TextCellValue('FECHA EXPORTACIÓN:'), TextCellValue(formattedTimestamp)]);
    sheet.appendRow([]); // Empty row 7

    // Data Table Headers
    final List<String> headers = [
      'ESTADO',
      'ARCHIVO ORIGINAL',
      'NOMBRE CONVENCIÓN',
      'CAPÍTULO',
      'ESCENA',
      'PLANO',
      'TOMA',
      'CÁMARA',
      'CLIP NUM',
      'REEL',
      'TC IN',
      'TC OUT',
      'MOS',
      'OBSERVACIONES'
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // Data Rows
    List<List<String>> csvData = [headers];

    for (var proposal in videoProposals) {
      String estado = _statusToString(proposal.status);
      String originalFile = proposal.originalFilePath != null ? p.basename(proposal.originalFilePath!) : '—';
      String conventionName = proposal.status == ProposalStatus.unmatchedClip ? '—' : proposal.proposedFileName;
      
      String capitulo = proposal.associatedRecord?.chapter ?? '—';
      String escena = proposal.associatedRecord?.scene ?? '—';
      String plano = proposal.associatedRecord?.plane ?? '—';
      String toma = proposal.associatedRecord?.take ?? '—';
      String camara = activeCamera.toUpperCase();
      String clipNum = '—';
      if (proposal.associatedRecord != null) {
        var camRec = proposal.associatedRecord!.cameras.firstWhere(
          (c) => c.cameraName.toUpperCase() == activeCamera.toUpperCase(), 
          orElse: () => CameraTakeRecord(cameraName: activeCamera, clipName: '—')
        );
        clipNum = camRec.clipName;
      } else if (proposal.status == ProposalStatus.unmatchedClip) {
        // Try to extract clip num from the unmatched file
        final RegExp regex = RegExp(r'[cC](\d{3,4})');
        final match = regex.firstMatch(p.basenameWithoutExtension(originalFile));
        if (match != null) {
          clipNum = int.parse(match.group(1)!).toString().padLeft(3, '0');
        } else {
           final fallback = RegExp(r'\d+').allMatches(p.basenameWithoutExtension(originalFile));
           if (fallback.isNotEmpty) {
             clipNum = int.parse(fallback.last.group(0)!).toString().padLeft(3, '0');
           }
        }
      }

      String reel = proposal.associatedRecord?.reel ?? '—';
      String tcIn = proposal.associatedRecord?.tcIn ?? '—';
      String tcOut = proposal.associatedRecord?.tcOut ?? '—';
      String mos = proposal.associatedRecord?.isMos == true ? 'SI' : 'NO';
      String obs = proposal.associatedRecord?.observations ?? '—';

      List<String> rowData = [
        estado, originalFile, conventionName, capitulo, escena, plano, toma,
        camara, clipNum, reel, tcIn, tcOut, mos, obs
      ];

      sheet.appendRow(rowData.map((val) => TextCellValue(val)).toList());
      csvData.add(rowData);
    }

    // Save Excel
    var fileBytes = excel.save();
    if (fileBytes != null) {
      File(xlsxPath).writeAsBytesSync(fileBytes);
    }

    // 2. Generate CSV
    StringBuffer csvBuffer = StringBuffer();
    // Add Metadata to CSV as well (optional but good for completeness)
    csvBuffer.writeln('PRODUCCIÓN:,${_escapeCsv(metadata.production)},UNIDAD:,${_escapeCsv(metadata.unit)}');
    csvBuffer.writeln('PRODUCTOR:,${_escapeCsv(metadata.producer)},DÍA:,${_escapeCsv(metadata.day)}');
    csvBuffer.writeln('NOMENCLATURA:,${_escapeCsv(metadata.nomenclature)},FRAME RATE:,${_escapeCsv(metadata.frameRate)}');
    csvBuffer.writeln('LOCACIÓN:,${_escapeCsv(metadata.location)},VIDEO CODEC:,${_escapeCsv(metadata.videoCodec)}');
    csvBuffer.writeln('FECHA:,${_escapeCsv(metadata.date)},AUDIO FORMAT:,${_escapeCsv(metadata.audioFormat)}');
    csvBuffer.writeln('ING. RESPONSABLE:,${_escapeCsv(metadata.responsibleEngineer)},INGESTADOR:,${_escapeCsv(metadata.ingestor)}');
    csvBuffer.writeln('FECHA EXPORTACIÓN:,${formattedTimestamp}');
    csvBuffer.writeln(); // Empty row

    for (var row in csvData) {
      csvBuffer.writeln(row.map(_escapeCsv).join(','));
    }

    File(csvPath).writeAsStringSync(csvBuffer.toString());

    return xlsxPath;
  }

  static String _statusToString(ProposalStatus status) {
    switch (status) {
      case ProposalStatus.ready: return 'Listo';
      case ProposalStatus.renamed: return 'Renombrado exitoso';
      case ProposalStatus.alreadyRenamed: return 'Ya renombrado';
      case ProposalStatus.missingFile: return 'Faltante';
      case ProposalStatus.unmatchedClip: return 'No registrado';
      case ProposalStatus.conflict: return 'Conflicto';
    }
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      String escaped = value.replaceAll('"', '""');
      return '"$escaped"';
    }
    return value;
  }
}
