/// Generates standardized media naming conventions according to the Televisa /
/// ViX post-production standard.
///
/// Supports physical filename generation as well as full proforma / verificador
/// naming with the `%` separator, with automatic camera overrides for GoPro
/// (`GPR1`), Drone (`DR1`), Free Fly (`NFF`), Driving Shot (`DS`), and Toma Falsa (`TF`).
class ConventionNameGenerator {
  /// Generates a naming convention string.
  ///
  /// If [includeProforma] is `true`, appends `%{TARJ}_{CLIP}_{DGRAB}_{UCR}`.
  static String generate({
    required String nomenclature,
    required String date,
    required String scene,
    String? plane,
    required String take,
    required String reel,
    required String day,
    required String unit,
    String activeCamera = 'A',
    String? reelOverride,
    String? chapter,
    String? clipIndex,
    bool isGpr = false,
    bool isDs = false,
    bool isTf = false,
    bool isDr = false,
    bool isFf = false,
    bool includeProforma = false,
    String? cardName,
  }) {
    nomenclature = nomenclature.trim();
    date = date.trim();
    scene = scene.trim();
    plane = plane?.trim();
    take = take.trim();
    reel = reel.trim();
    day = day.trim();
    unit = unit.trim();
    chapter = chapter?.trim();
    clipIndex = clipIndex?.trim();

    // 1. Chapter vs Date
    final dateOrChapter = (chapter != null && chapter.isNotEmpty)
        ? chapter
        : date;

    // 2. Unit override for Driving Shot
    String finalUnit = unit;
    if (isDs) {
      finalUnit = 'DS';
    }

    // 3. Take formatting & Toma Falsa
    String formattedTake = take;
    if (isTf) {
      final upper = take.toUpperCase();
      if (upper.startsWith('TF')) {
        formattedTake = upper;
      } else if (upper.startsWith('T')) {
        formattedTake = 'TF${take.substring(1)}';
      } else if (take.isNotEmpty) {
        formattedTake = 'TF$take';
      } else {
        formattedTake = 'TF1';
      }
    } else {
      if (int.tryParse(take) != null) {
        formattedTake = 'T$take';
      }
    }

    // 4. Camera / Reel resolution
    String finalReel;
    if (isGpr) {
      finalReel = 'GPR1';
    } else if (isDr) {
      finalReel = 'DR1';
    } else if (isFf) {
      finalReel = 'NFF';
    } else if (reelOverride != null && reelOverride.trim().isNotEmpty) {
      finalReel = reelOverride.trim();
    } else {
      if (reel.isEmpty) {
        finalReel = '${activeCamera}001';
      } else {
        final letterMatch = RegExp(r'^([A-Za-z])(\d+.*)$').firstMatch(reel);
        if (letterMatch != null) {
          finalReel = '$activeCamera${letterMatch.group(2)}';
        } else {
          final numericMatch = RegExp(r'^(\d+.*)$').firstMatch(reel);
          if (numericMatch != null) {
            finalReel = '$activeCamera$reel';
          } else {
            finalReel = reel;
          }
        }
      }
    }

    // 5. Clip index resolution (GoPro uses 2 digits: 01, 02)
    String? formattedClip;
    if (clipIndex != null && clipIndex.isNotEmpty) {
      if (isGpr) {
        final parsed = int.tryParse(clipIndex);
        formattedClip = parsed != null
            ? parsed.toString().padLeft(2, '0')
            : clipIndex.padLeft(2, '0');
      } else {
        formattedClip = clipIndex;
      }
    }

    // 6. Assemble physical convention
    final parts = <String>[
      nomenclature,
      dateOrChapter,
      scene,
    ];

    if (plane != null && plane.isNotEmpty) {
      parts.add(plane);
    }

    parts.add(formattedTake);

    if (finalReel.isNotEmpty) parts.add(finalReel);
    if (day.isNotEmpty) parts.add(day);
    if (formattedClip != null && formattedClip.isNotEmpty) parts.add(formattedClip);
    if (finalUnit.isNotEmpty) parts.add(finalUnit);

    final physicalName = parts.where((part) => part.isNotEmpty).join('_');

    if (!includeProforma) {
      return physicalName;
    }

    // 7. Full Proforma/Verificador string:
    // {PROD}_{CAP}_{ESC}_{TOMA}_{CAM}_{CLIP}_{DGRAB}_{UCR}%{TARJ}_{CLIP}_{DGRAB}_{UCR}
    final effectiveTarj = (cardName != null && cardName.trim().isNotEmpty)
        ? cardName.trim()
        : (finalReel.isNotEmpty ? finalReel : 'TARJ');
    final effectiveClip = (formattedClip != null && formattedClip.isNotEmpty)
        ? formattedClip
        : 'CLIP';
    final effectiveDay = day.isNotEmpty ? day : 'D01';
    final effectiveUnit = finalUnit.isNotEmpty ? finalUnit : 'U1';

    final subConvention = '${effectiveTarj}_${effectiveClip}_${effectiveDay}_$effectiveUnit';
    return '$physicalName%$subConvention';
  }

  /// Convenience method to generate the full Proforma/Verificador convention string
  /// containing the `%` delimiter.
  static String generateProforma({
    required String nomenclature,
    required String date,
    required String scene,
    String? plane,
    required String take,
    required String reel,
    required String day,
    required String unit,
    String activeCamera = 'A',
    String? reelOverride,
    String? chapter,
    String? clipIndex,
    bool isGpr = false,
    bool isDs = false,
    bool isTf = false,
    bool isDr = false,
    bool isFf = false,
    String? cardName,
  }) {
    return generate(
      nomenclature: nomenclature,
      date: date,
      scene: scene,
      plane: plane,
      take: take,
      reel: reel,
      day: day,
      unit: unit,
      activeCamera: activeCamera,
      reelOverride: reelOverride,
      chapter: chapter,
      clipIndex: clipIndex,
      isGpr: isGpr,
      isDs: isDs,
      isTf: isTf,
      isDr: isDr,
      isFf: isFf,
      includeProforma: true,
      cardName: cardName,
    );
  }
}
