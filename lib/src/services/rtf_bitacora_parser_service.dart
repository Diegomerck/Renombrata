import 'package:renombrata/src/models/shooting_log.dart';

/// Represents a parsed television/streaming media naming convention entry
/// (e.g., Televisa / ViX data manager standard).
class ParsedConventionEntry {
  final String nomenclature;
  final String chapter;
  final String scene;
  final String? plane;
  final String take;
  final String reel;
  final String day;
  final String clipIndex;
  final String unit;
  final String? subConvention;
  final String rawLine;

  const ParsedConventionEntry({
    required this.nomenclature,
    required this.chapter,
    required this.scene,
    this.plane,
    required this.take,
    required this.reel,
    required this.day,
    required this.clipIndex,
    required this.unit,
    this.subConvention,
    required this.rawLine,
  });

  bool get isTf => take.toUpperCase().startsWith('TF');
  bool get isGpr => reel.toUpperCase().startsWith('GPR');
  bool get isDr => reel.toUpperCase().startsWith('DR');
  bool get isDs => unit.toUpperCase() == 'DS';
  bool get isFf => reel.toUpperCase().startsWith('NFF') || reel.toUpperCase().startsWith('FF');

  @override
  String toString() => rawLine;
}

/// Service for decoding macOS TextEdit (.rtf) and plain-text (.txt) convention
/// lists into structured [ShootingLog] and [ShotRecord] models.
class RtfBitacoraParserService {
  /// Regular expression for matching Televisa / ViX naming convention lines.
  /// Format:
  /// {PROD}_{CAP}_{ESC}_(?:P{PLANO}_)?{TOMA}_{REEL}_{DIA}_{CLIP#}_{UNIDAD}(?:%{SUBCONV})?
  static final RegExp conventionPattern = RegExp(
    r'^([A-Za-z0-9]+)_([A-Za-z0-9Y]+)_([A-Za-z0-9Y]+)_(?:P([0-9]+)_)?(T[0-9]+|TF[0-9]*|TU|SEC[0-9]+|G[0-9]*)_([A-Za-z][0-9]{3}(?:_[0-9]+)?|GPR[0-9]*|NFF|DR[0-9]*)_([A-Za-z0-9]+)_([0-9]+)_([A-Za-z0-9]+)(?:%(.*))?$',
    caseSensitive: false,
  );

  /// Regular expression for matching Micronovela naming convention lines.
  /// Format:
  /// {PROD}_{DATE}_{CAP}_{ESC}_(?:P{PLANO}_)?{TOMA}_{REEL}_{CLIP#}_{DIA}_{UNIDAD}(?:%{SUBCONV})?
  static final RegExp micronovelaPattern = RegExp(
    r'^([A-Za-z0-9]+)_([0-9]{6})_([A-Za-z0-9]+)_([A-Za-z0-9]+)_(?:P([0-9]+)_)?(T[0-9]+|TF[0-9]*|TU|SEC[0-9]+|G[0-9]*)_([A-Za-z][0-9]{1,4}(?:_[0-9]+)?|GPR[0-9]*|NFF|DR[0-9]*)_([0-9]+)_([A-Za-z0-9]+)_([A-Za-z0-9]+)(?:%(.*))?$',
    caseSensitive: false,
  );

  /// Extracts clean plain text from raw string content.
  ///
  /// If [rawContent] is in Rich Text Format (starts with `{\rtf`), control words,
  /// font/color tables, and grouping braces are stripped, and escaped hex and
  /// unicode characters are decoded into UTF-8 characters.
  /// If [rawContent] is plain text, it is returned unchanged.
  static String extractPlainText(String rawContent) {
    if (!rawContent.trimLeft().startsWith(r'{\rtf')) {
      return rawContent;
    }

    final buffer = StringBuffer();
    final length = rawContent.length;
    int i = 0;

    while (i < length) {
      final char = rawContent[i];

      if (char == '{') {
        i++;
        // Check for ignorable destination groups: {\*..., {\fonttbl..., etc.
        if (i < length && rawContent[i] == '\\') {
          bool isIgnorable = false;
          int checkPos = i + 1;
          if (checkPos < length && rawContent[checkPos] == '*') {
            isIgnorable = true;
          } else {
            final startCtrl = checkPos;
            while (checkPos < length && _isRtfLetter(rawContent[checkPos])) {
              checkPos++;
            }
            final word = rawContent.substring(startCtrl, checkPos);
            if (word == 'fonttbl' ||
                word == 'colortbl' ||
                word == 'stylesheet' ||
                word == 'info' ||
                word == 'generator' ||
                word == 'nonesttables' ||
                word == 'expandedcolortbl') {
              isIgnorable = true;
            }
          }

          if (isIgnorable) {
            int depth = 1;
            while (i < length && depth > 0) {
              if (rawContent[i] == '{') {
                depth++;
              } else if (rawContent[i] == '}') {
                depth--;
              } else if (rawContent[i] == '\\' && i + 1 < length) {
                i++; // Skip escaped char
              }
              i++;
            }
            continue;
          }
        }
        continue;
      }

      if (char == '}') {
        i++;
        continue;
      }

      if (char == '\\') {
        i++;
        if (i >= length) break;
        final nextChar = rawContent[i];

        // Escaped literal characters
        if (nextChar == '\\' || nextChar == '{' || nextChar == '}') {
          buffer.write(nextChar);
          i++;
          continue;
        }

        // Hex escape: \'xx
        if (nextChar == "'") {
          i++;
          if (i + 2 <= length) {
            final hex = rawContent.substring(i, i + 2);
            final code = int.tryParse(hex, radix: 16);
            if (code != null) {
              buffer.write(String.fromCharCode(code));
            }
            i += 2;
          }
          continue;
        }

        // Backslash-newline or line breaks
        if (nextChar == '\n' || nextChar == '\r') {
          buffer.write('\n');
          i++;
          continue;
        }

        // Read control word (lower-case a-z in RTF)
        final startWord = i;
        while (i < length && _isRtfLetter(rawContent[i])) {
          i++;
        }
        final controlWord = rawContent.substring(startWord, i);

        // Control symbols without letters (e.g., \*, \~, \_)
        if (controlWord.isEmpty) {
          if (nextChar == '~') buffer.write(' ');
          if (nextChar == '_') buffer.write('-');
          i++;
          continue;
        }

        // Optional numeric parameter
        final startNum = i;
        if (i < length && (rawContent[i] == '-' || _isDigit(rawContent[i]))) {
          i++;
          while (i < length && _isDigit(rawContent[i])) {
            i++;
          }
        }
        final paramStr = rawContent.substring(startNum, i);

        // Control word delimiter (single space)
        if (i < length && rawContent[i] == ' ') {
          i++;
        }

        // Check for line-break control words
        if (controlWord == 'par' || controlWord == 'line' || controlWord == 'row') {
          buffer.write('\n');
        } else if (controlWord == 'tab') {
          buffer.write('\t');
        } else if (controlWord == 'u' && paramStr.isNotEmpty) {
          int? codePoint = int.tryParse(paramStr);
          if (codePoint != null) {
            if (codePoint < 0) codePoint += 65536;
            buffer.write(String.fromCharCode(codePoint));
          }
          // RTF unicode commands are usually followed by an ASCII replacement character or '?'
          if (i < length && rawContent[i] == '?') {
            i++;
          }
        }
        continue;
      }

      buffer.write(char);
      i++;
    }

    return buffer.toString();
  }

  static bool _isRtfLetter(String char) {
    final code = char.codeUnitAt(0);
    return code >= 97 && code <= 122;
  }

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  /// Parses lines of text into a list of [ParsedConventionEntry] objects.
  ///
  /// Lines that do not match the Televisa / ViX naming convention pattern are ignored.
  static List<ParsedConventionEntry> parseLines(String text) {
    final entries = <ParsedConventionEntry>[];
    final lines = text.split(RegExp(r'\r?\n'));

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final match = conventionPattern.firstMatch(line);
      if (match != null) {
        entries.add(ParsedConventionEntry(
          nomenclature: match.group(1)!,
          chapter: match.group(2)!,
          scene: match.group(3)!,
          plane: match.group(4),
          take: match.group(5)!,
          reel: match.group(6)!,
          day: match.group(7)!,
          clipIndex: match.group(8)!,
          unit: match.group(9)!,
          subConvention: match.group(10),
          rawLine: line,
        ));
      } else {
        final microMatch = micronovelaPattern.firstMatch(line);
        if (microMatch != null) {
          entries.add(ParsedConventionEntry(
            nomenclature: microMatch.group(1)!,
            chapter: microMatch.group(3)!,
            scene: microMatch.group(4)!,
            plane: microMatch.group(5),
            take: microMatch.group(6)!,
            reel: microMatch.group(7)!,
            clipIndex: microMatch.group(8)!,
            day: microMatch.group(9)!,
            unit: microMatch.group(10)!,
            subConvention: microMatch.group(11),
            rawLine: line,
          ));
        }
      }
    }

    return entries;
  }

  /// Groups [entries] into a Map keyed by reel name (e.g. `'A001'`, `'B001'`, `'GPR1'`).
  static Map<String, List<ParsedConventionEntry>> segmentByReel(
    List<ParsedConventionEntry> entries,
  ) {
    final map = <String, List<ParsedConventionEntry>>{};
    for (final entry in entries) {
      map.putIfAbsent(entry.reel, () => []).add(entry);
    }
    return map;
  }

  /// Converts parsed convention [entries] into a [ShootingLog] containing
  /// [ShotRecord] models.
  static ShootingLog toShootingLog(
    List<ParsedConventionEntry> entries, {
    String production = '',
    String date = '',
  }) {
    final first = entries.isNotEmpty ? entries.first : null;
    final effectiveProduction = production.isNotEmpty
        ? production
        : (first?.nomenclature ?? '');
    final effectiveDate = date.isNotEmpty ? date : (first?.day ?? '');

    final cameraSet = <String>{};
    for (final entry in entries) {
      if (entry.isGpr) {
        cameraSet.add('GPR');
      } else if (entry.isDr) {
        cameraSet.add('DR');
      } else if (entry.isFf) {
        cameraSet.add('FF');
      } else if (entry.reel.isNotEmpty) {
        cameraSet.add(entry.reel.substring(0, 1).toUpperCase());
      }
    }
    if (cameraSet.isEmpty) {
      cameraSet.add('A');
    }

    final records = <ShotRecord>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final isTf = e.isTf;

      String cleanTake = e.take;
      if (isTf) {
        final stripped = e.take.substring(2);
        cleanTake = stripped.isEmpty ? '1' : stripped;
      } else if (cleanTake.toUpperCase().startsWith('T')) {
        cleanTake = cleanTake.substring(1);
      }

      String camName = 'A';
      if (e.isGpr) {
        camName = 'GPR';
      } else if (e.isDr) {
        camName = 'DR';
      } else if (e.isFf) {
        camName = 'FF';
      } else if (e.reel.isNotEmpty) {
        camName = e.reel.substring(0, 1).toUpperCase();
      }

      final parsedClipInt = int.tryParse(e.clipIndex);
      final normalizedClip = parsedClipInt != null ? parsedClipInt.toString().padLeft(3, '0') : e.clipIndex;

      records.add(ShotRecord(
        id: 'rec_${i + 1}',
        chapter: e.chapter,
        scene: e.scene,
        plane: e.plane,
        take: cleanTake,
        cameras: [
          CameraTakeRecord(cameraName: camName, clipName: normalizedClip),
        ],
        reel: e.reel,
        isTf: isTf,
        isDs: e.isDs,
        isGpr: e.isGpr,
        isDr: e.isDr,
        isFf: e.isFf,
        observations: e.subConvention,
      ));
    }

    return ShootingLog(
      metadata: ShootingLogMetadata.empty().copyWith(
        production: effectiveProduction,
        date: effectiveDate,
        nomenclature: effectiveProduction,
        day: first?.day ?? '',
        unit: first?.unit ?? '',
      ),
      records: records,
    );
  }
}
