import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Service for generating and writing DigitalLogic 4.0 XML metadata sidecars
/// compliant with Televisa / ViX post-production workflows.
class DigitalLogicXmlService {
  const DigitalLogicXmlService();

  /// Escapes special XML characters to prevent malformed XML.
  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Formats a [DateTime] into standard production timestamp `YYYY-MM-DD HH:mm:ss.000`.
  static String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    final s = date.second.toString().padLeft(2, '0');
    final ms = date.millisecond.toString().padLeft(3, '0');
    return '$y-$m-$d $h:$min:$s.$ms';
  }

  /// Generates a valid XML document following the DigitalLogic 4.0 schema.
  static String generateXml({
    required String productionName,
    required String chapter,
    required String scene,
    String? plane,
    required String take,
    required String cameraReel,
    required String clipIndex,
    required String shootingDay,
    required String unit,
    required String conventionName,
    required String proformaName,
    required String originalClipName,
    bool isSelectedTake = false,
    String cameraType = 'DIGITAL',
    String notes = '',
    DateTime? recordingDate,
  }) {
    final safeProductionName = _escapeXml(productionName);
    final safeChapter = _escapeXml(chapter);
    final safeScene = _escapeXml(scene);
    final safePlane = _escapeXml(plane ?? '');
    final safeTake = _escapeXml(take);
    final safeCameraReel = _escapeXml(cameraReel);
    final safeClipIndex = _escapeXml(clipIndex);
    final safeShootingDay = _escapeXml(shootingDay);
    final safeUnit = _escapeXml(unit);
    final safeConventionName = _escapeXml(conventionName);
    final safeProformaName = _escapeXml(proformaName);
    final safeOriginalClipName = _escapeXml(originalClipName);
    final safeTomaSeleccionada = isSelectedTake ? 'SI' : 'NO';
    final safeCameraType = _escapeXml(cameraType);
    final safeNotes = _escapeXml(notes);
    final formattedDate = recordingDate != null ? _formatDate(recordingDate) : '';

    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<digitallogic version="4.0">\n'
        '  <clip>\n'
        '    <metadata>\n'
        '      <produccionNombre>$safeProductionName</produccionNombre>\n'
        '      <capitulo>$safeChapter</capitulo>\n'
        '      <escena>$safeScene</escena>\n'
        '      <plano>$safePlane</plano>\n'
        '      <toma>$safeTake</toma>\n'
        '      <camara>$safeCameraReel</camara>\n'
        '      <clipIndex>$safeClipIndex</clipIndex>\n'
        '      <diaGrabacion>$safeShootingDay</diaGrabacion>\n'
        '      <unidad>$safeUnit</unidad>\n'
        '      <convencionNombre>$safeConventionName</convencionNombre>\n'
        '      <proformaNombre>$safeProformaName</proformaNombre>\n'
        '      <clipName>$safeOriginalClipName</clipName>\n'
        '      <tomaSeleccionada>$safeTomaSeleccionada</tomaSeleccionada>\n'
        '      <tipoCamara>$safeCameraType</tipoCamara>\n'
        '      <descripcion>$safeNotes</descripcion>\n'
        '      <fechaGrabacion>$formattedDate</fechaGrabacion>\n'
        '    </metadata>\n'
        '  </clip>\n'
        '</digitallogic>\n';
  }

  /// Writes the [xmlContent] to a sidecar file named `{mediaFileDirectory}/{baseMediaName}.xml`.
  ///
  /// Throws a [FileSystemException] if the file exists and [overwrite] is `false`.
  static Future<File> writeXmlSidecar({
    required String mediaFilePath,
    required String xmlContent,
    bool overwrite = false,
  }) async {
    final dir = p.dirname(mediaFilePath);
    final baseName = p.basenameWithoutExtension(mediaFilePath);
    final xmlPath = p.join(dir, '$baseName.xml');
    final file = File(xmlPath);

    if (!overwrite && await file.exists()) {
      throw FileSystemException(
        'Sidecar XML file already exists and overwrite is false',
        xmlPath,
      );
    }

    return await file.writeAsString(xmlContent, encoding: utf8);
  }
}
