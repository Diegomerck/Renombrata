import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/services/report_export_service.dart';

void main() {
  group('ReportExportService', () {
    test('exports xlsx and csv correctly', () async {
      final tempDir = Directory.systemTemp.createTempSync('renombrata_export_test');

      ShootingLog log = ShootingLog(
        metadata: ShootingLogMetadata(
          nomenclature: 'MNL', date: '071026', unit: 'U3', day: 'D3',
          producer: 'P', production: 'PR', location: 'L', audioFormat: 'F', frameRate: '24fps', videoCodec: 'ProRes', responsibleEngineer: 'E', ingestor: 'I',
        ),
        records: [
          ShotRecord(
            chapter: '1', scene: '10', plane: '1', take: '1', reel: 'A007', 
            tcIn: '01:00:00:00', tcOut: '01:00:10:00', observations: 'Good take, maybe',
            cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')]
          ),
        ]
      );

      DryRunReport report = DryRunReport(proposals: [
        RenameProposal(
          originalFilePath: p.join(tempDir.path, 'C0001.MP4'),
          proposedFileName: 'MNL_071026_10_1_T1_A007_D3_U3.MP4',
          associatedRecord: log.records.first,
          status: ProposalStatus.ready,
        )
      ]);

      await ReportExportService.exportReport(
        mediaFolderPath: tempDir.path,
        log: log,
        report: report,
        activeCamera: 'A',
      );

      final String baseFileName = 'Reporte_Renombrata_MNL_071026_D3_CamA';
      final xlsxFile = File(p.join(tempDir.path, '$baseFileName.xlsx'));
      final csvFile = File(p.join(tempDir.path, '$baseFileName.csv'));

      expect(xlsxFile.existsSync(), true);
      expect(csvFile.existsSync(), true);

      // Read CSV to verify content
      final csvContent = csvFile.readAsStringSync();
      expect(csvContent.contains('CAPÍTULO'), true);
      expect(csvContent.contains('MNL_071026_10_1_T1_A007_D3_U3.MP4'), true);
      expect(csvContent.contains('C0001.MP4'), true);
      expect(csvContent.contains('Good take, maybe'), true); // Comma correctly escaped
      expect(csvContent.contains('01:00:00:00'), true);
      
      // Cleanup
      tempDir.deleteSync(recursive: true);
    });
  });
}
