import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/services/bitacora_parser_service.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/services/rename_service.dart';
import 'package:renombrata/src/services/report_export_service.dart';
import 'package:renombrata/src/services/project_service.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/app_settings.dart';
import 'package:renombrata/src/services/settings_service.dart';
import 'package:renombrata/src/ui/settings_dialog.dart';
import 'package:renombrata/src/ui/bitacora_editor_tab.dart';
import 'package:renombrata/src/ui/conflict_resolver_dialog.dart';
import 'package:renombrata/src/ui/media_preview_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:desktop_drop/desktop_drop.dart';
import '../../main.dart';

class HomeScreen extends StatefulWidget {
  final RenombrataProject? initialProject;
  final DryRunReport? initialReport;

  const HomeScreen({
    super.key,
    this.initialProject,
    this.initialReport,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  RenombrataProject _project = RenombrataProject(
    log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
    defaultReel: '001',
    activeCamera: 'A',
  );

  AppSettings _appSettings = AppSettings.defaults();

  @visibleForTesting
  RenombrataProject get project => _project;

  String? _projectPath;
  bool _isDirty = false;
  
  String? _mediaFolderPath;
  bool _renameMetadata = true;

  DryRunReport? _report;
  DryRunReport? _baseReport;
  bool _isLoading = false;
  List<Map<String, dynamic>> _renameHistory = [];
  Map<String, String?> _manualOverrides = {};
  bool _isDragging = false;

  String? _notificationMessage;
  bool _isNotificationError = false;
  Timer? _notificationTimer;

  final TextEditingController _reelController = TextEditingController(text: '001');
  final ScrollController _horizontalTableScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialProject != null) {
      _project = widget.initialProject!;
    }
    if (widget.initialReport != null) {
      _report = widget.initialReport;
    }
    _reelController.text = _project.defaultReel;
    SettingsService.loadSettings().then((s) {
      if (mounted) {
        setState(() {
          _appSettings = s;
        });
      }
    });
  }

  void _openSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        currentSettings: _appSettings,
        onSettingsChanged: (newSettings) {
          setState(() {
            _appSettings = newSettings;
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _reelController.dispose();
    _horizontalTableScrollController.dispose();
    _notificationTimer?.cancel();
    super.dispose();
  }

  String _computeDefaultReel(String camera) {
    if (_project.log.records.isEmpty) return '${camera}001';
    
    String baseReel = '';
    for (var r in _project.log.records) {
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

  void _updateProject(RenombrataProject newProject) {
    setState(() {
      _project = newProject;
      _isDirty = true;
    });
    // Auto-generate preview if tab is on renamer
    _generatePreview();
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

  Future<void> _newProject() async {
    final confirm = await _checkUnsavedChanges();
    if (!confirm) return;

    setState(() {
      _project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: '001',
        activeCamera: 'A',
      );
      _projectPath = null;
      _isDirty = false;
      _reelController.text = _project.defaultReel;
      _manualOverrides = {};
      _baseReport = null;
    });
    _generatePreview();
  }

  Future<void> _openProject() async {
    final confirm = await _checkUnsavedChanges();
    if (!confirm) return;

    List<PlatformFile> result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['renombrata', 'json'],
    );

    if (result.isNotEmpty && result.single.path != null) {
      try {
        final project = await ProjectService.loadProject(result.single.path!);
        setState(() {
          _project = project;
          _projectPath = result.single.path!;
          _isDirty = false;
          _reelController.text = _project.defaultReel;
          _manualOverrides = {};
          _baseReport = null;
        });
        _generatePreview();
        if (mounted) {
          _showNotification('Proyecto cargado correctamente.');
        }
      } catch (e) {
        if (mounted) {
          _showNotification('Error al cargar proyecto: $e', isError: true);
        }
      }
    }
  }

  Future<void> _saveProject() async {
    if (_projectPath == null) {
      await _saveProjectAs();
      return;
    }
    
    // Save current active camera and reel to project before saving
    _project = _project.copyWith(
      activeCamera: _project.activeCamera,
      defaultReel: _reelController.text.trim(),
    );

    try {
      await ProjectService.saveProject(_project, _projectPath!);
      setState(() {
        _isDirty = false;
      });
      if (mounted) {
        _showNotification('Proyecto guardado.');
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Error al guardar: $e', isError: true);
      }
    }
  }

  Future<void> _saveProjectAs() async {
    String? outputDir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta para guardar proyecto',
    );

    if (outputDir != null) {
      String outputFile = '$outputDir${Platform.pathSeparator}proyecto.renombrata';
      setState(() {
        _projectPath = outputFile;
      });
      await _saveProject();
    }
  }

  Future<bool> _checkUnsavedChanges() async {
    if (!_isDirty) return true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hay cambios sin guardar'),
        content: const Text('¿Desea continuar y perder los cambios no guardados?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar cambios'),
          ),
        ],
      ),
    );

    return confirm == true;
  }

  Future<void> _pickBitacora() async {
    List<PlatformFile> result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result.isNotEmpty && result.single.path != null) {
      setState(() {
        _isLoading = true;
      });

      try {
        final file = File(result.single.path!);
        final log = BitacoraParserService.parse(file);
        setState(() {
          _project = _project.copyWith(log: log);
          _isDirty = true;
          _reelController.text = _computeDefaultReel(_project.activeCamera);
          _manualOverrides = {};
          _baseReport = null;
        });
        _generatePreview();
        if (mounted) {
          _showNotification('Bitácora importada correctamente.');
        }
      } catch (e) {
        setState(() {
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
    try {
      String? selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Seleccionar carpeta de medios / clips',
      );

      if (selectedDirectory != null) {
        setState(() {
          _mediaFolderPath = selectedDirectory;
          _manualOverrides = {};
        });
        await _generatePreview();
        if (mounted) {
          final folderName = selectedDirectory.split(Platform.pathSeparator).last;
          final totalScanned = _report?.proposals.length ?? 0;
          if (_project.log.records.isEmpty) {
            _showNotification('Carpeta "$folderName" seleccionada ($totalScanned clips detectados). Importa un Excel o crea tomas en la Bitácora Digital para generar propuestas.');
          } else {
            _showNotification('Carpeta "$folderName" cargada correctamente ($totalScanned clips analizados).');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Error al abrir selector de carpeta: $e', isError: true);
      }
    }
  }

  Future<void> _generatePreview({Map<String, String?>? manualOverrides}) async {
    if (_mediaFolderPath == null) {
      if (_report == null) {
        setState(() {
          _baseReport = null;
          _renameHistory = [];
        });
      }
      return;
    }

    if (manualOverrides != null) {
      _manualOverrides = manualOverrides;
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

      final baseReport = await ClipMatcherService.matchFilesAsync(
        scannedFiles: scannedFiles,
        log: _project.log,
        targetCamera: _project.activeCamera,
        reelOverride: _reelController.text.trim().isNotEmpty ? _reelController.text.trim() : null,
        renameHistory: history,
        manualOverrides: const {},
      );

      final report = _manualOverrides.isEmpty
          ? baseReport
          : await ClipMatcherService.matchFilesAsync(
              scannedFiles: scannedFiles,
              log: _project.log,
              targetCamera: _project.activeCamera,
              reelOverride: _reelController.text.trim().isNotEmpty ? _reelController.text.trim() : null,
              renameHistory: history,
              manualOverrides: _manualOverrides,
            );

      setState(() {
        _baseReport = baseReport;
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
      _manualOverrides = {};
      _baseReport = null;
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

  Future<void> _openConflictResolver() async {
    if (_report == null && _baseReport == null) return;

    final reportToUse = _baseReport ?? _report!;

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => ConflictResolverDialog(
        report: reportToUse,
        log: _project.log,
        currentOverrides: _manualOverrides,
      ),
    );

    if (result != null) {
      setState(() {
        _manualOverrides = result;
      });
      await _generatePreview(manualOverrides: _manualOverrides);
    }
  }

  bool _isPlayableVideo(String? filePath) {
    if (filePath == null) return false;
    final ext = p.extension(filePath).toLowerCase();
    return ['.mp4', '.mov', '.mxf'].contains(ext);
  }

  void _openMediaPreview(RenameProposal proposal) {
    if (_report == null) return;
    final playlist = _report!.proposals
        .where((p) => p.originalFilePath != null && _isPlayableVideo(p.originalFilePath))
        .toList();
    if (playlist.isEmpty) return;

    final initialIndex = playlist.indexOf(proposal);

    showDialog(
      context: context,
      builder: (ctx) => MediaPreviewDialog(
        playlist: playlist,
        initialIndex: initialIndex >= 0 ? initialIndex : 0,
        projectMetadata: _project.log.metadata,
        activeCamera: _project.activeCamera,
        reelOverride: _reelController.text.trim().isNotEmpty ? _reelController.text.trim() : null,
        autoSortByClip: _project.autoSortByClip,
        onAutoSortChanged: (val) {
          setState(() {
            _project = _project.copyWith(autoSortByClip: val);
            _isDirty = true;
          });
        },
        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {
          final clipNum = ClipMatcherService.extractClipNumber(prop.originalFilePath ?? '');
          final fileReel = prop.fileReel ?? ClipMatcherService.extractReel(prop.originalFilePath ?? '');
          final targetReel = _reelController.text.trim().isNotEmpty
              ? _reelController.text.trim()
              : (fileReel ?? _project.defaultReel);

          final records = List<ShotRecord>.from(_project.log.records);
          final existingIdx = records.indexWhere((r) =>
              (chapter.isEmpty || r.chapter.trim() == chapter.trim()) &&
              r.scene.trim() == scene.trim() &&
              (r.plane ?? '').trim() == plane.trim() &&
              r.take.trim() == take.trim());

          if (existingIdx != -1) {
            final existing = records[existingIdx];
            final updatedCameras = List<CameraTakeRecord>.from(existing.cameras);
            final camIdx = updatedCameras.indexWhere((c) => c.cameraName == _project.activeCamera);
            if (camIdx != -1) {
              updatedCameras[camIdx] = updatedCameras[camIdx].copyWith(clipName: clipNum);
            } else {
              updatedCameras.add(CameraTakeRecord(cameraName: _project.activeCamera, clipName: clipNum));
            }

            records[existingIdx] = existing.copyWith(
              chapter: chapter.isNotEmpty ? chapter : existing.chapter,
              cameras: updatedCameras,
              reel: targetReel.isNotEmpty ? targetReel : existing.reel,
              tcIn: prop.fileTcIn ?? existing.tcIn,
              tcOut: prop.fileTcOut ?? existing.tcOut,
              observations: notes.isNotEmpty ? notes : existing.observations,
              isMos: isMos,
            );
          } else {
            final newRecord = ShotRecord(
              chapter: chapter,
              scene: scene,
              plane: plane.isNotEmpty ? plane : null,
              take: take,
              cameras: [
                CameraTakeRecord(cameraName: _project.activeCamera, clipName: clipNum),
              ],
              reel: targetReel,
              tcIn: prop.fileTcIn,
              tcOut: prop.fileTcOut,
              observations: notes.isNotEmpty ? notes : null,
              isMos: isMos,
            );
            records.add(newRecord);
          }

          final List<ShotRecord> finalRecords;
          if (_project.autoSortByClip) {
            finalRecords = BitacoraEditorTab.sortRecordsByClip(records, _project.activeCamera);
          } else {
            finalRecords = records;
          }

          setState(() {
            _project = _project.copyWith(
              log: ShootingLog(
                metadata: _project.log.metadata,
                records: finalRecords,
              ),
            );
            _isDirty = true;
          });

          await _generatePreview();
        },
      ),
    );
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
    if (_report == null || _mediaFolderPath == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await ReportExportService.exportReport(
        mediaFolderPath: _mediaFolderPath!,
        log: _project.log,
        report: _report!,
        activeCamera: _project.activeCamera,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String projectTitle = _projectPath != null 
        ? _projectPath!.split(Platform.pathSeparator).last 
        : 'Proyecto Sin Título';
    if (_isDirty) projectTitle += ' *';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Renombrata - $projectTitle',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          backgroundColor: isDark ? const Color(0xFF16161A) : Colors.white,
          foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF282832) : const Color(0xFFCBD5E1),
              width: 1,
            ),
          ),
          actions: [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, currentMode, child) {
                final isCurrentDark = currentMode == ThemeMode.dark;
                return IconButton(
                  icon: Icon(isCurrentDark ? Icons.light_mode : Icons.dark_mode),
                  tooltip: 'Cambiar modo oscuro / claro',
                  onPressed: () async {
                    final newMode = isCurrentDark ? ThemeMode.light : ThemeMode.dark;
                    themeNotifier.value = newMode;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('is_dark_mode', !isCurrentDark);
                  },
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Configuración',
              onPressed: _openSettingsDialog,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar Medios y Bitácora',
              onPressed: () {
                _generatePreview();
              },
            ),
            IconButton(
              icon: const Icon(Icons.note_add),
              tooltip: 'Nuevo Proyecto',
              onPressed: _newProject,
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Abrir Proyecto',
              onPressed: _openProject,
            ),
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Guardar',
              onPressed: _saveProject,
            ),
            IconButton(
              icon: const Icon(Icons.save_as),
              tooltip: 'Guardar como',
              onPressed: _saveProjectAs,
            ),
            const SizedBox(width: 16),
          ],
          bottom: TabBar(
            indicatorColor: const Color(0xFF6366F1),
            labelColor: isDark ? Colors.white : const Color(0xFF4F46E5),
            unselectedLabelColor: isDark ? const Color(0xFF8E8E9F) : const Color(0xFF64748B),
            tabs: const [
              Tab(icon: Icon(Icons.edit_document), text: 'Bitácora Digital'),
              Tab(icon: Icon(Icons.sync), text: 'Renombrador de Medios'),
            ],
          ),
        ),
        body: DropTarget(
          onDragEntered: (details) => setState(() => _isDragging = true),
          onDragExited: (details) => setState(() => _isDragging = false),
          onDragDone: (details) {
            setState(() => _isDragging = false);
            _handleDroppedFiles(details.files);
          },
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildNotificationBanner(),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Tab 1: Editor
                        BitacoraEditorTab(
                          project: _project,
                          settings: _appSettings,
                          onProjectChanged: _updateProject,
                        ),
                        // Tab 2: Conciliación
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildControlsBar(),
                              const SizedBox(height: 16),
                              Expanded(
                                child: _buildPreviewTable(),
                              ),
                              const SizedBox(height: 16),
                              _buildFooter(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_isDragging) _buildDragDropOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsBar() {
    final playablePlaylist = _report?.proposals
            .where((p) => p.originalFilePath != null && _isPlayableVideo(p.originalFilePath))
            .toList() ??
        [];

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _pickBitacora,
              icon: const Icon(Icons.description),
              label: const Text('Importar Excel'),
            ),
            DropdownButton<String>(
              value: _project.cameraNames.contains(_project.activeCamera) 
                  ? _project.activeCamera 
                  : (_project.cameraNames.isNotEmpty ? _project.cameraNames.first : null),
              items: _project.cameraNames.isEmpty 
                  ? [const DropdownMenuItem(value: 'A', child: Text('Cámara A'))]
                  : _project.cameraNames.map((cam) => DropdownMenuItem(value: cam, child: Text('Cámara $cam'))).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    String oldCamera = _project.activeCamera;
                    _project = _project.copyWith(activeCamera: val);
                    
                    if (_reelController.text.isEmpty) {
                      _reelController.text = _computeDefaultReel(_project.activeCamera);
                    } else {
                      String currentText = _reelController.text.trim();
                      final letterMatch = RegExp(r'^([A-Za-z])(\d+.*)$').firstMatch(currentText);
                      final numericMatch = RegExp(r'^(\d+.*)$').firstMatch(currentText);
                      
                      if (letterMatch != null && letterMatch.group(1)!.toUpperCase() == oldCamera) {
                        _reelController.text = '${_project.activeCamera}${letterMatch.group(2)}';
                      } else if (numericMatch != null) {
                        _reelController.text = '${_project.activeCamera}$currentText';
                      }
                    }
                  });
                  _generatePreview();
                }
              },
            ),
            SizedBox(
              width: 130,
              child: TextField(
                controller: _reelController,
                decoration: InputDecoration(
                  labelText: 'Reel activo',
                  hintText: _computeDefaultReel(_project.activeCamera),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  isDense: true,
                ),
                onChanged: (val) {
                  _generatePreview();
                },
              ),
            ),
            ElevatedButton.icon(
              onPressed: _pickMediaFolder,
              icon: const Icon(Icons.folder),
              label: const Text('Selector de Carpeta de Medios'),
            ),
            if (playablePlaylist.isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.movie_filter),
                label: Text('Inspeccionar Lote (${playablePlaylist.length})'),
                onPressed: () => _openMediaPreview(playablePlaylist.first),
              ),
            if (_mediaFolderPath != null)
              Chip(
                avatar: const Icon(Icons.check_circle, size: 16, color: Colors.green),
                label: Text(
                  _mediaFolderPath!.split(Platform.pathSeparator).last,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () {
                  setState(() {
                    _mediaFolderPath = null;
                    _report = null;
                    _renameHistory = [];
                  });
                },
              ),
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
                const SizedBox(width: 4),
                const Text('Renombrar metadatos (.XML)'),
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
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 4.0),
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
      if (_project.log.records.isNotEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open, size: 52, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
              const SizedBox(height: 12),
              Text(
                'Bitácora activa con ${_project.log.records.length} tomas registradas',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Haz clic en "Selector de Carpeta de Medios" para conciliar los clips con la Cámara ${_project.activeCamera}.',
                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined, size: 52, color: Theme.of(context).hintColor.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text(
              'Bienvenido al Renombrador de Medios',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Puedes seleccionar una Carpeta de Medios o Importar un Excel para comenzar.',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
            ),
          ],
        ),
      );
    }

    List<RenameProposal> displayProposals = _report!.proposals;
    if (!_renameMetadata) {
      displayProposals = displayProposals.where((p) => !p.isCompanionFile).toList();
    }

    if (displayProposals.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.find_in_page_outlined, size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(
              'No se detectaron archivos de video para la Cámara ${_project.activeCamera} en esta carpeta.',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Verifica que la carpeta contenga clips con el prefijo "${_project.activeCamera}" o selecciona otra carpeta.',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_project.log.records.isEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Se detectaron ${displayProposals.length} archivos en la carpeta de medios. La bitácora aún no tiene tomas registradas; importa un Excel o usa la pestaña "Bitácora Digital" para asignar nombres propuestos.',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade200 : Colors.amber.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Scrollbar(
                controller: _horizontalTableScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _horizontalTableScrollController,
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                    columns: const [
                      DataColumn(label: Text('Archivo Original')),
                      DataColumn(label: Text('TC Archivo (In → Out)')),
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

                      final logTc = p.associatedRecord?.tcIn;
                      final fileTc = p.fileTcIn;
                      final hasLogTc = logTc != null && logTc.trim().isNotEmpty;
                      final hasFileTc = fileTc != null && fileTc.trim().isNotEmpty;
                      final isMatched = p.isTimecodeMatched;

                      final isPlayable = _isPlayableVideo(p.originalFilePath);

                      return DataRow(cells: [
                        // 1. Archivo Original (clean single line with preview button if video)
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isPlayable) ...[
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _openMediaPreview(p),
                                  child: Tooltip(
                                    message: 'Reproducir e inspeccionar video',
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 6.0),
                                      child: Icon(
                                        Icons.play_circle_outline,
                                        size: 16,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              Text(original),
                            ],
                          ),
                          onDoubleTap: isPlayable ? () => _openMediaPreview(p) : null,
                        ),

                        // 2. TC Archivo (In → Out)
                        DataCell(
                          p.fileTcIn != null
                              ? Text(
                                  p.fileTcOut != null 
                                      ? '${p.fileTcIn} → ${p.fileTcOut}'
                                      : p.fileTcIn!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : Text('—', style: TextStyle(color: Theme.of(context).hintColor)),
                        ),

                        // 3. Nombre Propuesto
                        DataCell(Text(proposed)),

                        // 4. Escena / Toma (with TC Coincide or TC Diferente badge)
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(sceneTake),
                              if (p.hasReelDiscrepancy) ...[
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: 'El reel del archivo (${p.fileReel ?? "—"}) no coincide con el registrado en bitácora (${p.associatedRecord?.reel ?? "—"})',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.amber),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Reel: ${p.associatedRecord?.reel ?? '—'} ≠ ${p.fileReel}',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              if (isMatched) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.green),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle, size: 12, color: Colors.green),
                                      const SizedBox(width: 4),
                                      Text(
                                        p.timecodeDeltaSeconds != null && p.timecodeDeltaSeconds! > 0
                                            ? 'TC Coincide (±${p.timecodeDeltaSeconds}s)'
                                            : 'TC Coincide',
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (hasLogTc && hasFileTc && !isMatched) ...[
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: 'El timecode del archivo ($fileTc) no coincide con el registrado en bitácora ($logTc)',
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.amber),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber),
                                        SizedBox(width: 4),
                                        Text(
                                          'TC Diferente',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // 5. Estado
                        DataCell(
                          p.status == ProposalStatus.conflict
                              ? Tooltip(
                                  message: 'Haz clic para resolver este conflicto',
                                  child: InkWell(
                                    onTap: _openConflictResolver,
                                    borderRadius: BorderRadius.circular(12),
                                    child: _buildStatusBadge(p.status),
                                  ),
                                )
                              : _buildStatusBadge(p.status),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

    int conflictCount = _report?.proposals.where((p) => p.status == ProposalStatus.conflict && !p.isCompanionFile).length ?? 0;
    bool hasConflicts = _report?.proposals.any((p) => p.status == ProposalStatus.conflict) ?? false;

    final summaryText = '$listos listos | $faltantes faltantes en disco | $noRegistrados no registrados';

    final actionButtons = <Widget>[
      if (hasConflicts)
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade800,
            foregroundColor: Colors.white,
          ),
          onPressed: _openConflictResolver,
          icon: const Icon(Icons.warning_amber, size: 18),
          label: Text('Resolver conflictos ($conflictCount)'),
        )
      else if (_manualOverrides.isNotEmpty)
        OutlinedButton.icon(
          icon: const Icon(Icons.tune, size: 18),
          label: Text('Editar resoluciones (${_manualOverrides.length})'),
          onPressed: _openConflictResolver,
        ),
      if (_report != null && _report!.proposals.isNotEmpty)
        OutlinedButton.icon(
          onPressed: _exportReport,
          icon: const Icon(Icons.file_download),
          label: const Text('Exportar Reporte'),
        ),
      if (_renameHistory.isNotEmpty)
        OutlinedButton(
          onPressed: _undoRename,
          child: const Text('Deshacer renombrado'),
        ),
      ElevatedButton(
        onPressed: (readyToRename > 0 && !hasConflicts) ? _executeRename : null,
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: Colors.grey.shade300,
        ),
        child: const Text('Renombrar archivos'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1050) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                summaryText,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actionButtons,
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                summaryText,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < actionButtons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actionButtons[i],
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleDroppedFiles(List<dynamic> files) async {
    if (files.isEmpty) return;

    bool anyHandled = false;
    for (final item in files) {
      final String path = item.path as String;
      if (path.isEmpty) continue;

      // 1. Directory -> Media Folder
      if (Directory(path).existsSync()) {
        setState(() {
          _mediaFolderPath = path;
          _manualOverrides = {};
          _baseReport = null;
        });
        await _generatePreview();
        anyHandled = true;
        if (mounted) {
          _showNotification('Carpeta de medios cargada: ${p.basename(path)} (${_report?.proposals.length ?? 0} clips detectados)');
        }
        continue;
      }

      final lower = path.toLowerCase();

      // 2. Excel File -> Bitácora (.xlsx, .xls)
      if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
        setState(() {
          _isLoading = true;
        });
        try {
          final file = File(path);
          final log = BitacoraParserService.parse(file);
          setState(() {
            _project = _project.copyWith(log: log);
            _isDirty = true;
            _reelController.text = _computeDefaultReel(_project.activeCamera);
            _manualOverrides = {};
            _baseReport = null;
          });
          await _generatePreview();
          anyHandled = true;
          if (mounted) {
            _showNotification('Bitácora importada: ${p.basename(path)} (${log.records.length} tomas registradas)');
          }
        } catch (e) {
          if (mounted) {
            _showNotification('Error al leer la bitácora: Verifique que sea un archivo Excel válido', isError: true);
          }
        } finally {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
        continue;
      }

      // 3. Project File -> (.renombrata, .json)
      if (lower.endsWith('.renombrata') || lower.endsWith('.json')) {
        final confirm = await _checkUnsavedChanges();
        if (!confirm) return;

        try {
          final project = await ProjectService.loadProject(path);
          setState(() {
            _project = project;
            _projectPath = path;
            _isDirty = false;
            _reelController.text = _project.defaultReel;
            _manualOverrides = {};
            _baseReport = null;
          });
          await _generatePreview();
          anyHandled = true;
          if (mounted) {
            _showNotification('Proyecto cargado: ${p.basename(path)}');
          }
        } catch (e) {
          if (mounted) {
            _showNotification('Error al cargar proyecto: $e', isError: true);
          }
        }
        continue;
      }
    }

    if (!anyHandled && mounted) {
      final firstFileName = p.basename(files.first.path as String);
      _showNotification(
        'Archivo no soportado: "$firstFileName". Formatos aceptados: carpetas de medios, Excel (.xlsx, .xls) o proyectos (.renombrata).',
        isError: true,
      );
    }
  }

  Widget _buildDragDropOverlay() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: isDark ? Colors.black54 : Colors.white70,
          child: Center(
            child: CustomPaint(
              painter: _DashedBorderPainter(
                color: primaryColor,
                strokeWidth: 2.5,
                dash: 8.0,
                gap: 5.0,
                radius: 20.0,
              ),
              child: Container(
                width: 540,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E26).withValues(alpha: 0.95)
                      : Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.file_download_outlined,
                        size: 52,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Suelta tus archivos aquí',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Suelta aquí carpetas de medios, archivos Excel (.xlsx) o proyectos (.renombrata)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildOverlayBadge(Icons.folder_outlined, 'Carpeta de Medios', primaryColor),
                        _buildOverlayBadge(Icons.table_chart_outlined, 'Bitácora (.xlsx, .xls)', Colors.green.shade600),
                        _buildOverlayBadge(Icons.description_outlined, 'Proyecto (.renombrata)', Colors.purple.shade400),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayBadge(IconData icon, String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDark ? color : color.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;
  final double radius;

  _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 2.0,
    this.dash = 6.0,
    this.gap = 4.0,
    this.radius = 16.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double length = (distance + dash <= metric.length) ? dash : metric.length - distance;
        final extractPath = metric.extractPath(distance, distance + length);
        canvas.drawPath(extractPath, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
}
