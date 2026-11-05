import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'sidecar_metadata_service.dart';

enum ProbeEngine {
  bundled,
  mediainfo,
  ffprobe,
  none,
}

class EmbeddedMetadataProbeService {
  static ProbeEngine? _cachedEngine;
  static String? _cachedBundledPath;
  static String? bundledPathOverrideForTesting;

  /// Allows tests to set or reset the engine explicitly.
  static void setEngineForTesting(ProbeEngine? engine) {
    _cachedEngine = engine;
  }

  /// Allows tests to set or reset the bundled executable path override.
  static void setBundledPathForTesting(String? path) {
    bundledPathOverrideForTesting = path;
  }

  /// Resets all cached session state.
  static void resetSession() {
    _cachedEngine = null;
    _cachedBundledPath = null;
    bundledPathOverrideForTesting = null;
  }

  /// Resolves the absolute path to the bundled MediaInfo CLI binary.
  /// If not yet extracted from application assets to the local app support
  /// directory, extracts and sets executable permissions.
  static Future<String?> getBundledEnginePath() async {
    if (bundledPathOverrideForTesting != null) {
      return bundledPathOverrideForTesting;
    }

    if (_cachedBundledPath != null && File(_cachedBundledPath!).existsSync()) {
      return _cachedBundledPath!;
    }

    final String assetPath;
    final String binName;
    if (Platform.isWindows) {
      assetPath = 'assets/bin/windows/mediainfo.exe';
      binName = 'mediainfo.exe';
    } else if (Platform.isMacOS) {
      assetPath = 'assets/bin/macos/mediainfo';
      binName = 'mediainfo';
    } else {
      return null;
    }

    try {
      Directory baseDir;
      try {
        baseDir = await getApplicationSupportDirectory();
      } catch (_) {
        baseDir = Directory.systemTemp;
      }

      final binDir = Directory(p.join(baseDir.path, 'bin'));
      if (!binDir.existsSync()) {
        binDir.createSync(recursive: true);
      }

      final targetFile = File(p.join(binDir.path, binName));

      List<int>? bytes;
      try {
        final byteData = await rootBundle.load(assetPath);
        bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
      } catch (_) {
        // Fallback for tests or local dev when rootBundle asset catalog is not initialized
        final localAssetFile = File(assetPath);
        if (localAssetFile.existsSync()) {
          bytes = localAssetFile.readAsBytesSync();
        }
      }

      if (bytes != null) {
        if (!targetFile.existsSync() || targetFile.lengthSync() != bytes.length) {
          await targetFile.writeAsBytes(bytes, flush: true);
          if (!Platform.isWindows) {
            try {
              await Process.run('chmod', ['+x', targetFile.path]);
            } catch (_) {}
          }
        }
        _cachedBundledPath = targetFile.path;
        return targetFile.path;
      }

      if (targetFile.existsSync()) {
        _cachedBundledPath = targetFile.path;
        return targetFile.path;
      }
    } catch (_) {
      // Gracefully return null if unable to resolve or extract
    }

    return null;
  }

  /// Detects whether the bundled engine, or system mediainfo / ffprobe is available.
  /// Caches the result for subsequent calls within the session.
  static Future<ProbeEngine> getAvailableEngine() async {
    if (_cachedEngine != null) {
      return _cachedEngine!;
    }

    // 1. Prioritize bundled standalone binary
    try {
      final bundledPath = await getBundledEnginePath();
      if (bundledPath != null && File(bundledPath).existsSync()) {
        final bundledResult = await Process.run(bundledPath, ['--version'])
            .timeout(const Duration(seconds: 2));
        if (bundledResult.exitCode == 0) {
          _cachedEngine = ProbeEngine.bundled;
          return _cachedEngine!;
        }
      }
    } catch (_) {
      // bundled binary execution failed
    }

    // 2. Fallback to system mediainfo
    try {
      final mediaInfoResult = await Process.run('mediainfo', ['--version'])
          .timeout(const Duration(seconds: 2));
      if (mediaInfoResult.exitCode == 0) {
        _cachedEngine = ProbeEngine.mediainfo;
        return _cachedEngine!;
      }
    } catch (_) {
      // mediainfo not found or timed out
    }

    // 3. Fallback to system ffprobe
    try {
      final ffprobeResult = await Process.run('ffprobe', ['-version'])
          .timeout(const Duration(seconds: 2));
      if (ffprobeResult.exitCode == 0) {
        _cachedEngine = ProbeEngine.ffprobe;
        return _cachedEngine!;
      }
    } catch (_) {
      // ffprobe not found or timed out
    }

    _cachedEngine = ProbeEngine.none;
    return _cachedEngine!;
  }

  /// Extracts embedded timecode from a video file (.mov, .mxf, .mp4) using the available engine.
  static Future<SidecarMetadata?> probeFile(String filePath) async {
    final engine = await getAvailableEngine();
    if (engine == ProbeEngine.none) {
      return null;
    }

    try {
      if (engine == ProbeEngine.bundled) {
        final bundledPath = await getBundledEnginePath();
        if (bundledPath != null) {
          final result = await Process.run(
            bundledPath,
            ['--Output=JSON', filePath],
          ).timeout(const Duration(seconds: 5));

          if (result.exitCode == 0 && result.stdout is String) {
            return parseMediaInfoJson(result.stdout as String);
          }
        }
      } else if (engine == ProbeEngine.mediainfo) {
        final result = await Process.run(
          'mediainfo',
          ['--Output=JSON', filePath],
        ).timeout(const Duration(seconds: 5));

        if (result.exitCode == 0 && result.stdout is String) {
          return parseMediaInfoJson(result.stdout as String);
        }
      } else if (engine == ProbeEngine.ffprobe) {
        final result = await Process.run(
          'ffprobe',
          [
            '-v',
            'error',
            '-select_streams',
            'v:0',
            '-show_entries',
            'format_tags=timecode:stream_tags=timecode:stream=r_frame_rate,duration:format=duration',
            '-of',
            'json',
            filePath,
          ],
        ).timeout(const Duration(seconds: 5));

        if (result.exitCode == 0 && result.stdout is String) {
          return parseFfprobeJson(result.stdout as String);
        }
      }
    } catch (_) {
      // Gracefully swallow process execution errors / timeouts
    }

    return null;
  }

  /// Parses MediaInfo JSON output and extracts timecode metadata.
  static SidecarMetadata? parseMediaInfoJson(String jsonStr) {
    if (jsonStr.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return null;

      final media = decoded['media'];
      if (media is! Map) return null;

      var rawTracks = media['track'];
      if (rawTracks == null) return null;
      final List tracks = rawTracks is List ? List.from(rawTracks) : [rawTracks];

      // Sort tracks prioritizing Other (Time code / SMPTE / QuickTime), Video, General, then others
      int trackPriority(dynamic t) {
        if (t is! Map) return 99;
        final type = (t['@type'] ?? '').toString().toLowerCase();
        final subType = (t['Type'] ?? '').toString().toLowerCase();
        final format = (t['Format'] ?? '').toString().toLowerCase();
        if (type == 'other' &&
            (subType.contains('time code') ||
                format.contains('tc') ||
                format.contains('smpte') ||
                format.contains('quicktime'))) {
          return 0;
        }
        if (type == 'video') return 1;
        if (type == 'other') return 2;
        if (type == 'general') return 3;
        return 4;
      }

      tracks.sort((a, b) => trackPriority(a).compareTo(trackPriority(b)));

      String? tcIn;
      String? tcOut;
      String? frameRate;
      double? durationSec;

      for (final t in tracks) {
        if (t is! Map) continue;

        // Check frame rate
        if (frameRate == null) {
          if (t['FrameRate'] != null) {
            frameRate = t['FrameRate'].toString();
          } else if (t['FrameRate_Nominal'] != null) {
            frameRate = t['FrameRate_Nominal'].toString();
          } else if (t['FrameRate_Num'] != null && t['FrameRate_Den'] != null) {
            final num = double.tryParse(t['FrameRate_Num'].toString());
            final den = double.tryParse(t['FrameRate_Den'].toString());
            if (num != null && den != null && den > 0) {
              frameRate = (num / den).toStringAsFixed(3);
            }
          }
        }

        // Check duration
        if (durationSec == null && t['Duration'] != null) {
          durationSec = double.tryParse(t['Duration'].toString());
        }

        // Look for TC In
        if (tcIn == null) {
          tcIn = _findFirstTimecode(t, [
            'TimeCode_FirstFrame',
            'TimeCode',
            'timecode',
            'TimeCode_Source',
            'com_apple_quicktime_timecode',
            'QuickTime_TC',
            'SMPTE_TC',
            'tc_in',
          ]);

          if (tcIn == null && t['extra'] is Map) {
            final extra = t['extra'] as Map;
            tcIn = _findFirstTimecode(extra, [
              'com_apple_quicktime_timecode',
              'TimeCode_FirstFrame',
              'TimeCode',
              'timecode',
              'TimeCode_Source',
              'QuickTime_TC',
              'SMPTE_TC',
              'tc_in',
            ]);
          }
        }

        // Look for TC Out
        if (tcOut == null) {
          tcOut = _findFirstTimecode(t, [
            'TimeCode_LastFrame',
            'TimeCode_End',
            'tc_out',
            'TimeCode_Striped_LastFrame',
          ]);
          if (tcOut == null && t['extra'] is Map) {
            final extra = t['extra'] as Map;
            tcOut = _findFirstTimecode(extra, [
              'TimeCode_LastFrame',
              'TimeCode_End',
              'tc_out',
              'TimeCode_Striped_LastFrame',
            ]);
          }
        }
      }

      if (tcIn == null) return null;

      tcIn = SidecarMetadataService.formatTimecode(tcIn);
      if (tcOut != null) {
        tcOut = SidecarMetadataService.formatTimecode(tcOut);
      } else if (durationSec != null && frameRate != null) {
        final fps = SidecarMetadataService.parseFpsBase(frameRate);
        final durationFrames = (durationSec * fps).round();
        tcOut = SidecarMetadataService.calculateTcOut(tcIn, durationFrames, frameRate);
      }

      return SidecarMetadata(
        tcIn: tcIn,
        tcOut: tcOut,
        frameRate: frameRate,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses FFprobe JSON output and extracts timecode metadata.
  static SidecarMetadata? parseFfprobeJson(String jsonStr) {
    if (jsonStr.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return null;

      String? tcIn;
      String? tcOut;
      String? frameRate;
      double? durationSec;

      // 1. Check format tags
      final format = decoded['format'];
      if (format is Map) {
        if (format['duration'] != null) {
          durationSec = double.tryParse(format['duration'].toString());
        }
        if (format['tags'] is Map) {
          final tags = format['tags'] as Map;
          tcIn ??= _findFirstString(tags, ['timecode', 'TIMECODE', 'time_code', 'TimeCode']);
        }
      }

      // 2. Check streams
      final streams = decoded['streams'];
      if (streams is List && streams.isNotEmpty) {
        for (final s in streams) {
          if (s is! Map) continue;

          if (durationSec == null && s['duration'] != null) {
            durationSec = double.tryParse(s['duration'].toString());
          }

          if (frameRate == null) {
            final rawRate = s['r_frame_rate'] ?? s['avg_frame_rate'];
            if (rawRate != null) {
              frameRate = _normalizeFpsFraction(rawRate.toString());
            }
          }

          if (tcIn == null && s['tags'] is Map) {
            final tags = s['tags'] as Map;
            tcIn = _findFirstString(tags, ['timecode', 'TIMECODE', 'time_code', 'TimeCode']);
          }
        }
      }

      if (tcIn == null) return null;

      tcIn = SidecarMetadataService.formatTimecode(tcIn);

      if (durationSec != null && frameRate != null) {
        final fps = SidecarMetadataService.parseFpsBase(frameRate);
        final durationFrames = (durationSec * fps).round();
        tcOut = SidecarMetadataService.calculateTcOut(tcIn, durationFrames, frameRate);
      }

      return SidecarMetadata(
        tcIn: tcIn,
        tcOut: tcOut,
        frameRate: frameRate,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isValidTimecodeString(String? val) {
    if (val == null) return false;
    final clean = val.trim();
    if (clean.isEmpty) return false;
    // Format names or package identifiers should not be treated as timecodes
    if (clean.toLowerCase().contains('tc') && !clean.contains(':')) return false;
    if (clean.toLowerCase().contains('package')) return false;
    return RegExp(r'^(\d{1,2}[:;.]){3}\d{1,2}$').hasMatch(clean) ||
        RegExp(r'^\d{8}$').hasMatch(clean);
  }

  static String? _findFirstTimecode(Map map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        final val = map[key].toString().trim();
        if (_isValidTimecodeString(val)) return val;
      }
    }
    return null;
  }
  static String? _findFirstString(Map map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        final val = map[key].toString().trim();
        if (val.isNotEmpty) return val;
      }
    }
    return null;
  }

  static String _normalizeFpsFraction(String fpsStr) {
    final clean = fpsStr.trim();
    if (clean.contains('/')) {
      final parts = clean.split('/');
      if (parts.length == 2) {
        final num = double.tryParse(parts[0]);
        final den = double.tryParse(parts[1]);
        if (num != null && den != null && den > 0) {
          final fps = num / den;
          return fps.toStringAsFixed(3);
        }
      }
    }
    return clean;
  }
}
