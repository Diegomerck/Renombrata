import 'package:flutter/material.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/services/convention_generator_service.dart';

/// A custom [TextEditingController] that styles convention lines with visual hierarchy:
/// - Fixed Header: `{PROD}_{FECHA}_` (dimmed/secondary color e.g. Color(0xFF64748B))
/// - Editable Slate Core: `{CAP}_{ESC}_{PLANO}_{TOMA}_{REEL}` (bright primary text e.g. Color(0xFFF1F5F9))
/// - Fixed Tail: `_{CLIP}_{DIA}_{UNIDAD}` (dimmed/secondary color e.g. Color(0xFF64748B))
/// - Post-Percent Metadata: `%{METADATOS}` (dimmed/secondary italicized metadata suffix)
class ConventionTextEditingController extends TextEditingController {
  RenombrataProject? project;

  ConventionTextEditingController({super.text, this.project});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dimmedColor = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
    final coreColor = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    final dimmedStyle = (style ?? const TextStyle()).copyWith(
      color: dimmedColor,
    );
    final coreStyle = (style ?? const TextStyle()).copyWith(
      color: coreColor,
    );
    final metadataStyle = dimmedStyle.copyWith(
      fontStyle: FontStyle.italic,
    );

    final rawText = value.text;
    if (rawText.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    final spans = <InlineSpan>[];
    final lines = rawText.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      _parseLineSpans(line, spans, dimmedStyle, coreStyle, metadataStyle, style);

      if (i < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: style));
      }
    }

    return TextSpan(children: spans, style: style);
  }

  void _parseLineSpans(
    String line,
    List<InlineSpan> spans,
    TextStyle dimmedStyle,
    TextStyle coreStyle,
    TextStyle metadataStyle,
    TextStyle? defaultStyle,
  ) {
    if (line.isEmpty) return;

    String mainPart = line;
    String? postPercent;
    final percentIdx = line.indexOf('%');
    if (percentIdx != -1) {
      mainPart = line.substring(0, percentIdx);
      postPercent = line.substring(percentIdx);
    }

    final segments = _segmentConventionLine(mainPart);
    if (segments != null) {
      if (segments.header.isNotEmpty) {
        spans.add(TextSpan(text: segments.header, style: dimmedStyle));
      }
      if (segments.core.isNotEmpty) {
        spans.add(TextSpan(text: segments.core, style: coreStyle));
      }
      if (segments.tail.isNotEmpty) {
        spans.add(TextSpan(text: segments.tail, style: dimmedStyle));
      }
    } else {
      if (mainPart.isNotEmpty) {
        spans.add(TextSpan(text: mainPart, style: defaultStyle));
      }
    }

    if (postPercent != null && postPercent.isNotEmpty) {
      spans.add(TextSpan(text: postPercent, style: metadataStyle));
    }
  }

  _LineSegments? _segmentConventionLine(String text) {
    if (text.isEmpty) return null;
    final tokens = text.split('_');
    if (tokens.length < 5) {
      return null;
    }

    int headerTokenCount = 0;
    final datePattern = RegExp(r'^\d{6}$');
    final hasProjectDate = project?.log.metadata.date.trim().isNotEmpty ?? false;
    final projectDate = hasProjectDate ? project!.log.metadata.date.trim() : null;
    final projectFormattedDate = projectDate != null
        ? ConventionGeneratorService.formatDateDDMMYY(projectDate)
        : null;

    bool isDateToken(String token) {
      if (datePattern.hasMatch(token)) return true;
      if (projectDate != null && token == projectDate) return true;
      if (projectFormattedDate != null && token == projectFormattedDate) return true;
      return false;
    }

    if (tokens.length >= 6 && isDateToken(tokens[1])) {
      headerTokenCount = 2;
    } else if (tokens.length >= 5 && isDateToken(tokens[0])) {
      headerTokenCount = 1;
    } else if (project != null) {
      final nom = project!.log.metadata.nomenclature.trim().toUpperCase();
      if (nom.isNotEmpty && tokens[0].toUpperCase() == nom) {
        headerTokenCount = 1;
        if (tokens.length >= 6 && isDateToken(tokens[1])) {
          headerTokenCount = 2;
        }
      }
    }

    if (headerTokenCount == 0) {
      return null;
    }

    int tailTokenCount = 0;
    final lastIdx = tokens.length - 1;
    final unitRegex = RegExp(r'^(U\w+|DS)(\.[a-zA-Z0-9]+)?$', caseSensitive: false);
    final dayRegex = RegExp(r'^D\w+$', caseSensitive: false);
    final clipRegex = RegExp(r'^\d+$');

    if (tokens.length - headerTokenCount >= 4) {
      final isUnit = unitRegex.hasMatch(tokens[lastIdx]);
      final isDay = dayRegex.hasMatch(tokens[lastIdx - 1]);
      final isClip = clipRegex.hasMatch(tokens[lastIdx - 2]);

      if (isUnit && isDay && isClip) {
        tailTokenCount = 3;
      } else if (isUnit && isDay) {
        tailTokenCount = 2;
      }
    }

    if (tailTokenCount == 0) {
      return null;
    }

    final coreTokenCount = tokens.length - headerTokenCount - tailTokenCount;
    if (coreTokenCount <= 0) {
      return null;
    }

    final headerTokens = tokens.sublist(0, headerTokenCount);
    final coreTokens =
        tokens.sublist(headerTokenCount, tokens.length - tailTokenCount);
    final tailTokens = tokens.sublist(tokens.length - tailTokenCount);

    final headerText = '${headerTokens.join('_')}_';
    final coreText = coreTokens.join('_');
    final tailText = '_${tailTokens.join('_')}';

    return _LineSegments(
      header: headerText,
      core: coreText,
      tail: tailText,
    );
  }
}

class _LineSegments {
  final String header;
  final String core;
  final String tail;

  const _LineSegments({
    required this.header,
    required this.core,
    required this.tail,
  });
}
