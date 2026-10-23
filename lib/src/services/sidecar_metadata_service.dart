class SidecarMetadata {
  final String? tcIn; // e.g. "10:00:00:00"
  final String? tcOut; // e.g. "10:01:30:12"
  final int? durationFrames;
  final String? frameRate;

  SidecarMetadata({
    this.tcIn,
    this.tcOut,
    this.durationFrames,
    this.frameRate,
  });
}

class SidecarMetadataService {
  /// Parses Sony XAVC/XDCAM NonRealTimeMeta or generic XML sidecar metadata.
  static SidecarMetadata? parseXml(String xmlContent) {
    if (xmlContent.trim().isEmpty) return null;

    String? tcIn;
    String? tcOut;
    int? durationFrames;
    String? frameRate;

    // 1. Sony XAVC / XDCAM format (<NonRealTimeMeta>)
    final isSonyMeta = xmlContent.contains('<NonRealTimeMeta') || xmlContent.contains('<LtcChangeTable');
    if (isSonyMeta) {
      final ltcFpsMatch = RegExp(r'<LtcChangeTable[^>]*tcFps=["\x27]([^"\x27]+)["\x27]', caseSensitive: false)
          .firstMatch(xmlContent);
      if (ltcFpsMatch != null) {
        frameRate = ltcFpsMatch.group(1);
      }

      final ltcChangeMatches = RegExp(r'<LtcChange\b([^>]*)>', caseSensitive: false)
          .allMatches(xmlContent);

      for (final match in ltcChangeMatches) {
        final attrs = match.group(1) ?? '';
        final valMatch = RegExp(r'value=["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(attrs);
        final statusMatch = RegExp(r'status=["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(attrs);
        final status = statusMatch?.group(1)?.toLowerCase();

        if (valMatch != null) {
          final rawVal = valMatch.group(1)!.trim();
          if (status == 'end') {
            tcOut ??= formatTimecode(rawVal, isSonyLtc: true);
          } else {
            tcIn ??= formatTimecode(rawVal, isSonyLtc: true);
          }
        }
      }

      final durationMatch = RegExp(r'<Duration[^>]*value=["\x27](\d+)["\x27]', caseSensitive: false)
          .firstMatch(xmlContent);
      if (durationMatch != null) {
        durationFrames = int.tryParse(durationMatch.group(1)!);
      }
    }

    // 2. Generic XML formats (<StartTimecode>, <TimeCode>, <StartTimeCode>, <StartTC>, <Duration>)
    if (tcIn == null) {
      final genericStartTags = ['StartTimecode', 'StartTimeCode', 'TimeCode', 'StartTC'];
      for (final tag in genericStartTags) {
        final val = _extractTagOrAttr(xmlContent, tag);
        if (val != null && val.isNotEmpty) {
          tcIn = formatTimecode(val);
          break;
        }
      }
    }

    if (durationFrames == null) {
      final durVal = _extractTagOrAttr(xmlContent, 'Duration');
      if (durVal != null && durVal.isNotEmpty) {
        if (RegExp(r'^\d+$').hasMatch(durVal)) {
          durationFrames = int.tryParse(durVal);
        } else if (durVal.contains(':')) {
          // Duration formatted as timecode
          // If we don't have tcOut yet, we can use this to add or store
        }
      }
    }

    if (frameRate == null) {
      final fpsVal = _extractTagOrAttr(xmlContent, 'FrameRate') ??
          _extractTagOrAttr(xmlContent, 'tcFps') ??
          _extractTagOrAttr(xmlContent, 'Rate');
      if (fpsVal != null && fpsVal.isNotEmpty) {
        frameRate = fpsVal;
      }
    }

    // Check for explicit end timecode tags if available
    final genericEndTags = ['EndTimecode', 'EndTimeCode', 'EndTC', 'StopTimecode'];
    for (final tag in genericEndTags) {
      final val = _extractTagOrAttr(xmlContent, tag);
      if (val != null && val.isNotEmpty) {
        tcOut = formatTimecode(val);
        break;
      }
    }

    // Calculate tcOut if tcIn & durationFrames exist and tcOut is not set
    if (tcIn != null && durationFrames != null && tcOut == null) {
      tcOut = calculateTcOut(tcIn, durationFrames, frameRate);
    }

    if (tcIn == null && tcOut == null && durationFrames == null && frameRate == null) {
      return null;
    }

    return SidecarMetadata(
      tcIn: tcIn,
      tcOut: tcOut,
      durationFrames: durationFrames,
      frameRate: frameRate,
    );
  }

  static String formatTimecode(String raw, {bool isSonyLtc = false}) {
    final clean = raw.trim();
    if (RegExp(r'^\d{8}$').hasMatch(clean)) {
      if (isSonyLtc) {
        // Sony XAVC/XDCAM NonRealTimeMeta stores LTC in Little-Endian byte order (FF SS MM HH).
        final ff = clean.substring(0, 2);
        final ss = clean.substring(2, 4);
        final mm = clean.substring(4, 6);
        final hh = clean.substring(6, 8);
        return '$hh:$mm:$ss:$ff';
      }
      return '${clean.substring(0, 2)}:${clean.substring(2, 4)}:${clean.substring(4, 6)}:${clean.substring(6, 8)}';
    }
    return clean;
  }

  static String? _extractTagOrAttr(String xml, String tagName) {
    // Check <tag>content</tag>
    final contentMatch = RegExp(
      '<$tagName(?:\\s+[^>]*)?>([^<]+)<\\/$tagName>',
      caseSensitive: false,
    ).firstMatch(xml);
    if (contentMatch != null) {
      return contentMatch.group(1)?.trim();
    }

    // Check <tag ... value="content" ... />
    final attrMatch = RegExp(
      '<$tagName\\s+[^>]*value=["\x27]([^"\x27]+)["\x27]',
      caseSensitive: false,
    ).firstMatch(xml);
    if (attrMatch != null) {
      return attrMatch.group(1)?.trim();
    }

    return null;
  }

  static String? calculateTcOut(String tcIn, int durationFrames, String? frameRate) {
    final parts = tcIn.split(':').map((s) => int.tryParse(s) ?? 0).toList();
    if (parts.length != 4) return null;

    final fpsBase = parseFpsBase(frameRate);
    final hh = parts[0];
    final mm = parts[1];
    final ss = parts[2];
    final ff = parts[3];

    final totalInFrames = ((hh * 3600 + mm * 60 + ss) * fpsBase) + ff;
    final totalOutFrames = totalInFrames + durationFrames;

    final outFf = totalOutFrames % fpsBase;
    final totalOutSec = totalOutFrames ~/ fpsBase;
    final outSs = totalOutSec % 60;
    final totalOutMin = totalOutSec ~/ 60;
    final outMm = totalOutMin % 60;
    final outHh = (totalOutMin ~/ 60) % 24;

    return '${outHh.toString().padLeft(2, '0')}:${outMm.toString().padLeft(2, '0')}:${outSs.toString().padLeft(2, '0')}:${outFf.toString().padLeft(2, '0')}';
  }

  static int parseFpsBase(String? fpsStr) {
    if (fpsStr == null) return 24;
    final clean = fpsStr.toLowerCase().replaceAll('p', '').replaceAll('i', '').replaceAll('fps', '').trim();
    final parsed = double.tryParse(clean);
    if (parsed != null && parsed > 0) {
      return parsed.round();
    }
    return 24;
  }
}
