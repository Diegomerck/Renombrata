import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/services/bitacora_parser_service.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/services/rename_service.dart';
import 'package:renombrata/src/services/report_export_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _bitacoraPath;
  ShootingLog? _parsedLog;
  String _activeCamera = 'A';
  String? _mediaFolderPath;
  bool _renameMetadata = true;

  DryRunReport? _report;
  bool _isLoading = false;
  List<Map<String, dynamic>> _renameHistory = [];

  String? _notificationMessage;
  bool _isNotificationError = false;
  Timer? _notificationTimer;

  final TextEditingController _reelController = TextEditingController();

  @override
  void dispose() {
    _reelController.dispose();
    _notificationTimer?.cancel();
    super.dispose();
  }

  String _computeDefaultReel(String camera) {
    if (_parsedLog == null || _parsedLog!.records.isEmpty) return '${camera}001';
    
    String baseReel = '';
    for (var r in _parsedLog!.records) {
      if (r.reel.trim().isNotEmpty) {
        baseReel = r.reel.trim();
        break;
      }
    }
    
    if (baseReel.isEmpty) return '${camera}001';

    final letterMatch = RegExp(r'^([A-Za-z])(\d+.*)$').firstMatch(baseReel);
    if (letterMatch != null) {
      return '$camera${letterMatch.group(2)}';
    } else {
      final numericMatch = RegExp(r'^(\d+.*)$').firstMatch(baseReel);
      if (numericMatch != null) {
        return '$camera$baseReel';
      }
    }
    return baseReel;
  }

  void _showNotification(String message, {bool isError = false}) {
    _notificationTimer?.cancel();
    setState(() {
      _notificationMessage = message;
      _isNotificationError = isError;
    });
    _notificationTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _notificationMessage = null;
        });
      }
    });
  }

  void _clearNotification() {
    _notificationTimer?.cancel();
    setState(() {
      _notificationMessage = null;
    });
  }

  Future<void> _pickBitacora() async {
    List<PlatformFile> result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result.isNotEmpty && result.single.path != null) {
      setState(() {
        _isLoading = true;
        _bitacoraPath = result.single.path!;
      });

      try {
        final file = File(_bitacoraPath!);
        final log = BitacoraParserService.parse(file);
        setState(() {
          _parsedLog = log;
          _reelController.text = _computeDefaultReel(_activeCamera);
        });
        _generatePreview();
      } catch (e) {
        setState(() {
          _parsedLog = null;
          _report = null;
        });
        if (mounted) {
          _showNotification('Error al leer la bitácora: Verifique que sea un archivo Excel válido', isError: true);
        }
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickMediaFolder() async {
    String? selectedDirectory = await FilePicker.getDirectoryPath();

    if (selectedDirectory != null) {
      setState(() {
        _mediaFolderPath = selectedDirectory;
      });
      _generatePreview();
    }
  }

  Future<void> _generatePreview() async {
    if (_parsedLog == null || _mediaFolderPath == null) {
      setState(() {
        _report = null;
        _renameHistory = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final history = await RenameService.readRenameHistory(_mediaFolderPath!);
      final scannedFiles = MediaScannerService.scanDirectory(
        _mediaFolderPath!,
        searchSubdirectories: true,
      );

      final report = ClipMatcherService.matchFiles(
        scannedFiles: scannedFiles,
        log: _parsedLog!,
        targetCamera: _activeCamera,
        reelOverride: _reelController.text.trim().isNotEmpty ? _reelController.text.trim() : null,
        renameHistory: history,
      );

      setState(() {
        _report = report;
        _renameHistory = history;
      });
    } catch (e) {
      if (mounted) {
        _showNotification('Error al procesar archivos: $e', isError: true);
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _executeRename() async {
    if (_report == null || _mediaFolderPath == null) return;

    final readyCount = _report!.proposals.where((p) {
      if (p.status != ProposalStatus.ready) return false;
      if (!_renameMetadata && p.isCompanionFile) return false;
      return true;
    }).length;

    if (readyCount == 0) return;

    int faltantes = _report!.totalMissing;
    int noRegistrados = _report!.totalUnmatched;
    
    String extraWarning = '';
    if (faltantes > 0 || noRegistrados > 0) {
      extraWarning = '\n\nAviso: Existen archivos faltantes o no registrados en esta carpeta. Solo se renombrarán los $readyCount archivos listos coincidentes.';
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Confirmar renombrado de archivos?'),
        content: Text('Se renombrarán $readyCount archivos en el disco. Esta acción modificará los nombres originales.$extraWarning'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar y Renombrar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await RenameService.executeRename(
        mediaFolderPath: _mediaFolderPath!,
        proposals: _report!.proposals,
        renameMetadata: _renameMetadata,
      );

      // Call _generatePreview to reload history and update UI accurately
      await _generatePreview();

      if (mounted) {
        _showNotification('Renombrado exitoso.');
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Error durante el renombrado: $e', isError: true);
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshBitacora() async {
    if (_bitacoraPath == null) return;
    
    try {
      final file = File(_bitacoraPath!);
      final log = BitacoraParserService.parse(file);
      setState(() {
        _parsedLog = log;
      });
      await _generatePreview();
      if (mounted) {
        _showNotification('Bitácora actualizada correctamente');
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Error al actualizar: $e', isError: true);
      }
    }
  }

  Future<void> _undoRename() async {
    if (_mediaFolderPath == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Deshacer último renombrado?'),
        content: const Text('Se restaurarán los nombres originales de los archivos procesados en este lote.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar y Deshacer'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await RenameService.undoRename(_mediaFolderPath!);
      await _generatePreview();
      if (mounted) {
        _showNotification('Renombrado deshecho con éxito');
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Error al deshacer: $e', isError: true);
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportReport() async {
    if (_report == null || _parsedLog == null || _mediaFolderPath == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await ReportExportService.exportReport(
        mediaFolderPath: _mediaFolderPath!,
        log: _parsedLog!,
        report: _report!,
        activeCamera: _activeCamera,
      );
      if (mounted) {
        _showNotification('Reporte exportado exitosamente');
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Error al exportar reporte: $e', isError: true);
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Renombrata'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildControlsBar(),
            const SizedBox(height: 16),
            _buildMetadataCard(),
            _buildNotificationBanner(),
            const SizedBox(height: 16),
            Expanded(
              child: _buildPreviewTable(),
            ),
            const SizedBox(height: 16),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsBar() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _pickBitacora,
              icon: const Icon(Icons.description),
              label: const Text('Selector de Bitácora'),
            ),
            if (_bitacoraPath != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _bitacoraPath!.split(Platform.pathSeparator).last,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Actualizar bitácora',
                    onPressed: _refreshBitacora,
                  ),
                ],
              ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _activeCamera,
              items: const [
                DropdownMenuItem(value: 'A', child: Text('Cámara A')),
                DropdownMenuItem(value: 'B', child: Text('Cámara B')),
                DropdownMenuItem(value: 'C', child: Text('Cámara C')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    String oldCamera = _activeCamera;
                    _activeCamera = val;
                    if (_reelController.text.isEmpty) {
                      _reelController.text = _computeDefaultReel(_activeCamera);
                    } else {
                      String currentText = _reelController.text.trim();
                      final letterMatch = RegExp(r'^([A-Za-z])(\d+.*)$').firstMatch(currentText);
                      final numericMatch = RegExp(r'^(\d+.*)$').firstMatch(currentText);
                      
                      if (letterMatch != null && letterMatch.group(1)!.toUpperCase() == oldCamera) {
                        _reelController.text = '$_activeCamera${letterMatch.group(2)}';
                      } else if (numericMatch != null) {
                        _reelController.text = '$_activeCamera$currentText';
                      }
                    }
                  });
                  _generatePreview();
                }
              },
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _reelController,
                decoration: InputDecoration(
                  labelText: 'Reel activo',
                  hintText: _computeDefaultReel(_activeCamera),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (val) {
                  _generatePreview();
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _pickMediaFolder,
              icon: const Icon(Icons.folder),
              label: const Text('Selector de Carpeta de Medios'),
            ),
            if (_mediaFolderPath != null)
              Text(
                _mediaFolderPath!.split(Platform.pathSeparator).last,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: _renameMetadata,
                  onChanged: (val) {
                    setState(() {
                      _renameMetadata = val;
                    });
                  },
                ),
                const Expanded(
                  child: Text('Renombrar archivos de metadatos (.XML) asociados'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataCard() {
    if (_parsedLog == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Seleccione una bitácora para ver los metadatos.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final meta = _parsedLog!.metadata;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Metadatos de la Bitácora', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                Text('Producción: ${meta.production}'),
                Text('Nomenclatura: ${meta.nomenclature}'),
                Text('Fecha: ${meta.date}'),
                Text('Día: ${meta.day}'),
                Text('Unidad: ${meta.unit}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationBanner() {
    if (_notificationMessage == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: _isNotificationError ? Colors.red.shade100 : Colors.green.shade100,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Icon(
                _isNotificationError ? Icons.error_outline : Icons.check_circle_outline,
                color: _isNotificationError ? Colors.red.shade900 : Colors.green.shade900,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _notificationMessage!,
                  style: TextStyle(
                    color: _isNotificationError ? Colors.red.shade900 : Colors.green.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearNotification,
                color: _isNotificationError ? Colors.red.shade900 : Colors.green.shade900,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_report == null) {
      return const Center(
        child: Text('Seleccione la bitácora y la carpeta de medios para ver la vista previa.'),
      );
    }

    List<RenameProposal> displayProposals = _report!.proposals;
    if (!_renameMetadata) {
      displayProposals = displayProposals.where((p) => !p.isCompanionFile).toList();
    }

    return Card(
      child: SingleChildScrollView(
        child: DataTable(
          headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
          columns: const [
            DataColumn(label: Text('Archivo Original')),
            DataColumn(label: Text('Nombre Propuesto')),
            DataColumn(label: Text('Escena / Toma')),
            DataColumn(label: Text('Estado')),
          ],
          rows: displayProposals.map((p) {
            String original = p.originalFilePath != null ? p.originalFilePath!.split(Platform.pathSeparator).last : '—';
            String proposed = p.proposedFileName;
            if (p.status == ProposalStatus.unmatchedClip) proposed = '—';

            String sceneTake = '—';
            if (p.associatedRecord != null) {
              String takeStr = p.associatedRecord!.take;
              String displayTake = takeStr.toUpperCase().startsWith('T') ? takeStr : 'T$takeStr';
              sceneTake = 'Esc. ${p.associatedRecord!.scene} - $displayTake';
            }

            return DataRow(cells: [
              DataCell(Text(original)),
              DataCell(Text(proposed)),
              DataCell(Text(sceneTake)),
              DataCell(_buildStatusBadge(p.status)),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ProposalStatus status) {
    Color bgColor;
    String text;

    switch (status) {
      case ProposalStatus.ready:
        bgColor = Colors.green;
        text = 'Listo para renombrar';
        break;
      case ProposalStatus.missingFile:
        bgColor = Colors.amber;
        text = 'Falta archivo en disco';
        break;
      case ProposalStatus.unmatchedClip:
        bgColor = Colors.orange;
        text = 'Clip no registrado';
        break;
      case ProposalStatus.conflict:
        bgColor = Colors.red;
        text = 'Conflicto';
        break;
      case ProposalStatus.renamed:
        bgColor = Colors.blue;
        text = 'Renombrado exitoso';
        break;
      case ProposalStatus.alreadyRenamed:
        bgColor = Colors.blue;
        text = 'Ya renombrado';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildFooter() {
    int listos = _report?.totalMatched ?? 0;
    int faltantes = _report?.totalMissing ?? 0;
    int noRegistrados = _report?.totalUnmatched ?? 0;

    int readyToRename = _report?.proposals.where((p) {
      if (p.status != ProposalStatus.ready) return false;
      if (!_renameMetadata && p.isCompanionFile) return false;
      return true;
    }).length ?? 0;

    bool hasConflicts = _report?.proposals.any((p) => p.status == ProposalStatus.conflict) ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            '$listos listos | $faltantes faltantes en disco | $noRegistrados no registrados',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_report != null && _report!.proposals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: OutlinedButton.icon(
                  onPressed: _exportReport,
                  icon: const Icon(Icons.file_download),
                  label: const Text('Exportar Reporte'),
                ),
              ),
            if (_renameHistory.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: OutlinedButton(
                  onPressed: _undoRename,
                  child: const Text('Deshacer renombrado'),
                ),
              ),
            ElevatedButton(
              onPressed: (readyToRename > 0 && !hasConflicts) ? _executeRename : null,
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: Colors.grey.shade300,
              ),
              child: const Text('Renombrar archivos'),
            ),
          ],
        ),
      ],
    );
  }
}
