class ConventionNameGenerator {
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
  }) {
    nomenclature = nomenclature.trim();
    date = date.trim();
    scene = scene.trim();
    plane = plane?.trim();
    take = take.trim();
    reel = reel.trim();
    day = day.trim();
    unit = unit.trim();

    String formattedTake = take;
    if (int.tryParse(take) != null) {
      formattedTake = 'T$take';
    }

    List<String> parts = [
      nomenclature,
      date,
      scene,
    ];

    if (plane != null && plane.isNotEmpty) {
      parts.add(plane);
    }

    parts.add(formattedTake);
    
    String finalReel = reel;
    if (reelOverride != null && reelOverride.trim().isNotEmpty) {
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
          }
        }
      }
    }

    if (finalReel.isNotEmpty) parts.add(finalReel);
    if (day.isNotEmpty) parts.add(day);
    if (unit.isNotEmpty) parts.add(unit);

    return parts.where((part) => part.isNotEmpty).join('_');
  }
}
