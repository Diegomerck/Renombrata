import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/services/embedded_metadata_probe_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EmbeddedMetadataProbeService - MediaInfo Parsing', () {
    test('parses ProRes QuickTime MediaInfo JSON with explicit First and Last frame', () {
      const mediaInfoJson = '''
{
  "media": {
    "@ref": "A001C001_240101_R1ZA.MOV",
    "track": [
      {
        "@type": "General",
        "Duration": "12.500",
        "FrameRate": "24.000"
      },
      {
        "@type": "Video",
        "Format": "ProRes",
        "Duration": "12.500",
        "FrameRate": "24.000",
        "TimeCode_FirstFrame": "10:00:00:00",
        "TimeCode_LastFrame": "10:00:12:12",
        "TimeCode_Source": "QuickTime TC"
      }
    ]
  }
}
''';

      final result = EmbeddedMetadataProbeService.parseMediaInfoJson(mediaInfoJson);
      expect(result, isNotNull);
      expect(result!.tcIn, '10:00:00:00');
      expect(result.tcOut, '10:00:12:12');
      expect(result.frameRate, '24.000');
    });

    test('parses MXF SMPTE timecode track in Other track', () {
      const mediaInfoJson = '''
{
  "media": {
    "track": [
      {
        "@type": "General",
        "Duration": "10.000",
        "FrameRate": "25.000"
      },
      {
        "@type": "Other",
        "Type": "Time code",
        "Format": "SMPTE TC",
        "TimeCode_FirstFrame": "01:23:45:10",
        "TimeCode_LastFrame": "01:23:55:10",
        "FrameRate": "25.000"
      }
    ]
  }
}
''';

      final result = EmbeddedMetadataProbeService.parseMediaInfoJson(mediaInfoJson);
      expect(result, isNotNull);
      expect(result!.tcIn, '01:23:45:10');
      expect(result.tcOut, '01:23:55:10');
      expect(result.frameRate, '25.000');
    });

    test('calculates tcOut using Duration and FrameRate when TimeCode_LastFrame is missing', () {
      const mediaInfoJson = '''
{
  "media": {
    "track": [
      {
        "@type": "General",
        "Duration": "10.000",
        "FrameRate": "24.000",
        "extra": {
          "com_apple_quicktime_timecode": "10:00:00:00"
        }
      }
    ]
  }
}
''';

      final result = EmbeddedMetadataProbeService.parseMediaInfoJson(mediaInfoJson);
      expect(result, isNotNull);
      expect(result!.tcIn, '10:00:00:00');
      // 10 seconds at 24fps = 240 frames -> 10:00:10:00
      expect(result.tcOut, '10:00:10:00');
    });

    test('formats unformatted 8-digit timecode strings correctly', () {
      const mediaInfoJson = '''
{
  "media": {
    "track": [
      {
        "@type": "General",
        "TimeCode_FirstFrame": "10000000"
      }
    ]
  }
}
''';

      final result = EmbeddedMetadataProbeService.parseMediaInfoJson(mediaInfoJson);
      expect(result, isNotNull);
      expect(result!.tcIn, '10:00:00:00');
    });

    test('parses Canon RAW Light (.CRM) MediaInfo JSON with QuickTime TC and TimeCode_FirstFrame', () {
      const crmMediaInfoJson = '''{
  "media": {
    "@ref": "A001_C001_1028OC_001.CRM",
    "track": [
      {
        "@type": "General",
        "Format": "Canon RAW Light",
        "Duration": "14.250",
        "FrameRate": "23.976"
      },
      {
        "@type": "Video",
        "Format": "Cinema RAW Light",
        "Duration": "14.250",
        "FrameRate": "23.976"
      },
      {
        "@type": "Other",
        "Type": "Time code",
        "Format": "QuickTime TC",
        "TimeCode_FirstFrame": "02:15:30:12",
        "TimeCode_LastFrame": "02:15:44:18",
        "TimeCode_Source": "QuickTime TC",
        "FrameRate": "23.976"
      }
    ]
  }
}''';

      final result = EmbeddedMetadataProbeService.parseMediaInfoJson(crmMediaInfoJson);
      expect(result, isNotNull);
      expect(result!.tcIn, '02:15:30:12');
      expect(result.tcOut, '02:15:44:18');
      expect(result.frameRate, '23.976');
    });

    test('parses MXF MediaInfo JSON where TimeCode_Source is SMPTE TC and TimeCode_FirstFrame is in Video track', () {
      const mxfMediaInfoJson = '''{
  "media": {
    "track": [
      {
        "@type": "General",
        "Format": "MXF",
        "Duration": "20.000",
        "FrameRate": "25.000"
      },
      {
        "@type": "Video",
        "Format": "XAVC",
        "Duration": "20.000",
        "FrameRate": "25.000",
        "TimeCode_FirstFrame": "08:30:00:00",
        "TimeCode_Source": "SMPTE TC"
      }
    ]
  }
}''';

      final result = EmbeddedMetadataProbeService.parseMediaInfoJson(mxfMediaInfoJson);
      expect(result, isNotNull);
      expect(result!.tcIn, '08:30:00:00');
      // 20s at 25fps = 500 frames -> 08:30:20:00
      expect(result.tcOut, '08:30:20:00');
      expect(result.frameRate, '25.000');
    });

    test('parses GoPro Proxy (.LRV) MediaInfo JSON correctly', () {
      const lrvMediaInfoJson = '''{
  "media": {
    "@ref": "GX010042.LRV",
    "track": [
      {
        "@type": "General",
        "Duration": "6.000",
        "FrameRate": "29.970"
      },
      {
        "@type": "Video",
        "Format": "AVC",
        "Duration": "6.000",
        "FrameRate": "29.970",
        "extra": {
          "TimeCode_FirstFrame": "14:20:10:00"
        }
      }
    ]
  }
}''';

      final result = EmbeddedMetadataProbeService.parseMediaInfoJson(lrvMediaInfoJson);
      expect(result, isNotNull);
      expect(result!.tcIn, '14:20:10:00');
      expect(result.tcOut, '14:20:16:00');
    });
    test('returns null for empty or invalid MediaInfo JSON', () {
      expect(EmbeddedMetadataProbeService.parseMediaInfoJson(''), isNull);
      expect(EmbeddedMetadataProbeService.parseMediaInfoJson('{}'), isNull);
      expect(EmbeddedMetadataProbeService.parseMediaInfoJson('{"media": {}}'), isNull);
      expect(EmbeddedMetadataProbeService.parseMediaInfoJson('not a json'), isNull);
    });
  });

  group('EmbeddedMetadataProbeService - FFprobe Parsing', () {
    test('parses FFprobe JSON with format tags and fractional frame rate', () {
      const ffprobeJson = '''
{
  "streams": [
    {
      "index": 0,
      "codec_type": "video",
      "r_frame_rate": "24/1",
      "duration": "10.000000",
      "tags": {
        "timecode": "09:15:30:00"
      }
    }
  ],
  "format": {
    "duration": "10.000000",
    "tags": {
      "timecode": "09:15:30:00"
    }
  }
}
''';

      final result = EmbeddedMetadataProbeService.parseFfprobeJson(ffprobeJson);
      expect(result, isNotNull);
      expect(result!.tcIn, '09:15:30:00');
      // 10 seconds at 24fps = 09:15:40:00
      expect(result.tcOut, '09:15:40:00');
      expect(result.frameRate, '24.000');
    });

    test('parses FFprobe JSON with 23.976 fps (24000/1001) and uppercase TIMECODE in stream tags', () {
      const ffprobeJson = '''
{
  "streams": [
    {
      "index": 0,
      "codec_type": "video",
      "r_frame_rate": "24000/1001",
      "duration": "5.000000",
      "tags": {
        "TIMECODE": "02:00:10:05"
      }
    }
  ],
  "format": {
    "duration": "5.000000"
  }
}
''';

      final result = EmbeddedMetadataProbeService.parseFfprobeJson(ffprobeJson);
      expect(result, isNotNull);
      expect(result!.tcIn, '02:00:10:05');
      expect(result.frameRate, '23.976');
      // 5s at 24fps base = 120 frames -> 02:00:15:05
      expect(result.tcOut, '02:00:15:05');
    });

    test('returns null for empty or invalid FFprobe JSON', () {
      expect(EmbeddedMetadataProbeService.parseFfprobeJson(''), isNull);
      expect(EmbeddedMetadataProbeService.parseFfprobeJson('{}'), isNull);
      expect(EmbeddedMetadataProbeService.parseFfprobeJson('{"streams": []}'), isNull);
      expect(EmbeddedMetadataProbeService.parseFfprobeJson('invalid'), isNull);
    });
  });

  group('EmbeddedMetadataProbeService - Probe Engine Execution', () {
    tearDown(() {
      EmbeddedMetadataProbeService.resetSession();
    });

    test('getBundledEnginePath resolves executable file path', () async {
      final path = await EmbeddedMetadataProbeService.getBundledEnginePath();
      expect(path, isNotNull);
      expect(path!.isNotEmpty, isTrue);
    });

    test('getAvailableEngine detects and prioritizes ProbeEngine.bundled', () async {
      final engine = await EmbeddedMetadataProbeService.getAvailableEngine();
      expect(engine, equals(ProbeEngine.bundled));
    });

    test('returns null gracefully when engine is ProbeEngine.none', () async {
      EmbeddedMetadataProbeService.setEngineForTesting(ProbeEngine.none);

      final result = await EmbeddedMetadataProbeService.probeFile('non_existent_file.mov');
      expect(result, isNull);
    });

    test('returns null gracefully on nonexistent file when engine is ProbeEngine.bundled', () async {
      EmbeddedMetadataProbeService.setEngineForTesting(ProbeEngine.bundled);
      final result = await EmbeddedMetadataProbeService.probeFile('missing.mov');
      expect(result, isNull);
    });

    test('returns null gracefully on nonexistent file when engine is mediainfo/ffprobe', () async {
      EmbeddedMetadataProbeService.setEngineForTesting(ProbeEngine.none);
      final result = await EmbeddedMetadataProbeService.probeFile('missing.mov');
      expect(result, isNull);
    });
  });
}
