import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/services/rtf_bitacora_parser_service.dart';

/// Internal representation of a loaded media clip for quick-paste matching.
class MediaClipItem {
  final int index;
  final String originalFilePath;
  final String fileName;
  final String reel;
  final int? clipNumber;
  final RenameProposal? proposal;

  const MediaClipItem({
    required this.index,
    required this.originalFilePath,
    required this.fileName,
    required this.reel,
    this.clipNumber,
    this.proposal,
  });

  String get clipDisplay {
    final clipNumStr =
        clipNumber != null ? '#${clipNumber.toString().padLeft(2, '0')}' : '#--';
    return 'Reel $reel - Clip $clipNumStr';
  }
}

/// Internal representation of a parsed line from pasted convention text.
class PastedLineItem {
  final int lineNumber;
  final String rawLine;
  final String? reel;
  final int? clipNumber;
  final bool hasExtractedClip;

  const PastedLineItem({
    required this.lineNumber,
    required this.rawLine,
    this.reel,
    this.clipNumber,
    required this.hasExtractedClip,
  });
}

enum MatchStatus {
  match, // Green: "Coincide"
  missingText, // Amber: "Sin texto"
  conflict, // Red: "Conflicto"
}

class ClipMatchResult {
  final MediaClipItem clip;
  final PastedLineItem? matchedLine;
  final MatchStatus status;
  final String? conflictReason;

  const ClipMatchResult({
    required this.clip,
    this.matchedLine,
    required this.status,
    this.conflictReason,
  });
}

/// Desktop dialog allowing users to paste a list of convention names
/// directly from the clipboard and preview intelligent clip-number matching
/// and real-time conflict detection with loaded media clips.
class QuickPasteConventionDialog extends StatefulWidget {
  final List<String>? loadedClipNames;
  final List<RenameProposal>? loadedProposals;

  const QuickPasteConventionDialog({
    super.key,
    this.loadedClipNames,
    this.loadedProposals,
  }) : assert(
          loadedClipNames != null || loadedProposals != null,
          'Either loadedClipNames or loadedProposals must be provided',
        );

  static final RegExp altConventionPattern = RegExp(
    r'^([A-Za-z0-9]+)_(?:[0-9]{6}_)?([A-Za-z0-9Y]+)_([A-Za-z0-9Y]+)_(?:P([0-9]+)_)?(T[0-9]+|TF[0-9]*|TU|SEC[0-9]+|G[0-9]*)_([A-Za-z][0-9]{1,4}(?:_[0-9]+)?|GPR[0-9]*|NFF|DR[0-9]*)_([0-9]+)_([A-Za-z0-9]+)_([A-Za-z0-9]+)(?:%(.*))?$',
    caseSensitive: false,
  );

  static PastedLineItem parsePastedLine(String rawLine, int lineNumber) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) {
      return PastedLineItem(
        lineNumber: lineNumber,
        rawLine: rawLine,
        hasExtractedClip: false,
      );
    }

    String withoutExt = trimmed;
    final ext = p.extension(withoutExt);
    if (ext.isNotEmpty &&
        ext.length <= 5 &&
        RegExp(r'^\.[a-zA-Z0-9]+$').hasMatch(ext)) {
      withoutExt = p.basenameWithoutExtension(withoutExt);
    }

    // 1. Standard Televisa / ViX convention pattern
    // format: {PROD}_{CAP}_{ESC}_(?:P{PLANO}_)?{TOMA}_{REEL}_{DIA}_{CLIP#}_{UNIDAD}(?:%(SUBCONV})?
    final match1 =
        RtfBitacoraParserService.conventionPattern.firstMatch(withoutExt);
    if (match1 != null) {
      final r = match1.group(6)?.toUpperCase();
      final cStr = match1.group(8);
      final c = cStr != null ? int.tryParse(cStr) : null;
      if (c != null) {
        return PastedLineItem(
          lineNumber: lineNumber,
          rawLine: trimmed,
          reel: r,
          clipNumber: c,
          hasExtractedClip: true,
        );
      }
    }

    // 2. Alternate convention: {PROD}_{CAP}_{ESC}_{TOMA}_{CAM}_{CLIP}_{DGRAB}_{UCR}...
    final match2 = altConventionPattern.firstMatch(withoutExt);
    if (match2 != null) {
      final r = match2.group(6)?.toUpperCase();
      final cStr = match2.group(7);
      final c = cStr != null ? int.tryParse(cStr) : null;
      if (c != null) {
        return PastedLineItem(
          lineNumber: lineNumber,
          rawLine: trimmed,
          reel: r,
          clipNumber: c,
          hasExtractedClip: true,
        );
      }
    }

    // 3. Subconvention parsing after '%'
    if (withoutExt.contains('%')) {
      final sub = withoutExt.split('%').last.trim();
      final subTokens = sub.split('_');
      if (subTokens.isNotEmpty) {
        final subReelMatch = RegExp(
          r'^([A-Za-z]\d{1,4}|GPR\d*|NFF|DR\d*)$',
          caseSensitive: false,
        ).firstMatch(subTokens[0]);
        if (subReelMatch != null && subTokens.length > 1) {
          final c = int.tryParse(subTokens[1]);
          if (c != null) {
            return PastedLineItem(
              lineNumber: lineNumber,
              rawLine: trimmed,
              reel: subReelMatch.group(1)!.toUpperCase(),
              clipNumber: c,
              hasExtractedClip: true,
            );
          }
        }
      }
    }

    // 4. Token-based delimiter search for Reel and adjacent clip number
    final mainPart =
        withoutExt.contains('%') ? withoutExt.split('%').first : withoutExt;
    final tokens = mainPart.split('_');
    final reelPattern =
        RegExp(r'^([A-Za-z]\d{1,4}|GPR\d*|NFF|DR\d*)$', caseSensitive: false);
    for (int k = 0; k < tokens.length; k++) {
      final rMatch = reelPattern.firstMatch(tokens[k]);
      if (rMatch != null) {
        final foundReel = rMatch.group(1)!.toUpperCase();
        // Check next token
        if (k + 1 < tokens.length) {
          final nextNum = int.tryParse(tokens[k + 1]);
          if (nextNum != null) {
            return PastedLineItem(
              lineNumber: lineNumber,
              rawLine: trimmed,
              reel: foundReel,
              clipNumber: nextNum,
              hasExtractedClip: true,
            );
          }
        }
        // Check token at k + 2 (if day token is in between)
        if (k + 2 < tokens.length) {
          final next2Num = int.tryParse(tokens[k + 2]);
          if (next2Num != null) {
            return PastedLineItem(
              lineNumber: lineNumber,
              rawLine: trimmed,
              reel: foundReel,
              clipNumber: next2Num,
              hasExtractedClip: true,
            );
          }
        }
      }
    }

    // 5. Standard camera clip filename format (e.g. A007C001, GPR1C004)
    final reelClipMatch = RegExp(
      r'^([A-Za-z]\d{1,4}|GPR\d*|NFF|DR\d*)_?[cC](\d{1,4})',
      caseSensitive: false,
    ).firstMatch(mainPart);
    if (reelClipMatch != null) {
      final r = reelClipMatch.group(1)!.toUpperCase();
      final c = int.tryParse(reelClipMatch.group(2)!);
      if (c != null) {
        return PastedLineItem(
          lineNumber: lineNumber,
          rawLine: trimmed,
          reel: r,
          clipNumber: c,
          hasExtractedClip: true,
        );
      }
    }

    // Fallback: line does not contain standard convention clip indices
    return PastedLineItem(
      lineNumber: lineNumber,
      rawLine: trimmed,
      reel: null,
      clipNumber: null,
      hasExtractedClip: false,
    );
  }

  @override
  State<QuickPasteConventionDialog> createState() =>
      _QuickPasteConventionDialogState();
}

class _QuickPasteConventionDialogState
    extends State<QuickPasteConventionDialog> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _tableVerticalScrollController = ScrollController();
  final ScrollController _tableHorizontalScrollController = ScrollController();
  final ScrollController _unassignedScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _tableVerticalScrollController.dispose();
    _tableHorizontalScrollController.dispose();
    _unassignedScrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  static PastedLineItem parsePastedLine(String rawLine, int lineNumber) =>
      QuickPasteConventionDialog.parsePastedLine(rawLine, lineNumber);

  List<MediaClipItem> _buildLoadedClips() {
    final clips = <MediaClipItem>[];
    if (widget.loadedProposals != null && widget.loadedProposals!.isNotEmpty) {
      for (int i = 0; i < widget.loadedProposals!.length; i++) {
        final prop = widget.loadedProposals![i];
        final origPath = prop.originalFilePath ?? prop.proposedFileName;
        final fileName = p.basename(origPath);
        final reel = _extractReelFromClip(fileName, prop.fileReel);
        final clipNumber = _extractClipNumberFromClip(fileName);
        clips.add(MediaClipItem(
          index: i + 1,
          originalFilePath: origPath,
          fileName: fileName,
          reel: reel,
          clipNumber: clipNumber,
          proposal: prop,
        ));
      }
    } else if (widget.loadedClipNames != null) {
      for (int i = 0; i < widget.loadedClipNames!.length; i++) {
        final name = widget.loadedClipNames![i];
        final fileName = p.basename(name);
        final reel = _extractReelFromClip(fileName, null);
        final clipNumber = _extractClipNumberFromClip(fileName);
        clips.add(MediaClipItem(
          index: i + 1,
          originalFilePath: name,
          fileName: fileName,
          reel: reel,
          clipNumber: clipNumber,
        ));
      }
    }
    return clips;
  }

  static String _extractReelFromClip(String filename, String? propReel) {
    if (propReel != null && propReel.isNotEmpty) {
      return propReel.toUpperCase();
    }
    final r = ClipMatcherService.extractReel(filename);
    if (r != null && r.isNotEmpty) {
      return r.toUpperCase();
    }
    final match = RegExp(
      r'^([A-Za-z]\d{1,4}|GPR\d*|NFF|DR\d*)',
      caseSensitive: false,
    ).firstMatch(p.basename(filename));
    if (match != null) {
      return match.group(1)!.toUpperCase();
    }
    return 'A001';
  }

  static int? _extractClipNumberFromClip(String filename) {
    final clean = p.basenameWithoutExtension(filename);
    final numStr = ClipMatcherService.extractClipNumber(clean);
    if (numStr.isNotEmpty) {
      return int.tryParse(numStr);
    }
    return null;
  }

  Map<String, String> _buildResultMap(List<ClipMatchResult> matches) {
    final map = <String, String>{};
    for (final m in matches) {
      if (m.status == MatchStatus.match && m.matchedLine != null) {
        final lineText = m.matchedLine!.rawLine;
        map[m.clip.originalFilePath] = lineText;
        map[m.clip.fileName] = lineText;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final loadedClips = _buildLoadedClips();
    final clipCount = loadedClips.length;

    // Parse raw input lines
    final rawLines = _textController.text.split(RegExp(r'\r?\n'));
    final parsedLines = <PastedLineItem>[];
    int lineCounter = 1;
    for (final r in rawLines) {
      final trimmed = r.trim();
      if (trimmed.isNotEmpty) {
        parsedLines.add(parsePastedLine(trimmed, lineCounter));
        lineCounter++;
      }
    }
    final pastedCount = parsedLines.length;

    // Check for duplicate clip numbers in pasted lines
    final pastedByKey = <String, List<PastedLineItem>>{};
    for (final line in parsedLines) {
      if (line.hasExtractedClip && line.clipNumber != null) {
        final reelKey = line.reel?.toUpperCase() ?? 'ALL';
        final key = '${reelKey}_${line.clipNumber}';
        pastedByKey.putIfAbsent(key, () => []).add(line);
      }
    }

    final duplicatePastedKeys = <String>{};
    String? pastedConflictBanner;
    for (final entry in pastedByKey.entries) {
      if (entry.value.length > 1) {
        duplicatePastedKeys.add(entry.key);
        if (pastedConflictBanner == null) {
          final firstConflict = entry.value.first;
          final linesStr = entry.value.map((l) => l.lineNumber).join(', ');
          final clipStr = firstConflict.clipNumber!.toString().padLeft(2, '0');
          pastedConflictBanner =
              'Conflicto: Clip #$clipStr duplicado en las líneas $linesStr';
        }
      }
    }

    // Check for duplicate files on disk for the same (Reel, ClipNumber)
    final diskClipsByKey = <String, List<MediaClipItem>>{};
    for (final clip in loadedClips) {
      if (clip.clipNumber != null) {
        final key = '${clip.reel.toUpperCase()}_${clip.clipNumber}';
        diskClipsByKey.putIfAbsent(key, () => []).add(clip);
      }
    }

    final duplicateDiskKeys = <String>{};
    String? diskConflictBanner;
    for (final entry in diskClipsByKey.entries) {
      if (entry.value.length > 1) {
        duplicateDiskKeys.add(entry.key);
        if (diskConflictBanner == null) {
          final firstClip = entry.value.first;
          final clipStr = firstClip.clipNumber!.toString().padLeft(2, '0');
          diskConflictBanner =
              'Conflicto en disco: Múltiples archivos para Reel ${firstClip.reel} - Clip #$clipStr';
        }
      }
    }

    final bool hasConflict =
        duplicatePastedKeys.isNotEmpty || duplicateDiskKeys.isNotEmpty;
    final String? conflictMessage = pastedConflictBanner ?? diskConflictBanner;

    // Match loaded clips against pasted lines
    final hasAnyExtractedClip = parsedLines.any((l) => l.hasExtractedClip);
    final clipMatches = <ClipMatchResult>[];
    final matchedLineIndices = <int>{};

    if (!hasAnyExtractedClip) {
      // Sequential fallback when clip numbers cannot be extracted
      for (int i = 0; i < loadedClips.length; i++) {
        final clip = loadedClips[i];
        final diskKey = clip.clipNumber != null
            ? '${clip.reel.toUpperCase()}_${clip.clipNumber}'
            : null;
        final hasDiskConflict =
            diskKey != null && duplicateDiskKeys.contains(diskKey);

        if (hasDiskConflict) {
          clipMatches.add(ClipMatchResult(
            clip: clip,
            matchedLine: null,
            status: MatchStatus.conflict,
            conflictReason: 'Múltiples archivos en disco para este clip',
          ));
        } else if (i < parsedLines.length) {
          final line = parsedLines[i];
          matchedLineIndices.add(i);
          clipMatches.add(ClipMatchResult(
            clip: clip,
            matchedLine: line,
            status: MatchStatus.match,
          ));
        } else {
          clipMatches.add(ClipMatchResult(
            clip: clip,
            matchedLine: null,
            status: MatchStatus.missingText,
          ));
        }
      }
    } else {
      // Intelligent matching by (Reel, ClipNumber)
      for (final clip in loadedClips) {
        final diskKey = clip.clipNumber != null
            ? '${clip.reel.toUpperCase()}_${clip.clipNumber}'
            : null;
        final hasDiskConflict =
            diskKey != null && duplicateDiskKeys.contains(diskKey);

        if (hasDiskConflict) {
          clipMatches.add(ClipMatchResult(
            clip: clip,
            matchedLine: null,
            status: MatchStatus.conflict,
            conflictReason: 'Múltiples archivos en disco para este clip',
          ));
          continue;
        }

        if (clip.clipNumber == null) {
          clipMatches.add(ClipMatchResult(
            clip: clip,
            matchedLine: null,
            status: MatchStatus.missingText,
          ));
          continue;
        }

        final candidateIndices = <int>[];
        for (int i = 0; i < parsedLines.length; i++) {
          final line = parsedLines[i];
          if (!line.hasExtractedClip || line.clipNumber != clip.clipNumber) {
            continue;
          }

          if (line.reel != null) {
            if (line.reel!.toUpperCase() == clip.reel.toUpperCase()) {
              candidateIndices.add(i);
            }
          } else {
            candidateIndices.add(i);
          }
        }

        if (candidateIndices.isEmpty) {
          clipMatches.add(ClipMatchResult(
            clip: clip,
            matchedLine: null,
            status: MatchStatus.missingText,
          ));
        } else if (candidateIndices.length > 1) {
          clipMatches.add(ClipMatchResult(
            clip: clip,
            matchedLine: parsedLines[candidateIndices.first],
            status: MatchStatus.conflict,
            conflictReason: 'Múltiples líneas de texto coinciden con este clip',
          ));
        } else {
          final lineIdx = candidateIndices.first;
          final matchedLine = parsedLines[lineIdx];
          matchedLineIndices.add(lineIdx);

          final lineKey =
              '${matchedLine.reel?.toUpperCase() ?? 'ALL'}_${matchedLine.clipNumber}';
          final hasPastedDuplicate = duplicatePastedKeys.contains(lineKey);

          clipMatches.add(ClipMatchResult(
            clip: clip,
            matchedLine: matchedLine,
            status:
                hasPastedDuplicate ? MatchStatus.conflict : MatchStatus.match,
            conflictReason:
                hasPastedDuplicate ? 'Clip duplicado en el texto pegado' : null,
          ));
        }
      }
    }

    // Collect unassigned pasted lines
    final unassignedLines = <PastedLineItem>[];
    for (int i = 0; i < parsedLines.length; i++) {
      if (!matchedLineIndices.contains(i)) {
        unassignedLines.add(parsedLines[i]);
      }
    }

    final diff = pastedCount - clipCount;
    final allMatched = clipMatches.isNotEmpty &&
        clipMatches.every((m) => m.status == MatchStatus.match) &&
        unassignedLines.isEmpty;
    final hasExactMatch = allMatched && diff == 0 && !hasConflict;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 900,
          maxHeight: 700,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.paste_rounded,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Pegar Nombres de Convención',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Pega los nombres de convención desde TextEdit, Notas o chat (uno por línea). '
                'Se emparejarán automáticamente por Reel y Número de Clip con detección de conflictos en tiempo real.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 14),

              // Multi-line Input
              TextField(
                controller: _textController,
                minLines: 3,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Ejemplo:\nLUZDMIN_15_41_T1_NFF_1_D24_F11\nLUZDMIN_16_12_T1_NFF_2_D24_F11',
                  hintStyle: TextStyle(
                    fontFamily: 'monospace',
                    color: theme.hintColor.withValues(alpha: 0.6),
                  ),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 12),

              // Status Bar / Comparison Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: conflictMessage != null
                      ? Colors.red.withValues(alpha: 0.08)
                      : (isDark
                          ? const Color(0xFF1E1E24)
                          : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: conflictMessage != null
                        ? Colors.red.shade700
                        : (isDark
                            ? const Color(0xFF2E2E38)
                            : const Color(0xFFCBD5E1)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Líneas detectadas: $pastedCount | Clips cargados: $clipCount',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                        ),
                        if (hasExactMatch)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.green),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle,
                                    size: 14, color: Colors.green),
                                SizedBox(width: 6),
                                Text(
                                  'Coincidencia exacta',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (pastedCount > 0 || clipCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.amber.shade700),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    size: 14, color: Colors.amber.shade800),
                                const SizedBox(width: 6),
                                Text(
                                  'Diferencia de líneas (${diff > 0 ? '+$diff' : '$diff'})',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.amber.shade300
                                        : Colors.amber.shade900,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (conflictMessage != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade700),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                size: 16, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                conflictMessage,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.red.shade300
                                      : Colors.red.shade900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Preview Table Title
              Text(
                'Vista Previa de Asignación por Clip',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),

              // Preview Table
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF2E2E38)
                          : const Color(0xFFCBD5E1),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: clipMatches.isEmpty
                      ? Center(
                          child: Text(
                            'Pega nombres de convención para visualizar la comparación con los clips.',
                            style: TextStyle(
                              color: theme.hintColor,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : Scrollbar(
                          controller: _tableVerticalScrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _tableVerticalScrollController,
                            primary: false,
                            scrollDirection: Axis.vertical,
                            child: Scrollbar(
                              controller: _tableHorizontalScrollController,
                              thumbVisibility: true,
                              notificationPredicate: (notif) =>
                                  notif.metrics.axis == Axis.horizontal,
                              child: SingleChildScrollView(
                                controller: _tableHorizontalScrollController,
                                primary: false,
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowHeight: 36,
                                  dataRowMinHeight: 32,
                                  dataRowMaxHeight: 36,
                                  horizontalMargin: 12,
                                  columnSpacing: 16,
                                  headingTextStyle: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color:
                                        isDark ? Colors.white : Colors.black87,
                                  ),
                                  columns: const [
                                    DataColumn(label: Text('#')),
                                    DataColumn(label: Text('Archivo de Medio')),
                                    DataColumn(label: Text('Clip Detectado')),
                                    DataColumn(
                                        label:
                                            Text('Nombre Pegado Coincidente')),
                                    DataColumn(label: Text('Estado')),
                                  ],
                                  rows:
                                      List.generate(clipMatches.length, (index) {
                                    final match = clipMatches[index];
                                    final clip = match.clip;
                                    final matched = match.matchedLine;

                                    final bool isConflict =
                                        match.status == MatchStatus.conflict;
                                    final bool isMissing =
                                        match.status == MatchStatus.missingText;

                                    Color? rowColor;
                                    if (isConflict) {
                                      rowColor =
                                          Colors.red.withValues(alpha: 0.08);
                                    } else if (isMissing) {
                                      rowColor =
                                          Colors.amber.withValues(alpha: 0.08);
                                    }

                                    final String estadoText;
                                    final Color estadoColor;
                                    final IconData estadoIcon;
                                    if (isConflict) {
                                      estadoText = 'Conflicto';
                                      estadoColor = Colors.red.shade700;
                                      estadoIcon = Icons.error_outline;
                                    } else if (isMissing) {
                                      estadoText = 'Sin texto';
                                      estadoColor = Colors.amber.shade800;
                                      estadoIcon = Icons.warning_amber_rounded;
                                    } else {
                                      estadoText = 'Coincide';
                                      estadoColor = Colors.green;
                                      estadoIcon = Icons.check_circle_outline;
                                    }

                                    final String pastedCellText = matched != null
                                        ? matched.rawLine
                                        : '— Sin coincidencia en texto —';

                                    return DataRow(
                                      color: WidgetStatePropertyAll(rowColor),
                                      cells: [
                                        DataCell(
                                          Text(
                                            '${clip.index}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            clip.fileName,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            clip.clipDisplay,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            pastedCellText,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                              fontWeight: matched != null
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              fontStyle: matched != null
                                                  ? FontStyle.normal
                                                  : FontStyle.italic,
                                              color: matched != null
                                                  ? (isConflict
                                                      ? Colors.red
                                                      : theme
                                                          .colorScheme.primary)
                                                  : (isDark
                                                      ? Colors.amber.shade300
                                                      : Colors.amber.shade900),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: estadoColor.withValues(
                                                  alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: estadoColor),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(estadoIcon,
                                                    size: 12,
                                                    color: estadoColor),
                                                const SizedBox(width: 4),
                                                Text(
                                                  estadoText,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: estadoColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),

              // Unassigned Pasted Lines Section
              if (unassignedLines.isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 110),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade700),
                    ),
                    child: Scrollbar(
                      controller: _unassignedScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _unassignedScrollController,
                        primary: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 15, color: Colors.amber.shade800),
                                const SizedBox(width: 6),
                                Text(
                                  'Entradas no asignadas (${unassignedLines.length}):',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.amber.shade300
                                        : Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ...unassignedLines.map((line) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    line.clipNumber != null
                                        ? '• Línea ${line.lineNumber} (Clip ${line.clipNumber.toString().padLeft(2, '0')}) no tiene archivo correspondiente en disco: ${line.rawLine}'
                                        : '• Línea ${line.lineNumber} no tiene archivo correspondiente en disco: ${line.rawLine}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: isDark
                                          ? Colors.amber.shade200
                                          : Colors.amber.shade900,
                                    ),
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: (parsedLines.isEmpty || hasConflict)
                        ? null
                        : () {
                            final resultMap = _buildResultMap(clipMatches);
                            Navigator.of(context).pop(resultMap);
                          },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Aplicar a Renombrador'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
