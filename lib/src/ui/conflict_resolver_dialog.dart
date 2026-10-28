import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';

class _ConflictGroup {
  final String key;
  final ShotRecord? targetRecord;
  final String expectedClip;
  final List<RenameProposal> candidates;

  _ConflictGroup({
    required this.key,
    required this.targetRecord,
    required this.expectedClip,
    required this.candidates,
  });
}

class ConflictResolverDialog extends StatefulWidget {
  final DryRunReport report;
  final ShootingLog log;
  final Map<String, String?> currentOverrides;

  const ConflictResolverDialog({
    super.key,
    required this.report,
    required this.log,
    this.currentOverrides = const {},
  });

  @override
  State<ConflictResolverDialog> createState() => _ConflictResolverDialogState();
}

class _ConflictResolverDialogState extends State<ConflictResolverDialog> {
  late final List<_ConflictGroup> _groups;
  late final List<ShotRecord> _missingTakes;
  late final Map<String, String?> _overrides;

  @override
  void initState() {
    super.initState();
    _overrides = Map<String, String?>.from(widget.currentOverrides);

    // Identify missing takes in the shooting log that currently lack a file on disk
    final seenIds = <String>{};
    _missingTakes = widget.report.proposals
        .where((p) => p.status == ProposalStatus.missingFile && p.associatedRecord != null && !p.isCompanionFile)
        .map((p) => p.associatedRecord!)
        .where((r) => seenIds.add(r.id))
        .toList();

    String getProposalReel(RenameProposal pItem) {
      final r = pItem.fileReel ?? pItem.associatedRecord?.reel;
      if (r != null && r.trim().isNotEmpty) return r.trim().toUpperCase();
      if (pItem.originalFilePath != null) {
        final extracted = ClipMatcherService.extractReel(pItem.originalFilePath!);
        if (extracted != null && extracted.isNotEmpty) return extracted.toUpperCase();
      }
      return '';
    }

    String getProposalClipNum(RenameProposal pItem) {
      if (pItem.originalFilePath != null) {
        final cn = ClipMatcherService.extractClipNumber(p.basename(pItem.originalFilePath!));
        if (cn.isNotEmpty) return cn;
      }
      if (pItem.associatedRecord != null) {
        for (var cam in pItem.associatedRecord!.cameras) {
          final cn = ClipMatcherService.extractClipNumber(cam.clipName);
          if (cn.isNotEmpty) return cn;
        }
      }
      return '';
    }

    // Identify proposals sharing the same reel and clip index
    final byReelAndClip = <String, List<RenameProposal>>{};
    for (var pItem in widget.report.proposals) {
      if (pItem.isCompanionFile || pItem.originalFilePath == null) continue;
      final reel = getProposalReel(pItem);
      final clipNum = getProposalClipNum(pItem);
      if (clipNum.isNotEmpty) {
        final key = '${reel}_$clipNum';
        byReelAndClip.putIfAbsent(key, () => []).add(pItem);
      }
    }

    // Group all proposals that are in conflict, currently overridden, or share (reel, clipNum)
    final seenConflictPaths = <String>{};
    final conflictProposals = <RenameProposal>[];
    for (var pItem in widget.report.proposals) {
      if (pItem.isCompanionFile || pItem.originalFilePath == null) continue;
      final reel = getProposalReel(pItem);
      final clipNum = getProposalClipNum(pItem);
      final key = '${reel}_$clipNum';
      final isDuplicateOnDisk = (byReelAndClip[key]?.length ?? 0) > 1;

      if (pItem.status == ProposalStatus.conflict ||
          widget.currentOverrides.containsKey(pItem.originalFilePath) ||
          isDuplicateOnDisk) {
        if (seenConflictPaths.add(pItem.originalFilePath!)) {
          conflictProposals.add(pItem);
        }
      }
    }

    final Map<String, List<RenameProposal>> grouped = {};
    for (var pItem in conflictProposals) {
      final overrideVal = widget.currentOverrides[pItem.originalFilePath];
      final reel = getProposalReel(pItem);
      final clipNum = getProposalClipNum(pItem);
      final key = '${reel}_$clipNum';

      String groupKey;
      if ((byReelAndClip[key]?.length ?? 0) > 1) {
        groupKey = key;
      } else {
        groupKey = pItem.associatedRecord?.id ?? overrideVal ?? key;
      }
      grouped.putIfAbsent(groupKey, () => []).add(pItem);
    }

    _groups = grouped.entries.map((entry) {
      final candidates = entry.value;
      var targetRecord = candidates.where((c) => c.associatedRecord != null).map((c) => c.associatedRecord!).firstOrNull;
      if (targetRecord == null && widget.log.records.isNotEmpty) {
        for (var c in candidates) {
          final recId = widget.currentOverrides[c.originalFilePath];
          if (recId != null) {
            targetRecord = widget.log.records.where((r) => r.id == recId).firstOrNull;
            if (targetRecord != null) break;
          }
        }
        if (targetRecord == null) {
          final clipNum = getProposalClipNum(candidates.first);
          final reel = getProposalReel(candidates.first);
          targetRecord = widget.log.records.where((r) {
            final rReel = r.reel.trim().toUpperCase();
            final matchesReel = reel.isEmpty || rReel.isEmpty || rReel == reel;
            final matchesClip = r.cameras.any((cam) =>
                ClipMatcherService.extractClipNumber(cam.clipName) == clipNum ||
                cam.clipName == clipNum);
            return matchesReel && matchesClip;
          }).firstOrNull;
        }
      }

      String expectedClip = '';
      if (targetRecord != null) {
        for (var cam in targetRecord.cameras) {
          if (cam.clipName.isNotEmpty) {
            expectedClip = cam.clipName;
            break;
          }
        }
      }
      if (expectedClip.isEmpty && candidates.first.originalFilePath != null) {
        expectedClip = getProposalClipNum(candidates.first);
      }

      return _ConflictGroup(
        key: entry.key,
        targetRecord: targetRecord,
        expectedClip: expectedClip,
        candidates: candidates,
      );
    }).toList();

    // Set intelligent default resolutions if not already resolved:
    // First candidate becomes the winner for target take, secondary candidates are marked as alternate or omit
    for (var group in _groups) {
      final hasAnyOverride = group.candidates.any((c) => _overrides.containsKey(c.originalFilePath));
      if (!hasAnyOverride && group.candidates.isNotEmpty) {
        final hasTcConflict = group.candidates.any((c) {
          final temp = c.copyWith(associatedRecord: group.targetRecord);
          return temp.hasTimecodeDiscrepancy;
        });

        if (!hasTcConflict && group.candidates.length > 1) {
          if (group.targetRecord != null) {
            _overrides[group.candidates.first.originalFilePath!] = group.targetRecord!.id;
            for (int i = 1; i < group.candidates.length; i++) {
              _overrides[group.candidates[i].originalFilePath!] = '__ALT__:${group.targetRecord!.id}';
            }
          } else {
            _overrides[group.candidates.first.originalFilePath!] = '__PRIMARY__';
            for (int i = 1; i < group.candidates.length; i++) {
              _overrides[group.candidates[i].originalFilePath!] = '__ALT__';
            }
          }
        }
      }
    }
  }

  void _resetConflicts() {
    setState(() {
      for (var group in _groups) {
        for (var c in group.candidates) {
          final path = c.originalFilePath;
          if (path != null) {
            _overrides.remove(path);
          }
        }
      }
    });
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  String _getFileMetadata(String? filePath) {
    if (filePath == null) return 'Archivo no encontrado';
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        final length = file.lengthSync();
        final modified = file.lastModifiedSync();
        final sizeStr = _formatBytes(length);
        final dateStr = '${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')} ${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}';
        return '$sizeStr · $dateStr';
      }
    } catch (_) {}
    return 'Archivo en disco';
  }

  void _setWinner(_ConflictGroup group, String winnerPath) {
    setState(() {
      final target = group.targetRecord;
      if (target != null) {
        _overrides[winnerPath] = target.id;
        for (var c in group.candidates) {
          final path = c.originalFilePath;
          if (path != null && path != winnerPath) {
            _overrides[path] = '__ALT__:${target.id}';
          }
        }
      } else {
        _overrides[winnerPath] = '__PRIMARY__';
        for (var c in group.candidates) {
          final path = c.originalFilePath;
          if (path != null && path != winnerPath) {
            _overrides[path] = '__ALT__';
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(isDark),
              const SizedBox(height: 16),
              Expanded(
                child: _groups.isEmpty
                    ? const Center(
                        child: Text('No hay conflictos pendientes por resolver.',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      )
                    : ListView.separated(
                        itemCount: _groups.length,
                        separatorBuilder: (_, index) => const SizedBox(height: 16),
                        itemBuilder: (context, index) => _buildGroupCard(_groups[index], isDark),
                      ),
              ),
              const SizedBox(height: 16),
              _buildFooter(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 4,
                children: [
                  const Text(
                    'Resolución de Conflictos de Medios',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_groups.length} ${_groups.length == 1 ? 'conflicto' : 'conflictos'}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Se detectaron clips compitiendo por la misma toma de bitácora. Selecciona el archivo ganador para cada toma o reasigna los duplicados a tomas faltantes.',
                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ],
    );
  }

  Widget _buildGroupCard(_ConflictGroup group, bool isDark) {
    final record = group.targetRecord;
    final headerBg = isDark ? const Color(0xFF282834) : const Color(0xFFE2E7F0);
    final cardBorder = isDark ? const Color(0xFF383846) : const Color(0xFFCBD2DC);
    final bodyBg = isDark ? const Color(0xFF1E1E26) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bodyBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Group Header (Target Take)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                const Icon(Icons.movie_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    record != null
                        ? 'Toma Objetivo: Escena ${record.scene}  ·  Toma ${record.take}  ·  Reel ${record.reel}'
                        : 'Conflicto por Clip "${group.expectedClip}"',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Clip Esperado: "${group.expectedClip}"',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Candidates List
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: group.candidates.map((candidate) {
                final path = candidate.originalFilePath!;
                final filename = p.basename(path);
                final fileMeta = _getFileMetadata(path);

                final reelStr = 'Reel: ${candidate.fileReel ?? '—'}';
                String tcInfo = '';
                if (candidate.fileTcIn != null) {
                  if (candidate.fileTcOut != null) {
                    tcInfo = 'TC: ${candidate.fileTcIn} → ${candidate.fileTcOut}';
                  } else {
                    tcInfo = 'TC: ${candidate.fileTcIn}';
                  }
                }
                final metadata = '$reelStr  ·  ${tcInfo.isNotEmpty ? '$tcInfo  ·  ' : ''}$fileMeta';

                final tempProposal = candidate.copyWith(associatedRecord: record);
                final hasTcDiscrepancy = tempProposal.hasTimecodeDiscrepancy;
                final hasReelDiscrepancy = tempProposal.hasReelDiscrepancy;

                final isAssigned = _overrides.containsKey(path);
                final currentAssignment = _overrides[path];
                final isWinner = isAssigned && ((record != null && currentAssignment == record.id) || currentAssignment == '__PRIMARY__');
                final isAlternate = isAssigned && (currentAssignment == '__ALT__' || (currentAssignment != null && currentAssignment.startsWith('__ALT__:')));
                final isUnassigned = !isAssigned;

                Color cardBg;
                Color borderColor;
                if (isWinner) {
                  cardBg = isDark ? Colors.green.shade900.withValues(alpha: 0.25) : Colors.green.shade50;
                  borderColor = isDark ? Colors.green.shade700 : Colors.green.shade400;
                } else if (isAlternate) {
                  cardBg = isDark ? Colors.blue.shade900.withValues(alpha: 0.2) : Colors.blue.shade50;
                  borderColor = isDark ? Colors.blue.shade700 : Colors.blue.shade300;
                } else if (isUnassigned) {
                  cardBg = isDark ? Colors.orange.shade900.withValues(alpha: 0.2) : Colors.orange.shade50.withValues(alpha: 0.4);
                  borderColor = isDark ? Colors.orange.shade900 : Colors.orange.shade300;
                } else {
                  cardBg = isDark ? const Color(0xFF16161D) : const Color(0xFFF7F8FA);
                  borderColor = isDark ? const Color(0xFF2C2C38) : const Color(0xFFE2E7F0);
                }

                IconData statusIcon = Icons.video_file;
                Color iconColor = Theme.of(context).hintColor;
                if (isWinner) {
                  statusIcon = Icons.check_circle;
                  iconColor = Colors.green;
                } else if (isAlternate) {
                  statusIcon = Icons.alt_route_rounded;
                  iconColor = Colors.blue;
                } else if (isUnassigned) {
                  statusIcon = Icons.warning_amber_rounded;
                  iconColor = Colors.orange.shade800;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: borderColor,
                      width: isWinner ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Radio<String>(
                        value: path,
                        groupValue: group.candidates
                            .firstWhere(
                              (c) {
                                final a = _overrides[c.originalFilePath];
                                return _overrides.containsKey(c.originalFilePath) &&
                                    ((record != null && a == record.id) || a == '__PRIMARY__');
                              },
                              orElse: () => RenameProposal(proposedFileName: '', status: ProposalStatus.conflict),
                            )
                            .originalFilePath,
                        toggleable: true,
                        onChanged: (val) {
                          if (val != null) {
                            _setWinner(group, val);
                          } else {
                            setState(() {
                              _overrides.remove(path);
                            });
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        statusIcon,
                        color: iconColor,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    filename,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isWinner && !isDark ? Colors.green.shade900 : null,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isWinner)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: isDark ? 0.25 : 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.green.shade600, width: 1),
                                    ),
                                    child: const Text('Ganador / Principal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                                  ),
                                if (isAlternate)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: isDark ? 0.25 : 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.blue.shade600, width: 1),
                                    ),
                                    child: const Text('Alterno (_ALT)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              metadata,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).hintColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (hasReelDiscrepancy) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: isDark ? 0.2 : 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.amber.shade700,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  '⚠ Reel Discrepante: Bitácora (${record?.reel ?? "—"}) vs Archivo (${candidate.fileReel ?? "—"})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                            if (hasTcDiscrepancy) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: isDark ? 0.2 : 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.amber.shade700,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  '⚠ TC Discrepante: Bitácora (${record?.tcIn ?? "—"}) vs Archivo (${candidate.fileTcIn ?? "—"})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildActionDropdown(group, path, currentAssignment, isWinner),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionDropdown(
    _ConflictGroup group,
    String path,
    String? currentAssignment,
    bool isWinner,
  ) {
    final targetRecord = group.targetRecord;
    final isAssigned = _overrides.containsKey(path);
    final dropdownValue = isAssigned ? (currentAssignment ?? '__OMIT__') : '__UNASSIGNED__';

    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: '__UNASSIGNED__',
        child: Text(
          '⚠ Conflicto (Sin resolver)',
          style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (targetRecord != null) ...[
        DropdownMenuItem(
          value: targetRecord.id,
          child: Text(
            group.candidates.length == 1
                ? '✓ Confirmar (Esc. ${targetRecord.scene} - T${targetRecord.take})'
                : '✓ Ganador (Esc. ${targetRecord.scene} - T${targetRecord.take})',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DropdownMenuItem(
          value: '__ALT__:${targetRecord.id}',
          child: Text(
            '↳ Alterno (_ALT) (Esc. ${targetRecord.scene} - T${targetRecord.take})',
            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ] else ...[
        const DropdownMenuItem(
          value: '__PRIMARY__',
          child: Text(
            '✓ Toma Principal',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const DropdownMenuItem(
          value: '__ALT__',
          child: Text(
            '↳ Alterno (_ALT)',
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      const DropdownMenuItem(
        value: '__OMIT__',
        child: Text(
          '⊘ Omitir (No renombrar)',
          style: TextStyle(color: Colors.orange),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      for (var missing in _missingTakes)
        if (missing.id != targetRecord?.id)
          DropdownMenuItem(
            value: missing.id,
            child: Text(
              '→ Asignar a: Esc. ${missing.scene} T${missing.take} (Reel ${missing.reel})',
              style: const TextStyle(color: Colors.blue),
              overflow: TextOverflow.ellipsis,
            ),
          ),
    ];

    if (!items.any((item) => item.value == dropdownValue)) {
      items.add(DropdownMenuItem(
        value: dropdownValue,
        child: Text(dropdownValue, overflow: TextOverflow.ellipsis),
      ));
    }

    return SizedBox(
      width: 290,
      child: DropdownButtonFormField<String>(
        value: dropdownValue,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          isDense: true,
        ),
        style: const TextStyle(fontSize: 12),
        items: items,
        onChanged: (val) {
          if (val == null) return;
          setState(() {
            if (val == '__UNASSIGNED__') {
              _overrides.remove(path);
            } else if (val == '__OMIT__') {
              _overrides[path] = null;
            } else if (val == targetRecord?.id || val == '__PRIMARY__') {
              _setWinner(group, path);
            } else {
              _overrides[path] = val;
            }
          });
        },
      ),
    );
  }

  Widget _buildFooter(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Restablecer a conflicto'),
          style: TextButton.styleFrom(
            foregroundColor: isDark ? Colors.orange.shade300 : Colors.orange.shade900,
          ),
          onPressed: _resetConflicts,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Guardar cambios'),
              onPressed: () => Navigator.of(context).pop(_overrides),
            ),
          ],
        ),
      ],
    );
  }
}
