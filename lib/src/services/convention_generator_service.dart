import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/renombrata_project.dart';

/// Service responsible for generating and parsing standardized convention strings
/// based on project production parameters and customizable token orders.
class ConventionGeneratorService {
  /// Formats a raw date string into a 6-digit DDMMYY format.
  /// Handles ISO format ("2026-06-08"), slash/dash formats ("08/06/2026", "08-06-2026"),
  /// or raw 6/8-digit numeric strings.
  static String formatDateDDMMYY(String rawDate) {
    final trimmed = rawDate.trim();
    if (trimmed.isEmpty) return '';

    // 1. Try ISO or standard DateTime parsing (e.g. 2026-06-08)
    final dt = DateTime.tryParse(trimmed);
    if (dt != null) {
      final dd = dt.day.toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final yy = (dt.year % 100).toString().padLeft(2, '0');
      return '$dd$mm$yy';
    }

    // 2. Check regex patterns like DD/MM/YYYY, DD-MM-YYYY, DD/MM/YY
    final slashMatch = RegExp(
      r'^(\d{1,2})[/\.-](\d{1,2})[/\.-](\d{2,4})$',
    ).firstMatch(trimmed);
    if (slashMatch != null) {
      final part1 = int.parse(slashMatch.group(1)!);
      final part2 = int.parse(slashMatch.group(2)!);
      final part3 = int.parse(slashMatch.group(3)!);
      final dd = part1.toString().padLeft(2, '0');
      final mm = part2.toString().padLeft(2, '0');
      final yy = (part3 % 100).toString().padLeft(2, '0');
      return '$dd$mm$yy';
    }

    // 3. Strip non-digits and inspect length
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 6) {
      return digits;
    }
    if (digits.length == 8) {
      if (digits.startsWith('19') || digits.startsWith('20')) {
        // YYYYMMDD
        final yyyy = digits.substring(0, 4);
        final mm = digits.substring(4, 6);
        final dd = digits.substring(6, 8);
        return '$dd$mm${yyyy.substring(2)}';
      } else {
        // DDMMYYYY
        final dd = digits.substring(0, 2);
        final mm = digits.substring(2, 4);
        final yy = digits.substring(6, 8);
        return '$dd$mm$yy';
      }
    }

    return digits;
  }

  /// Combines reel and camera into a camera-prefixed reel string (e.g. "A001").
  static String formatReelWithCamera(String reel, String camera) {
    reel = reel.trim();
    camera = camera.trim().toUpperCase();
    if (reel.isEmpty) {
      return camera.isNotEmpty ? '${camera}001' : '001';
    }

    // If reel is numeric (e.g. "1" or "001")
    final numMatch = RegExp(r'^\d+$').firstMatch(reel);
    if (numMatch != null) {
      final padded = reel.padLeft(3, '0');
      return camera.isNotEmpty ? '$camera$padded' : padded;
    }

    // If reel has leading alpha characters (e.g. "A001", "B01")
    final alphaMatch = RegExp(r'^([A-Za-z]+)(\d.*)$').firstMatch(reel);
    if (alphaMatch != null) {
      final existingCam = alphaMatch.group(1)!.toUpperCase();
      final rest = alphaMatch.group(2)!;
      final paddedRest = rest.length < 3 && int.tryParse(rest) != null
          ? rest.padLeft(3, '0')
          : rest;
      if (camera.isNotEmpty) {
        return '$camera$paddedRest';
      }
      return '$existingCam$paddedRest';
    }

    return camera.isNotEmpty && !reel.toUpperCase().startsWith(camera)
        ? '$camera$reel'
        : reel;
  }

  /// Formats the take string, prefixing with "T" if not already prefixed.
  static String formatTake(String take) {
    take = take.trim();
    if (take.isEmpty) return 'T1';
    final upper = take.toUpperCase();
    if (upper.startsWith('T')) {
      return upper;
    }
    return 'T$take';
  }

  /// Constructs the full convention string following the project settings and conventionNameOrder.
  static String generateConventionName({
    required RenombrataProject project,
    required String chapter,
    required String scene,
    String? plane,
    required String take,
    required String reel,
    required String camera,
    required int clipIndex,
  }) {
    final tokens = <String>[];

    // 1. Header tokens
    final nomenclature = project.log.metadata.nomenclature.trim();
    if (nomenclature.isNotEmpty) {
      tokens.add(nomenclature);
    }

    final dateStr = formatDateDDMMYY(project.log.metadata.date);
    if (dateStr.isNotEmpty) {
      tokens.add(dateStr);
    }

    // 2. Variable tokens ordered by project.conventionNameOrder
    for (final element in project.conventionNameOrder) {
      switch (element.toLowerCase()) {
        case 'capitulo':
          if (project.showChapter && chapter.trim().isNotEmpty) {
            tokens.add(chapter.trim());
          }
          break;
        case 'escena':
          if (scene.trim().isNotEmpty) {
            tokens.add(scene.trim());
          }
          break;
        case 'plano':
          if (project.showPlane && plane != null && plane.trim().isNotEmpty) {
            tokens.add(plane.trim());
          }
          break;
        case 'toma':
          if (take.trim().isNotEmpty) {
            tokens.add(formatTake(take));
          }
          break;
      }
    }

    // 3. Trailing tokens: Reel with camera, Clip index, Day, Unit
    final camType = project.getCameraType(camera);
    final isDs = camType == CameraType.drivingShot;
    final isFf = camType == CameraType.freeFly;
    final isGpr = camType == CameraType.goPro;
    final isDr = camType == CameraType.drone;

    String finalReel;
    if (isGpr) {
      finalReel = 'GPR1';
    } else if (isDr) {
      finalReel = 'DR1';
    } else if (isFf) {
      finalReel = 'NFF';
    } else {
      finalReel = formatReelWithCamera(reel, camera);
    }
    if (finalReel.isNotEmpty) {
      tokens.add(finalReel);
    }

    if (isGpr) {
      tokens.add(clipIndex.toString().padLeft(2, '0'));
    } else {
      tokens.add(clipIndex.toString());
    }

    final day = project.log.metadata.day.trim();
    if (day.isNotEmpty) {
      final dayToken = day.toUpperCase().startsWith('D')
          ? day.toUpperCase()
          : 'D$day';
      tokens.add(dayToken);
    }

    final unit = isDs ? 'DS' : project.log.metadata.unit.trim();
    if (unit.isNotEmpty) {
      final unitToken = (isDs || unit.toUpperCase().startsWith('U'))
          ? (isDs ? 'DS' : unit.toUpperCase())
          : 'U$unit';
      tokens.add(unitToken);
    }

    return tokens.join('_');
  }

  /// Parses an edited convention line by extracting variable fields
  /// (chapter, scene, plane, take, reel, clipIndex) based on the project's
  /// conventionNameOrder and metadata tokens.
  ///
  /// Returns a [Map] containing the extracted field values, or `null` if the
  /// line cannot be recognized as a valid convention format.
  static Map<String, String>? parseConventionLine({
    required String line,
    required RenombrataProject project,
  }) {
    String clean = line.trim();
    if (clean.contains('%')) {
      clean = clean.split('%').first;
    }
    final ext = p.extension(clean);
    if (ext.isNotEmpty &&
        ext.length <= 5 &&
        RegExp(r'^\.[a-zA-Z0-9]+$').hasMatch(ext)) {
      clean = p.basenameWithoutExtension(clean);
    }
    if (clean.isEmpty) return null;

    final tokens = clean.split('_').where((t) => t.isNotEmpty).toList();
    // A convention string must have at least nomenclature/date, scene, take, reel, clipIndex
    if (tokens.length < 3) {
      return null;
    }

    // 1. Consume Header tokens
    final projNom = project.log.metadata.nomenclature.trim().toUpperCase();
    if (projNom.isNotEmpty &&
        tokens.isNotEmpty &&
        tokens.first.toUpperCase() == projNom) {
      tokens.removeAt(0);
    } else if (projNom.isEmpty &&
        tokens.isNotEmpty &&
        !RegExp(r'^\d+$').hasMatch(tokens.first)) {
      tokens.removeAt(0);
    }

    final formattedDate = formatDateDDMMYY(project.log.metadata.date);
    if (tokens.isNotEmpty) {
      final candidateDate = tokens.first;
      if ((formattedDate.isNotEmpty && candidateDate == formattedDate) ||
          RegExp(r'^\d{6}$').hasMatch(candidateDate)) {
        tokens.removeAt(0);
      }
    }

    // 2. Consume Trailing tokens from the end: Unit, Day, ClipIndex, Reel
    String? unit;
    String? day;
    String? clipIndex;
    String? reel;

    if (tokens.isNotEmpty &&
        (RegExp(r'^U\w+$', caseSensitive: false).hasMatch(tokens.last) ||
            tokens.last.toUpperCase() == 'DS')) {
      unit = tokens.removeLast();
    }

    if (tokens.isNotEmpty &&
        RegExp(r'^D\w+$', caseSensitive: false).hasMatch(tokens.last)) {
      day = tokens.removeLast();
      if (tokens.isNotEmpty && RegExp(r'^\d+$').hasMatch(tokens.last)) {
        clipIndex = tokens.removeLast();
      }
    } else if (tokens.isNotEmpty && RegExp(r'^\d+$').hasMatch(tokens.last)) {
      clipIndex = tokens.removeLast();
      if (tokens.isNotEmpty &&
          RegExp(r'^D\w+$', caseSensitive: false).hasMatch(tokens.last)) {
        day = tokens.removeLast();
      }
    }

    String? rawReel;
    String? camera;
    if (tokens.isNotEmpty) {
      final candidateReel = tokens.last;
      final isTake = RegExp(
        r'^(TF?\d+|T\d{1,2})$',
        caseSensitive: false,
      ).hasMatch(candidateReel);
      if (!isTake) {
        // Reel typically matches camera + 3 digits (e.g. A001, B002), numeric digits (e.g. 001), or specialized tags (GPR1, DR1, NFF)
        final reelMatch = RegExp(
          r'^([A-Za-z]+)?(\d+.*)$',
        ).firstMatch(candidateReel);
        final isSpecialReel = RegExp(
          r'^(GPR\d*|DR\d*|NFF)$',
          caseSensitive: false,
        ).hasMatch(candidateReel);
        if (reelMatch != null || isSpecialReel) {
          rawReel = tokens.removeLast();
          // Extract numeric portion if it had a camera prefix
          if (reelMatch != null &&
              reelMatch.group(1) != null &&
              reelMatch.group(2) != null) {
            camera = reelMatch.group(1)!.toUpperCase();
            reel = reelMatch.group(2);
          } else {
            reel = rawReel;
          }
        }
      }
    }

    // If we couldn't even extract clipIndex and reel, or no middle tokens remain, check if invalid
    if (tokens.isEmpty && clipIndex == null && reel == null) {
      return null;
    }

    // 3. Middle tokens correspond to variable tokens in project.conventionNameOrder
    String chapter = '';
    String scene = '';
    String? plane;
    String take = '1';

    // Identify take token if it starts with 'T' or 'TF'
    int takeIndex = -1;
    for (int i = 0; i < tokens.length; i++) {
      if (RegExp(
        r'^(TF?\d+|T\w+)$',
        caseSensitive: false,
      ).hasMatch(tokens[i])) {
        takeIndex = i;
        break;
      }
    }

    if (takeIndex != -1) {
      final rawTake = tokens.removeAt(takeIndex);
      final upper = rawTake.toUpperCase();
      if (upper.startsWith('TF')) {
        take = upper;
      } else if (upper.startsWith('T')) {
        take = rawTake.substring(1);
      } else {
        take = rawTake;
      }
    }

    // Remaining expected elements (excluding take which was extracted)
    final expectedElements = <String>[];
    for (final el in project.conventionNameOrder) {
      final lower = el.toLowerCase();
      if (lower == 'toma') continue;
      if (lower == 'capitulo' && !project.showChapter) continue;
      if (lower == 'plano' && !project.showPlane) continue;
      expectedElements.add(lower);
    }

    // Map remaining tokens to expected elements
    for (int i = 0; i < tokens.length && i < expectedElements.length; i++) {
      final el = expectedElements[i];
      final val = tokens[i];
      switch (el) {
        case 'capitulo':
          chapter = val;
          break;
        case 'escena':
          scene = val;
          break;
        case 'plano':
          plane = val;
          break;
      }
    }

    // Basic validity check: must have at least scene or take or reel/clipIndex
    if (scene.isEmpty && take.isEmpty && clipIndex == null) {
      return null;
    }

    return {
      'chapter': chapter,
      'scene': scene,
      'plane': ?plane,
      'take': take,
      'reel': ?reel,
      'rawReel': ?rawReel,
      'camera': ?camera,
      'clipIndex': ?clipIndex,
      'day': ?day,
      'unit': ?unit,
    };
  }
}
