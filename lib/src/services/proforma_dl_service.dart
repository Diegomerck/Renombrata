import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/proforma_dl_metadata.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/services/digitallogic_xml_service.dart';

/// Represents parsed components of a production media filename.
class ParsedConventionFilename {
  final String raw;
  final String production;
  final String chapter;
  final String scene;
  final String take;
  final String camera;
  final String day;
  final String unitCard;
  final String clipName;
  final String? existingSubConvention;

  const ParsedConventionFilename({
    required this.raw,
    required this.production,
    required this.chapter,
    required this.scene,
    required this.take,
    required this.camera,
    required this.day,
    required this.unitCard,
    required this.clipName,
    this.existingSubConvention,
  });

  @override
  String toString() {
    return 'ParsedConventionFilename(prod: $production, ch: $chapter, sc: $scene, '
        'take: $take, cam: $camera, day: $day, unitCard: $unitCard, '
        'clipName: $clipName, sub: $existingSubConvention)';
  }
}

/// Service for parsing convention filenames and generating DigitalLogic 3.2
/// Proforma_DL XML sidecars.
class ProformaDlService {
  const ProformaDlService();

  /// Known media extensions to strip when parsing filenames.
  static final RegExp _mediaExtRegex = RegExp(
    r'\.(mxf|mov|mp4|avi|xml|m4v|mkv|wav|mp3)$',
    caseSensitive: false,
  );

  /// Strips directories and media file extensions from a filename or path.
  static String cleanFilename(String pathOrFilename) {
    var name = p.basename(pathOrFilename.trim());
    name = name.replaceAll(_mediaExtRegex, '');
    return name;
  }

  /// Parses convention filenames such as:
  /// `INOCENCIA_01_15_PROT1_CAM1_D03_UCR14.mxf`
  /// or full proforma strings:
  /// `INOCENCIA_01_15_PROT1_CAM1_D03_UCR14%1_6_D03_U14B.mxf`
  static ParsedConventionFilename parseConventionFilename(String input) {
    final cleaned = cleanFilename(input);
    if (cleaned.isEmpty) {
      return const ParsedConventionFilename(
        raw: '',
        production: '',
        chapter: '',
        scene: '',
        take: '',
        camera: '',
        day: '',
        unitCard: '',
        clipName: '',
      );
    }

    String clipName = cleaned;
    String? existingSub;
    if (cleaned.contains('%')) {
      final parts = cleaned.split('%');
      clipName = parts[0].trim();
      if (parts.length > 1) {
        existingSub = parts[1].trim();
      }
    }

    final tokens = clipName.split('_').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) {
      return ParsedConventionFilename(
        raw: input,
        production: '',
        chapter: '',
        scene: '',
        take: '',
        camera: '',
        day: '',
        unitCard: '',
        clipName: clipName,
        existingSubConvention: existingSub,
      );
    }

    // 1. Production is token 0
    final production = tokens.removeAt(0);

    // 2. Trailing tokens extraction: Unit/Card, Day, Camera
    String unitCard = '';
    String day = '';
    String camera = '';

    // Unit / Card regex (e.g. UCR14, U1, U3, DS, U14B)
    if (tokens.isNotEmpty &&
        (RegExp(r'^U(CR)?\w*$', caseSensitive: false).hasMatch(tokens.last) ||
            tokens.last.toUpperCase() == 'DS')) {
      unitCard = tokens.removeLast();
    }

    // Day regex (e.g. D03, D1, D24)
    if (tokens.isNotEmpty &&
        RegExp(r'^D\d+$', caseSensitive: false).hasMatch(tokens.last)) {
      day = tokens.removeLast();
    }

    // Camera regex (e.g. CAM1, CAM A, CAMA, A001, GPR1, DR1, NFF)
    if (tokens.isNotEmpty &&
        (RegExp(r'^(CAM\s*[\dA-Za-z]+|[A-Z]\d{2,4}|GPR\d*|DR\d*|NFF)$',
                caseSensitive: false)
            .hasMatch(tokens.last))) {
      camera = tokens.removeLast();
    }

    // 3. Middle tokens: Chapter, Scene, Take
    String chapter = '';
    String scene = '';
    String take = '';

    // If first token of remaining looks like chapter (digits e.g. '01' or '1')
    if (tokens.length >= 3) {
      chapter = tokens.removeAt(0);
      scene = tokens.removeAt(0);
      take = tokens.join('_');
    } else if (tokens.length == 2) {
      // Could be chapter & scene, or scene & take.
      // If second token matches take patterns (T1, PROT1, SEC1, TF1, etc.), then scene & take
      if (RegExp(r'^(PROT|SEC|TF?|T)\w*$', caseSensitive: false)
          .hasMatch(tokens[1])) {
        scene = tokens[0];
        take = tokens[1];
      } else {
        chapter = tokens[0];
        scene = tokens[1];
      }
    } else if (tokens.length == 1) {
      if (RegExp(r'^(PROT|SEC|TF?|T)\w*$', caseSensitive: false)
          .hasMatch(tokens[0])) {
        take = tokens[0];
      } else {
        scene = tokens[0];
      }
    }

    // Fallbacks if take is empty
    if (take.isEmpty) {
      take = 'T1';
    }

    return ParsedConventionFilename(
      raw: input,
      production: production,
      chapter: chapter,
      scene: scene,
      take: take,
      camera: camera,
      day: day,
      unitCard: unitCard,
      clipName: clipName,
      existingSubConvention: existingSub,
    );
  }

  /// Extracts numeric card index from camera (e.g. "CAM1" -> "1", "A001" -> "1")
  /// or unitCard, defaulting to "1".
  static String extractCardNumber(String camera, {String defaultCard = '1'}) {
    final camDigits = camera.replaceAll(RegExp(r'\D'), '');
    if (camDigits.isNotEmpty) {
      final parsed = int.tryParse(camDigits);
      if (parsed != null) return parsed.toString();
    }
    return defaultCard;
  }

  /// Derives sub-reel ID from unitCard.
  /// E.g. "UCR14" -> "U14B" (or "U14" with suffix).
  static String deriveSubReelId(String unitCard, {String suffix = 'B'}) {
    final trimmed = unitCard.trim();
    if (trimmed.isEmpty) return 'U1$suffix';

    // If it starts with UCR (e.g. UCR14) -> U14 + suffix
    final ucrMatch = RegExp(r'^UCR(\d+.*)$', caseSensitive: false)
        .firstMatch(trimmed);
    if (ucrMatch != null) {
      final numPart = ucrMatch.group(1)!;
      // If it already ends with a letter, don't append suffix
      if (RegExp(r'[A-Za-z]$').hasMatch(numPart)) {
        return 'U$numPart';
      }
      return 'U$numPart$suffix';
    }

    // If it starts with U followed by digits (e.g. U14)
    final uMatch = RegExp(r'^U(\d+.*)$', caseSensitive: false)
        .firstMatch(trimmed);
    if (uMatch != null) {
      final rest = uMatch.group(1)!;
      if (RegExp(r'[A-Za-z]$').hasMatch(rest)) {
        return 'U$rest';
      }
      return 'U$rest$suffix';
    }

    return '$trimmed$suffix';
  }

  /// Builds the sub-convention string after the `%` separator.
  /// Format: `{cardNumber}_{clipSequenceNumber}_{day}_{unitSubId}`
  /// Example: `1_6_D03_U14B`
  static String buildSubConvention({
    required String cardNumber,
    required int clipSequenceNumber,
    required String day,
    required String unitSubId,
  }) {
    final cleanCard = cardNumber.trim().isEmpty ? '1' : cardNumber.trim();
    final cleanDay = day.trim().isEmpty ? 'D01' : day.trim();
    final cleanUnit = unitSubId.trim().isEmpty ? 'U1B' : unitSubId.trim();
    return '${cleanCard}_${clipSequenceNumber}_${cleanDay}_$cleanUnit';
  }

  /// Builds the full convention name combining the physical clipName and sub-convention.
  /// Format: `{clipName}%{subConvention}`
  static String buildFullConvention({
    required String clipName,
    required String subConvention,
  }) {
    return '$clipName%$subConvention';
  }

  /// Creates a [ProformaDlMetadata] instance from a file path and optional project context.
  static ProformaDlMetadata createMetadata({
    required String filePath,
    int clipSequenceNumber = 1,
    RenombrataProject? project,
    String? defaultOperador,
    String? defaultPais,
    String? defaultCiudad,
    String? defaultUbicacion,
    String? defaultTemporalidad,
    String? defaultVideoObs,
    String? defaultAudioObs,
    String? defaultLugar,
    String? defaultSinopsis,
    String? defaultVfxCompuestos,
    String? defaultDescripcionVfx,
  }) {
    final filename = p.basename(filePath);
    final parsed = parseConventionFilename(filename);

    final cardNum = extractCardNumber(parsed.camera);
    final unitSub = deriveSubReelId(parsed.unitCard);

    final subConv = parsed.existingSubConvention ??
        buildSubConvention(
          cardNumber: cardNum,
          clipSequenceNumber: clipSequenceNumber,
          day: parsed.day,
          unitSubId: unitSub,
        );

    final fullConv = buildFullConvention(
      clipName: parsed.clipName,
      subConvention: subConv,
    );

    // Cross-reference with project bitácora if available
    String matchedLugar = defaultLugar ?? project?.log.metadata.location ?? '';
    String matchedSinopsis = defaultSinopsis ?? '';
    String matchedIngestor = defaultOperador ??
        (project?.log.metadata.ingestor.isNotEmpty == true
            ? project!.log.metadata.ingestor
            : '');
    bool isSelected = true;

    if (project != null && project.log.records.isNotEmpty) {
      // Find matching record by scene & take
      final match = project.log.records.cast<dynamic>().firstWhere(
        (r) {
          final sc = r.scene.toString().trim().toUpperCase();
          final tk = r.take.toString().trim().toUpperCase();
          final parsedSc = parsed.scene.trim().toUpperCase();
          final parsedTk = parsed.take.trim().toUpperCase();
          return sc == parsedSc && (tk == parsedTk || 'T$tk' == parsedTk || tk == 'T$parsedTk');
        },
        orElse: () => null,
      );

      if (match != null) {
        if (match.observations != null && match.observations.toString().trim().isNotEmpty) {
          matchedSinopsis = match.observations.toString().trim();
        }
        if (match.isTf == true) {
          isSelected = false;
        }
      }
    }

    return ProformaDlMetadata(
      filePath: filePath,
      originalFileName: filename,
      produccionNombre: parsed.production.isNotEmpty
          ? parsed.production
          : (project?.log.metadata.production ?? 'PRODUCCION'),
      convencionNombre: fullConv,
      clipName: parsed.clipName,
      subConvention: subConv,
      fuente: 'Portátil',
      ubicacion: defaultUbicacion ?? 'Exterior',
      temporalidad: defaultTemporalidad ?? 'Día',
      tomaSeleccionada: isSelected,
      pais: defaultPais ?? 'MEXICO',
      ciudad: defaultCiudad ?? 'CDMX',
      lugar: matchedLugar,
      vfxCompuestos: defaultVfxCompuestos ?? 'No',
      descripcionVfx: defaultDescripcionVfx ?? '',
      observacionesVideo: defaultVideoObs ?? 'OK SLOG 3',
      observacionesAudio: defaultAudioObs ?? 'MIX Y MULTITRACK',
      sinopsis: matchedSinopsis,
      operadorIngesta: matchedIngestor,
      chapter: parsed.chapter,
      scene: parsed.scene,
      take: parsed.take,
      camera: parsed.camera,
      day: parsed.day,
      unitCard: parsed.unitCard,
      cardNumber: cardNum,
      clipSequenceNumber: clipSequenceNumber,
      unitSubId: unitSub,
    );
  }

  /// Generates the XML string for a [ProformaDlMetadata] entry.
  static String generateXml(ProformaDlMetadata item) {
    return DigitalLogicXmlService.generateProformaDlXml(
      produccionNombre: item.produccionNombre,
      convencionNombre: item.convencionNombre,
      clipName: item.clipName,
      fuente: item.fuente,
      ubicacion: item.ubicacion,
      temporalidad: item.temporalidad,
      tomaSeleccionada: item.tomaSeleccionada,
      pais: item.pais,
      ciudad: item.ciudad,
      lugar: item.lugar,
      vfxCompuestos: item.vfxCompuestos,
      descripcionVfx: item.descripcionVfx,
      observacionesVideo: item.observacionesVideo,
      observacionesAudio: item.observacionesAudio,
      sinopsis: item.sinopsis,
      operadorIngesta: item.operadorIngesta,
    );
  }

  /// Writes sidecar XML files for a batch of [ProformaDlMetadata] entries.
  ///
  /// Returns a map of `{filePath: writtenXmlFile}`.
  static Future<Map<String, File>> batchGenerateSidecars({
    required List<ProformaDlMetadata> items,
    bool overwrite = true,
  }) async {
    final results = <String, File>{};

    for (final item in items) {
      final xmlContent = generateXml(item);
      final file = await DigitalLogicXmlService.writeXmlSidecar(
        mediaFilePath: item.filePath,
        xmlContent: xmlContent,
        overwrite: overwrite,
      );
      results[item.filePath] = file;
    }

    return results;
  }
}
