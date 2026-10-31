import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../models/renombrata_project.dart';
import '../models/shooting_log.dart';
import '../services/settings_service.dart';
import '../utils/shortcut_utils.dart';

class SettingsDialog extends StatefulWidget {
  final AppSettings currentSettings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final RenombrataProject? project;
  final ValueChanged<RenombrataProject>? onProjectChanged;
  final int initialTabIndex;

  const SettingsDialog({
    super.key,
    required this.currentSettings,
    required this.onSettingsChanged,
    this.project,
    this.onProjectChanged,
    this.initialTabIndex = 0,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late AppSettings _settings;
  late List<CameraConfig> _tempCameras;
  late bool _tempShowChapter;
  late bool _tempShowPlane;
  late bool _tempShowMos;
  late bool _tempShowTcOut;
  late bool _tempShowDs;
  late bool _tempShowFf;
  late bool _tempShowGpr;
  late bool _tempShowDr;
  late bool _tempShowTf;
  late List<String> _tempBitacoraElementOrder;
  late List<String> _tempConventionNameOrder;

  static const Map<String, String> _elementLabels = {
    'capitulo': 'Capítulo',
    'escena': 'Escena',
    'plano': 'Plano',
    'toma': 'Toma',
  };

  static const Map<String, IconData> _elementIcons = {
    'capitulo': Icons.bookmark_outline,
    'escena': Icons.movie_creation_outlined,
    'plano': Icons.crop_free_outlined,
    'toma': Icons.videocam_outlined,
  };

  @override
  void initState() {
    super.initState();
    _settings = widget.currentSettings;
    _initProjectState();
  }

  void _initProjectState() {
    if (widget.project != null) {
      _tempCameras = List<CameraConfig>.from(widget.project!.cameras);
      _tempShowChapter = widget.project!.showChapter;
      _tempShowPlane = widget.project!.showPlane;
      _tempShowMos = widget.project!.showMos;
      _tempShowTcOut = widget.project!.showTcOut;
      _tempShowDs = widget.project!.showDs;
      _tempShowFf = widget.project!.showFf;
      _tempShowGpr = widget.project!.showGpr;
      _tempShowDr = widget.project!.showDr;
      _tempShowTf = widget.project!.showTf;
      _tempBitacoraElementOrder = List<String>.from(widget.project!.bitacoraElementOrder);
      _tempConventionNameOrder = List<String>.from(widget.project!.conventionNameOrder);
    } else {
      _tempCameras = [const CameraConfig(name: 'A', type: CameraType.regular)];
      _tempShowChapter = false;
      _tempShowPlane = false;
      _tempShowMos = false;
      _tempShowTcOut = true;
      _tempShowDs = true;
      _tempShowFf = true;
      _tempShowGpr = true;
      _tempShowDr = true;
      _tempShowTf = true;
      _tempBitacoraElementOrder = const ['capitulo', 'escena', 'plano', 'toma'];
      _tempConventionNameOrder = const ['capitulo', 'escena', 'plano', 'toma'];
    }
  }

  void _updateSettings(AppSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    widget.onSettingsChanged(_settings);
    SettingsService.saveSettings(_settings);
  }

  void _syncProjectChanges() {
    if (widget.project == null || widget.onProjectChanged == null) return;

    final cleanCameras = _tempCameras
        .map((c) => c.copyWith(name: c.name.trim()))
        .where((c) => c.name.isNotEmpty)
        .toList();
    final effectiveCameras = cleanCameras.isEmpty
        ? const [CameraConfig(name: 'A', type: CameraType.regular)]
        : cleanCameras;

    final updatedRecords = widget.project!.log.records.map((record) {
      final updatedCameras = List<CameraTakeRecord>.from(record.cameras);
      for (var cam in effectiveCameras) {
        if (!updatedCameras.any((c) => c.cameraName.toUpperCase() == cam.name.toUpperCase())) {
          updatedCameras.add(CameraTakeRecord(cameraName: cam.name, clipName: ''));
        }
      }
      return record.copyWith(cameras: updatedCameras);
    }).toList();

    final updatedLog = widget.project!.log.copyWith(records: updatedRecords);
    final updatedProject = widget.project!.copyWith(
      cameras: effectiveCameras,
      cameraNames: effectiveCameras.map((c) => c.name).toList(),
      showChapter: _tempShowChapter,
      showPlane: _tempShowPlane,
      showMos: _tempShowMos,
      showTcOut: _tempShowTcOut,
      showDs: _tempShowDs,
      showFf: _tempShowFf,
      showGpr: _tempShowGpr,
      showDr: _tempShowDr,
      showTf: _tempShowTf,
      bitacoraElementOrder: _tempBitacoraElementOrder,
      conventionNameOrder: _tempConventionNameOrder,
      log: updatedLog,
    );
    widget.onProjectChanged!(updatedProject);
  }

  Future<void> _exportSettings() async {
    try {
      final jsonStr = await SettingsService.exportSettingsJson(_settings);
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Exportar configuración',
        fileName: 'renombrata_settings.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (uri != null) {
        try {
          final file = File(uri.toFilePath());
          if (!await file.exists()) {
            await file.writeAsBytes(bytes);
          }
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Configuración exportada correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar configuración: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importSettings() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result.isNotEmpty && result.single.path != null) {
        final content = await File(result.single.path!).readAsString();
        final imported = SettingsService.importSettingsJson(content);
        _updateSettings(imported);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Configuración importada y aplicada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al importar archivo de configuración: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editShortcut(String actionKey, String currentShortcut) async {
    final theme = Theme.of(context);
    final actionName = ShortcutUtils.actionLabels[actionKey] ?? actionKey;

    final parts = currentShortcut.split('+').map((s) => s.trim()).toList();
    bool ctrl = parts.any((p) => p.toLowerCase() == 'ctrl' || p.toLowerCase() == 'cmd');
    bool alt = parts.any((p) => p.toLowerCase() == 'alt');
    bool shift = parts.any((p) => p.toLowerCase() == 'shift');

    String selectedKey = parts.lastWhere(
      (p) => !['ctrl', 'cmd', 'alt', 'shift'].contains(p.toLowerCase()),
      orElse: () => 'N',
    ).toUpperCase();

    if (!ShortcutUtils.availableKeys.contains(selectedKey)) {
      selectedKey = ShortcutUtils.availableKeys.first;
    }

    final newShortcut = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String computeShortcutStr() {
              final prefix = <String>[];
              if (ctrl) prefix.add('Ctrl');
              if (alt) prefix.add('Alt');
              if (shift) prefix.add('Shift');
              prefix.add(selectedKey);
              return prefix.join('+');
            }

            final currentCombo = computeShortcutStr();

            return AlertDialog(
              title: Text('Modificar Atajo: $actionName'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Selecciona los modificadores y la tecla correspondiente:'),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        FilterChip(
                          label: const Text('Ctrl / Cmd'),
                          selected: ctrl,
                          onSelected: (val) {
                            setDialogState(() {
                              ctrl = val;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Alt'),
                          selected: alt,
                          onSelected: (val) {
                            setDialogState(() {
                              alt = val;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Shift'),
                          selected: shift,
                          onSelected: (val) {
                            setDialogState(() {
                              shift = val;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedKey,
                      decoration: const InputDecoration(
                        labelText: 'Tecla principal',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: ShortcutUtils.availableKeys.map((k) {
                        return DropdownMenuItem(value: k, child: Text(k));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedKey = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Vista previa del atajo:',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                          ),
                          const SizedBox(height: 6),
                          _buildShortcutBadge(currentCombo, theme),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(currentCombo),
                  child: const Text('Guardar atajo'),
                ),
              ],
            );
          },
        );
      },
    );

    if (newShortcut != null && newShortcut.isNotEmpty) {
      final updatedShortcuts = Map<String, String>.from(_settings.shortcuts);
      updatedShortcuts[actionKey] = newShortcut;
      _updateSettings(_settings.copyWith(shortcuts: updatedShortcuts));
    }
  }

  Widget _buildShortcutBadge(String shortcut, ThemeData theme) {
    final parts = shortcut.split('+').map((s) => s.trim()).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        parts.join(' + '),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          fontFamily: 'monospace',
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildGeneralTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Visualización de Bitácora',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                RadioListTile<bool>(
                  value: true,
                  groupValue: _settings.usePagesStyleLayout,
                  title: const Text(
                    'Diseño moderno (Estilo bitácora)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Texto en negrita y agrupación visual por escena. Oculta capítulo, escena y plano repetidos en tomas consecutivas para mayor legibilidad y destaca el inicio de cada nueva escena.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (val) {
                    if (val != null) {
                      _updateSettings(_settings.copyWith(usePagesStyleLayout: val));
                    }
                  },
                ),
                const Divider(height: 1),
                RadioListTile<bool>(
                  value: false,
                  groupValue: _settings.usePagesStyleLayout,
                  title: const Text(
                    'Diseño anterior (Clásico)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Muestra y repite los campos de capítulo, escena y plano en cada fila individual.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (val) {
                    if (val != null) {
                      _updateSettings(_settings.copyWith(usePagesStyleLayout: val));
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Orientación del Renombrador de Medios',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Define si los archivos originales aparecen a la izquierda o derecha en la pantalla de renombrado.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                RadioListTile<String>(
                  value: 'media_left',
                  groupValue: _settings.renamerPaneLayout,
                  title: const Text(
                    'Medios a la izquierda, Nombres a la derecha (Estilo Finder)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Los archivos de cámara originales se muestran en la columna izquierda y los nombres propuestos a la derecha.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (val) {
                    if (val != null) {
                      _updateSettings(_settings.copyWith(renamerPaneLayout: val));
                    }
                  },
                ),
                const Divider(height: 1),
                RadioListTile<String>(
                  value: 'media_right',
                  groupValue: _settings.renamerPaneLayout,
                  title: const Text(
                    'Nombres a la izquierda, Medios a la derecha',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Los nombres propuestos de la bitácora aparecen a la izquierda y los archivos originales a la derecha.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (val) {
                    if (val != null) {
                      _updateSettings(_settings.copyWith(renamerPaneLayout: val));
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Portabilidad de Configuración',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Exporta tus preferencias a un archivo JSON o importa una configuración compartida para sincronizar flujos de trabajo.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Exportar configuración...'),
                  onPressed: _exportSettings,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Importar configuración...'),
                  onPressed: _importSettings,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBitacoraTab(ThemeData theme) {
    if (widget.project == null) {
      return Center(
        child: Text(
          'Abre o crea un proyecto para configurar columnas y cámaras de la bitácora.',
          style: TextStyle(color: theme.hintColor),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Columnas y Campos Visibles',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                CheckboxListTile(
                  title: const Text('Capítulo'),
                  subtitle: const Text('Muestra la columna y campo de capítulo (Cap)'),
                  value: _tempShowChapter,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setState(() {
                      _tempShowChapter = val ?? false;
                    });
                    _syncProjectChanges();
                  },
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  title: const Text('Plano'),
                  subtitle: const Text('Muestra la columna y campo de encuadre/plano'),
                  value: _tempShowPlane,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setState(() {
                      _tempShowPlane = val ?? false;
                    });
                    _syncProjectChanges();
                  },
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  title: const Text('MOS (Sin Sonido)'),
                  subtitle: const Text('Muestra la casilla para tomas sin registro de audio'),
                  value: _tempShowMos,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setState(() {
                      _tempShowMos = val ?? false;
                    });
                    _syncProjectChanges();
                  },
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  title: const Text('TC Out'),
                  subtitle: const Text('Muestra la columna de código de tiempo de salida'),
                  value: _tempShowTcOut,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setState(() {
                      _tempShowTcOut = val ?? true;
                    });
                    _syncProjectChanges();
                  },
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  title: const Text('DS (Driving Shot)'),
                  subtitle: const Text('Muestra la casilla para tomas en vehículo / conducción'),
                  value: _tempShowDs,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setState(() {
                      _tempShowDs = val ?? true;
                    });
                    _syncProjectChanges();
                  },
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  title: const Text('FF (Free Fly)'),
                  subtitle: const Text('Muestra la casilla para tomas con cámara en mano o gimbal'),
                  value: _tempShowFf,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setState(() {
                      _tempShowFf = val ?? true;
                    });
                    _syncProjectChanges();
                  },
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  title: const Text('GPR (GoPro)'),
                  subtitle: const Text('Muestra la casilla para tomas grabadas con cámaras de acción'),
                  value: _tempShowGpr,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setState(() {
                      _tempShowGpr = val ?? true;
                    });
                    _syncProjectChanges();
                  },
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  title: const Text('DR (Drone)'),
                  subtitle: const Text('Muestra la casilla para tomas grabadas con drone'),
                  value: _tempShowDr,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setState(() {
                      _tempShowDr = val ?? true;
                    });
                    _syncProjectChanges();
                  },
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  title: const Text('TF (Toma Falsa)'),
                  subtitle: const Text('Muestra la casilla para tomas falsas o descartadas'),
                  value: _tempShowTf,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (val) {
                    setState(() {
                      _tempShowTf = val ?? true;
                    });
                    _syncProjectChanges();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Orden de elementos en la bitácora',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Arrastra los bloques para configurar el orden de las columnas principales en la bitácora.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 10),
          _buildReorderableBlockList(
            listId: 'bitacora',
            items: _tempBitacoraElementOrder,
            onReorder: (newList) {
              _tempBitacoraElementOrder = newList;
            },
            theme: theme,
          ),
          const SizedBox(height: 20),
          Text(
            'Orden de elementos en el nombre de convención',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Arrastra los bloques para definir el orden en la nomenclatura de archivos exportados.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 10),
          _buildReorderableBlockList(
            listId: 'convention',
            items: _tempConventionNameOrder,
            onReorder: (newList) {
              _tempConventionNameOrder = newList;
            },
            theme: theme,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Configuración de Cámaras',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Añadir Cámara'),
                onPressed: () {
                  setState(() {
                    final nextLetter = _tempCameras.length < 26
                        ? String.fromCharCode('A'.codeUnitAt(0) + _tempCameras.length)
                        : 'CAM ${_tempCameras.length + 1}';
                    _tempCameras.add(CameraConfig(name: nextLetter, type: CameraType.regular));
                  });
                  _syncProjectChanges();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _tempCameras.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _tempCameras.removeAt(oldIndex);
                _tempCameras.insert(newIndex, item);
              });
              _syncProjectChanges();
            },
            itemBuilder: (context, i) {
              final cam = _tempCameras[i];
              return Padding(
                key: ValueKey('cam_row_${i}_${_tempCameras.length}'),
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6.0),
                          child: Icon(Icons.drag_handle, size: 20),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        key: ValueKey('cam_${i}_${_tempCameras.length}'),
                        initialValue: cam.name,
                        decoration: InputDecoration(
                          labelText: 'Cámara ${i + 1}',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          _tempCameras[i] = _tempCameras[i].copyWith(name: val);
                          _syncProjectChanges();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<CameraType>(
                        key: ValueKey('cam_type_${i}_${_tempCameras.length}'),
                        value: cam.type,
                        isDense: true,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de Cámara',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: CameraType.values.map((type) {
                          return DropdownMenuItem<CameraType>(
                            value: type,
                            child: Text(type.label, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (newType) {
                          if (newType != null) {
                            setState(() {
                              _tempCameras[i] = _tempCameras[i].copyWith(type: newType);
                            });
                            _syncProjectChanges();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      tooltip: 'Eliminar cámara',
                      onPressed: _tempCameras.length <= 1
                          ? null
                          : () {
                              setState(() {
                                _tempCameras.removeAt(i);
                              });
                              _syncProjectChanges();
                            },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReorderableBlockList({
    required String listId,
    required List<String> items,
    required ValueChanged<List<String>> onReorder,
    required ThemeData theme,
  }) {
    return SizedBox(
      height: 48,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: items.length,
        proxyDecorator: (child, index, animation) {
          return Material(
            color: Colors.transparent,
            elevation: 4,
            shadowColor: Colors.black45,
            borderRadius: BorderRadius.circular(8),
            child: child,
          );
        },
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex--;
            final item = items.removeAt(oldIndex);
            items.insert(newIndex, item);
          });
          onReorder(items);
          _syncProjectChanges();
        },
        itemBuilder: (context, index) {
          final key = items[index];
          final label = _elementLabels[key] ?? key;
          final icon = _elementIcons[key] ?? Icons.label_outline;

          return ReorderableDragStartListener(
            key: ValueKey('${listId}_$key'),
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.drag_indicator,
                      size: 16,
                      color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 6),
                    Icon(icon, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildShortcutsTab(ThemeData theme) {
    final actions = [
      'new_take',
      'duplicate_take',
      'stamp_cut',
      'undo_delete',
      'save_project',
    ];

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            itemCount: actions.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final actionKey = actions[index];
              final label = ShortcutUtils.actionLabels[actionKey] ?? actionKey;
              final desc = ShortcutUtils.actionDescriptions[actionKey] ?? '';
              final currentShortcut = _settings.shortcuts[actionKey] ??
                  AppSettings.defaultShortcuts[actionKey] ??
                  '';

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(desc, style: TextStyle(fontSize: 12, color: theme.hintColor)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildShortcutBadge(currentShortcut, theme),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Modificar atajo',
                      onPressed: () => _editShortcut(actionKey, currentShortcut),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Personaliza los atajos de teclado para tu flujo de trabajo.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Restablecer atajos'),
                onPressed: () {
                  _updateSettings(_settings.copyWith(shortcuts: AppSettings.defaultShortcuts));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTabIndex,
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                const Text('Configuración', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            TabBar(
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.hintColor,
              indicatorColor: theme.colorScheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.tune, size: 18), text: 'General'),
                Tab(icon: Icon(Icons.view_column_outlined, size: 18), text: 'Bitácora'),
                Tab(icon: Icon(Icons.keyboard_outlined, size: 18), text: 'Atajos'),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: 620,
          height: 440,
          child: TabBarView(
            children: [
              _buildGeneralTab(theme),
              _buildBitacoraTab(theme),
              _buildShortcutsTab(theme),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
