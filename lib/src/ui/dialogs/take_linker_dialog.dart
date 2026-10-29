import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/shooting_log.dart';

enum TakeLinkerAction { link, unlink }

class TakeLinkerResult {
  final TakeLinkerAction action;
  final ShotRecord? record;

  const TakeLinkerResult.link(this.record) : action = TakeLinkerAction.link;
  const TakeLinkerResult.unlink()
      : action = TakeLinkerAction.unlink,
        record = null;
}

/// Interactive searchable dialog for linking or unlinking clips to bitácora takes.
class TakeLinkerDialog extends StatefulWidget {
  final RenameProposal clip;
  final List<ShotRecord> records;
  final String activeCamera;
  final ShotRecord? currentlyLinkedRecord;

  const TakeLinkerDialog({
    super.key,
    required this.clip,
    required this.records,
    required this.activeCamera,
    this.currentlyLinkedRecord,
  });

  static Future<TakeLinkerResult?> show(
    BuildContext context, {
    required RenameProposal clip,
    required List<ShotRecord> records,
    required String activeCamera,
    ShotRecord? currentlyLinkedRecord,
  }) {
    return showDialog<TakeLinkerResult>(
      context: context,
      builder: (context) => TakeLinkerDialog(
        clip: clip,
        records: records,
        activeCamera: activeCamera,
        currentlyLinkedRecord: currentlyLinkedRecord,
      ),
    );
  }

  @override
  State<TakeLinkerDialog> createState() => _TakeLinkerDialogState();
}

class _TakeLinkerDialogState extends State<TakeLinkerDialog> {
  final TextEditingController _searchController = TextEditingController();
  ShotRecord? _selectedRecord;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedRecord = widget.currentlyLinkedRecord;
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isTimecodeMatch(ShotRecord record) {
    final clipIn = widget.clip.fileTcIn?.trim();
    final clipOut = widget.clip.fileTcOut?.trim();
    if (clipIn == null && clipOut == null) return false;

    final recIn = record.tcIn?.trim();
    final recOut = record.tcOut?.trim();
    if (recIn == null && recOut == null) return false;

    if (clipIn != null && recIn != null && clipIn == recIn) return true;
    if (clipOut != null && recOut != null && clipOut == recOut) return true;

    // Check prefix overlap (e.g. HH:MM)
    if (clipIn != null && recIn != null && clipIn.length >= 5 && recIn.length >= 5) {
      if (clipIn.substring(0, 5) == recIn.substring(0, 5)) return true;
    }
    return false;
  }

  List<ShotRecord> _filterRecords() {
    return widget.records.where((rec) {
      if (_searchQuery.isEmpty) return true;
      final scene = rec.scene.toLowerCase();
      final take = rec.take.toLowerCase();
      final chapter = rec.chapter.toLowerCase();
      final reel = rec.reel.toLowerCase();
      final notes = (rec.observations ?? '').toLowerCase();

      return scene.contains(_searchQuery) ||
          take.contains(_searchQuery) ||
          chapter.contains(_searchQuery) ||
          reel.contains(_searchQuery) ||
          notes.contains(_searchQuery) ||
          'esc. $scene'.contains(_searchQuery) ||
          'toma $take'.contains(_searchQuery) ||
          't$take'.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final fileName = widget.clip.originalFilePath != null
        ? p.basename(widget.clip.originalFilePath!)
        : widget.clip.proposedFileName;
    final fileTc = (widget.clip.fileTcIn != null || widget.clip.fileTcOut != null)
        ? '${widget.clip.fileTcIn ?? '—'} ➔ ${widget.clip.fileTcOut ?? '—'}'
        : null;

    final filtered = _filterRecords();
    final timecodeSuggestions = filtered.where(_isTimecodeMatch).toList();
    final regularRecords = filtered.where((r) => !_isTimecodeMatch(r)).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 12 / 100),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.link_rounded,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Vincular Toma a Clip',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Clip: $fileName${fileTc != null ? '  ·  TC: $fileTc' : ''}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.hintColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Search Bar
              TextField(
                key: const ValueKey('take_linker_search_field'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar por escena, toma, plano, capítulo o notas...',
                  hintStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),

              // Takes List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No se encontraron tomas coincidentes',
                          style: TextStyle(
                            color: theme.hintColor,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView(
                        children: [
                          if (timecodeSuggestions.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(
                                  alpha: isDark ? 18 / 100 : 12 / 100,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.amber.withValues(alpha: 40 / 100),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.access_time_filled,
                                    size: 15,
                                    color: Colors.amber,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Sugerencias por Código de Tiempo',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...timecodeSuggestions.map(
                              (r) => _buildTakeCard(r, theme, isDark, isSuggested: true),
                            ),
                            const Divider(height: 18),
                          ],
                          if (regularRecords.isNotEmpty) ...[
                            ...regularRecords.map(
                              (r) => _buildTakeCard(r, theme, isDark),
                            ),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 14),

              // Footer Actions
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                spacing: 8,
                children: [
                  if (widget.currentlyLinkedRecord != null)
                    OutlinedButton.icon(
                      key: const ValueKey('take_linker_unlink_button'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      icon: const Icon(Icons.link_off, size: 16),
                      label: const Text('Desvincular Toma'),
                      onPressed: () {
                        Navigator.of(context).pop(const TakeLinkerResult.unlink());
                      },
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        key: const ValueKey('take_linker_cancel_button'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const ValueKey('take_linker_confirm_button'),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Vincular'),
                        onPressed: _selectedRecord != null
                            ? () {
                                Navigator.of(
                                  context,
                                ).pop(TakeLinkerResult.link(_selectedRecord!));
                              }
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTakeCard(
    ShotRecord rec,
    ThemeData theme,
    bool isDark, {
    bool isSuggested = false,
  }) {
    final isSelected = _selectedRecord?.id == rec.id;
    final isCurrentlyLinked = widget.currentlyLinkedRecord?.id == rec.id;

    final takeStr = rec.take.toUpperCase().startsWith('T')
        ? rec.take
        : 'T${rec.take}';
    final capText = rec.chapter.isNotEmpty ? ' (Cap. ${rec.chapter})' : '';
    final title = 'Esc. ${rec.scene} - $takeStr$capText';

    final tcRange = (rec.tcIn != null || rec.tcOut != null)
        ? '${rec.tcIn ?? '—'} - ${rec.tcOut ?? '—'}'
        : null;

    final otherCams = rec.cameras.where((c) => c.clipName.trim().isNotEmpty).toList();

    return InkWell(
      key: ValueKey('take_item_${rec.id}'),
      onTap: () {
        setState(() {
          _selectedRecord = rec;
        });
      },
      onDoubleTap: () {
        Navigator.of(context).pop(TakeLinkerResult.link(rec));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: isDark ? 25 / 100 : 15 / 100)
              : (isSuggested
                  ? Colors.amber.withValues(alpha: isDark ? 8 / 100 : 5 / 100)
                  : (isDark
                      ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 30 / 100)
                      : Colors.grey.shade50)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : (isCurrentlyLinked
                    ? Colors.green.withValues(alpha: 60 / 100)
                    : theme.dividerColor.withValues(alpha: 20 / 100)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: isSelected ? theme.colorScheme.primary : theme.hintColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? theme.colorScheme.primary : null,
                        ),
                      ),
                      if (rec.plane != null && rec.plane!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Plano: ${rec.plane}',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.hintColor,
                            ),
                          ),
                        ),
                      if (rec.reel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Reel: ${rec.reel}',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.hintColor,
                            ),
                          ),
                        ),
                      if (isCurrentlyLinked)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 20 / 100),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Actual',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (tcRange != null) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined, size: 12, color: theme.hintColor),
                            const SizedBox(width: 4),
                            Text(
                              'TC: $tcRange',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (otherCams.isNotEmpty)
                        Text(
                          otherCams
                              .map((c) => 'Cam ${c.cameraName}: ${c.clipName}')
                              .join(' · '),
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  if (rec.observations != null && rec.observations!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Notas: ${rec.observations}',
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: theme.hintColor.withValues(alpha: 80 / 100),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
