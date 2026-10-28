import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/services/rtf_bitacora_parser_service.dart';

void main() {
  group('ClipMatcherService Numeric Clip Padding Normalization', () {
    test('normalizes clip numbers "1", "01", "001", "0001" consistently', () {
      expect(ClipMatcherService.normalizeClipNumber('1'), '001');
      expect(ClipMatcherService.normalizeClipNumber('01'), '001');
      expect(ClipMatcherService.normalizeClipNumber('001'), '001');
      expect(ClipMatcherService.normalizeClipNumber('0001'), '001');
      expect(ClipMatcherService.normalizeClipNumber('C1'), '001');
      expect(ClipMatcherService.normalizeClipNumber('C01'), '001');
      expect(ClipMatcherService.normalizeClipNumber('C001'), '001');
      expect(ClipMatcherService.normalizeClipNumber('15'), '015');
      expect(ClipMatcherService.normalizeClipNumber('C015'), '015');
      expect(ClipMatcherService.normalizeClipNumber('123'), '123');
    });

    test('automatically matches single-digit RTF clip (e.g. "1") with 3-digit camera file (e.g. "A001C001")', () {
      const rtfContent = 'TODTA_2_13_P1_T1_A001_D01_1_U1';
      final entries = RtfBitacoraParserService.parseLines(rtfContent);
      expect(entries.length, 1);
      expect(entries.first.clipIndex, '1');

      final log = RtfBitacoraParserService.toShootingLog(entries);
      expect(log.records.length, 1);
      expect(log.records.first.cameras.first.clipName, '001');

      final scannedFiles = [
        ScannedFile('/media/A001C001_260817AB.MP4'),
      ];

      final report = ClipMatcherService.matchFiles(
        scannedFiles: scannedFiles,
        log: log,
        targetCamera: 'A',
      );

      expect(report.totalMatched, 1);
      expect(report.totalMissing, 0);

      final proposal = report.proposals.firstWhere(
        (p) => p.originalFilePath == '/media/A001C001_260817AB.MP4',
      );
      expect(proposal.status, ProposalStatus.ready);
      expect(proposal.proposedFileName, 'TODTA_D01_13_1_T1_A001_D01_U1.MP4');
      expect(proposal.associatedRecord, isNotNull);
      expect(proposal.associatedRecord?.scene, '13');
      expect(proposal.associatedRecord?.take, '1');
    });
  });
}
