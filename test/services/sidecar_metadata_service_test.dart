import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/services/sidecar_metadata_service.dart';

void main() {
  group('SidecarMetadataService', () {
    test('formatTimecode handles standard Big-Endian and Sony Little-Endian byte inversion', () {
      // Sony Little-Endian: Byte 3 (HH), Byte 2 (MM), Byte 1 (SS), Byte 0 (FF)
      expect(SidecarMetadataService.formatTimecode('00220409', isSonyLtc: true), '09:04:22:00');
      expect(SidecarMetadataService.formatTimecode('23290709', isSonyLtc: true), '09:07:29:23');
      expect(SidecarMetadataService.formatTimecode('00000010', isSonyLtc: true), '10:00:00:00');

      // Standard Big-Endian: HH MM SS FF
      expect(SidecarMetadataService.formatTimecode('10000000'), '10:00:00:00');
      expect(SidecarMetadataService.formatTimecode('05000000'), '05:00:00:00');

      // Formatted with colons preserves value
      expect(SidecarMetadataService.formatTimecode('09:04:22:00', isSonyLtc: true), '09:04:22:00');
    });

    test('parses Sony NonRealTimeMeta XML with Little-Endian timecode and calculates tcOut', () {
      const sonyXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<NonRealTimeMeta xmlns="urn:schemas-professionalDisc:nonRealTimeMeta:ver.2.00" lastUpdate="2026-10-15T12:00:00Z">
  <Duration value="1440"/>
  <LtcChangeTable tcFps="24p" halfStep="false">
    <LtcChange frameCount="0" value="00220409" status="increment"/>
  </LtcChangeTable>
</NonRealTimeMeta>
''';

      final meta = SidecarMetadataService.parseXml(sonyXml);
      expect(meta, isNotNull);
      // 00220409 -> 09:04:22:00
      expect(meta!.tcIn, '09:04:22:00');
      expect(meta.durationFrames, 1440);
      expect(meta.frameRate, '24p');
      // 1440 frames @ 24fps = 60s -> 09:05:22:00
      expect(meta.tcOut, '09:05:22:00');
    });

    test('parses Sony NonRealTimeMeta XML using explicit status="end" for tcOut', () {
      const sonyXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<NonRealTimeMeta xmlns="urn:schemas-professionalDisc:nonRealTimeMeta:ver.2.00">
  <Duration value="1440"/>
  <LtcChangeTable tcFps="24p">
    <LtcChange frameCount="0" value="00220409" status="increment"/>
    <LtcChange frameCount="1440" value="00230409" status="end"/>
  </LtcChangeTable>
</NonRealTimeMeta>
''';

      final meta = SidecarMetadataService.parseXml(sonyXml);
      expect(meta, isNotNull);
      expect(meta!.tcIn, '09:04:22:00');
      expect(meta.tcOut, '09:04:23:00');
    });

    test('parses Sony XML with formatted timecode and fractional fps', () {
      const sonyXml = '''
<NonRealTimeMeta>
  <Duration value="72"/>
  <LtcChangeTable tcFps="23.98p">
    <LtcChange frameCount="0" value="01:15:30:10"/>
  </LtcChangeTable>
</NonRealTimeMeta>
''';

      final meta = SidecarMetadataService.parseXml(sonyXml);
      expect(meta, isNotNull);
      expect(meta!.tcIn, '01:15:30:10');
      expect(meta.durationFrames, 72);
      expect(meta.frameRate, '23.98p');
      // 72 frames at 24fps = 3 seconds -> 01:15:33:10
      expect(meta.tcOut, '01:15:33:10');
    });

    test('parses generic XML with StartTimecode and Duration', () {
      const genericXml = '''
<ClipMeta>
  <StartTimecode>09:30:00:05</StartTimecode>
  <Duration>48</Duration>
  <FrameRate>24</FrameRate>
</ClipMeta>
''';

      final meta = SidecarMetadataService.parseXml(genericXml);
      expect(meta, isNotNull);
      expect(meta!.tcIn, '09:30:00:05');
      expect(meta.durationFrames, 48);
      expect(meta.frameRate, '24');
      expect(meta.tcOut, '09:30:02:05');
    });

    test('parses generic XML with 8-digit StartTC and EndTC', () {
      const genericXml = '''
<Metadata>
  <StartTC>05000000</StartTC>
  <EndTC>05100000</EndTC>
</Metadata>
''';

      final meta = SidecarMetadataService.parseXml(genericXml);
      expect(meta, isNotNull);
      expect(meta!.tcIn, '05:00:00:00');
      expect(meta.tcOut, '05:10:00:00');
    });

    test('returns null for non-timecode XML or empty content', () {
      expect(SidecarMetadataService.parseXml(''), isNull);
      expect(SidecarMetadataService.parseXml('   '), isNull);
      expect(SidecarMetadataService.parseXml('<Config><Param name="foo">bar</Param></Config>'), isNull);
    });
  });
}
