import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/app_settings.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/ui/settings_dialog.dart';

class FolderIngestionResult {
  final String selectedCamera;
  final CameraType cameraType;
  final List<CameraConfig>? updatedCameras;
  final String? nomenclature;
  final String? date;
  final String? unit;
  final String? reel;
  final bool isAudio;

  const FolderIngestionResult({
    required this.selectedCamera,
    required this.cameraType,
    this.updatedCameras,
    this.nomenclature,
    this.date,
    this.unit,
    this.reel,
    this.isAudio = false,
  });
}

class FolderIngestionDialog extends StatefulWidget {
  final String folderPath;
  final RenombrataProject project;
  final List<ScannedFile> scannedFiles;
  final void Function(RenombrataProject updatedProject)? onManageCameras;

  const FolderIngestionDialog({
    super.key,
    required this.folderPath,
    required this.project,
    required this.scannedFiles,
    this.onManageCameras,
  });

  static Future<FolderIngestionResult?> show({
    required BuildContext context,
    required String folderPath,
    required RenombrataProject project,
    required List<ScannedFile> scannedFiles,
    void Function(RenombrataProject updatedProject)? onManageCameras,
  }) async {
    return showDialog<FolderIngestionResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => FolderIngestionDialog(
        folderPath: folderPath,
        project: project,
        scannedFiles: scannedFiles,
        onManageCameras: onManageCameras,
      ),
    );
  }

  @override
  State<FolderIngestionDialog> createState() => _FolderIngestionDialogState();
}

class _FolderIngestionDialogState extends State<FolderIngestionDialog> {
  late RenombrataProject _project;
  late String _suggestedCam;
  late CameraType _suggestedType;
  late String _selectedCamera;
  late CameraType _selectedType;

  // Fresh start wizard state
  bool _isAudio = false;
  late TextEditingController _cameraNameController;
  late TextEditingController _nomenclatureController;
  late TextEditingController _dateController;
  late TextEditingController _unitController;
  late TextEditingController _reelController;

  bool get _hasBitacora => _project.log.records.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _project = widget.project;

    final detected = _detectCameraFromFiles(widget.scannedFiles);
    _suggestedCam = detected.$1;
    _suggestedType = detected.$2;

    _selectedCamera = _suggestedCam;
    _selectedType = _suggestedType;

    final inProject = _project.cameras.any(
      (c) => c.name.toUpperCase() == _selectedCamera.toUpperCase(),
    );
    if (inProject) {
      _selectedType = _project.getCameraType(_selectedCamera);
    }

    _cameraNameController = TextEditingController(text: _selectedCamera);

    // Initial production metadata
    final folderBase = p.basename(widget.folderPath);
    final rawNomen = _project.log.metadata.nomenclature.trim().isNotEmpty
        ? _project.log.metadata.nomenclature.trim()
        : (_project.log.metadata.production.trim().isNotEmpty
            ? _project.log.metadata.production.trim()
            : _cleanFolderNomenclature(folderBase));
    _nomenclatureController = TextEditingController(text: rawNomen);

    final rawDate = _project.log.metadata.date.trim().isNotEmpty
        ? _project.log.metadata.date.trim()
        : _currentDateFormatted();
    _dateController = TextEditingController(text: rawDate);

    final autoUnit = _selectedType == CameraType.drivingShot ? 'DS' : 'U1';
    _unitController = TextEditingController(text: autoUnit);

    final autoReel = _computeAutoReel(_selectedCamera, _selectedType);
    _reelController = TextEditingController(text: autoReel);
  }

  @override
  void dispose() {
    _cameraNameController.dispose();
    _nomenclatureController.dispose();
    _dateController.dispose();
    _unitController.dispose();
    _reelController.dispose();
    super.dispose();
  }

  String _currentDateFormatted() {
    final now = DateTime.now();
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    final y = (now.year % 100).toString().padLeft(2, '0');
    return '$d$m$y';
  }

  String _cleanFolderNomenclature(String folderName) {
    final clean = folderName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    return clean.isNotEmpty ? clean.toUpperCase() : 'PROD';
  }

  String _computeAutoReel(String camName, CameraType type) {
    if (type == CameraType.drivingShot ||
        type == CameraType.goPro ||
        type == CameraType.drone) {
      return '01';
    }
    final cleanCam = camName.trim().toUpperCase();
    return cleanCam.isNotEmpty ? '${cleanCam}001' : 'A001';
  }

  static (String, CameraType) _detectCameraFromFiles(List<ScannedFile> files) {
    for (final f in files) {
      final name = f.basename.toUpperCase();
      if (name.contains('DJI_') ||
          name.startsWith('DJI') ||
          name.contains('_DR_') ||
          name.startsWith('DR')) {
        return ('DR', CameraType.drone);
      }
      if (name.contains('GOPR') ||
          name.contains('GH0') ||
          name.contains('GX0') ||
          name.contains('_GPR_') ||
          name.startsWith('GPR')) {
        return ('GPR', CameraType.goPro);
      }
      final cam = ClipMatcherService.extractCamera(f.basename, fallback: '');
      if (cam.isNotEmpty) {
        return (cam, CameraType.regular);
      }
    }
    return ('A', CameraType.regular);
  }

  void _onFreshCameraTypeChanged(CameraType newType) {
    setState(() {
      _selectedType = newType;
      if (newType == CameraType.drivingShot) {
        _unitController.text = 'DS';
      } else if (_unitController.text == 'DS') {
        _unitController.text = 'U1';
      }
      _reelController.text = _computeAutoReel(
        _cameraNameController.text,
        newType,
      );
    });
  }

  void _onFreshCameraNameChanged(String newName) {
    _selectedCamera = newName.trim().toUpperCase();
    _reelController.text = _computeAutoReel(_selectedCamera, _selectedType);
  }

  Future<void> _openManageCameras() async {
    await showDialog(
      context: context,
      builder: (ctx) => SettingsDialog(
        currentSettings: const AppSettings(),
        project: _project,
        onSettingsChanged: (_) {},
        onProjectChanged: (updated) {
          setState(() {
            _project = updated;
            if (!_project.cameras.any((c) => c.name == _selectedCamera)) {
              if (_project.cameras.isNotEmpty) {
                _selectedCamera = _project.cameras.first.name;
                _selectedType = _project.cameras.first.type;
              }
            }
          });
          widget.onManageCameras?.call(updated);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _hasBitacora
              ? _buildExistingBitacoraContent(theme, isDark)
              : _buildFreshStartContent(theme, isDark),
        ),
      ),
    );
  }

  Widget _buildExistingBitacoraContent(ThemeData theme, bool isDark) {
    final folderName = p.basename(widget.folderPath);
    final mediaCount = widget.scannedFiles.where((f) => f.isVideo || f.isAudio).length;

    // Ensure all cameras exist in dropdown, even if suggestedCam is not yet saved
    final cameraList = List<CameraConfig>.from(_project.cameras);
    if (!cameraList.any((c) => c.name.toUpperCase() == _selectedCamera.toUpperCase())) {
      cameraList.add(CameraConfig(name: _selectedCamera, type: _selectedType));
    }

    return SingleChildScrollView(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.video_camera_back, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Confirmar Cámara de la Carpeta',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Revisa y confirma la cámara a la que corresponden los clips importados.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[850] : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  folderName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$mediaCount clips detectados',
                style: TextStyle(color: theme.hintColor, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cámara sugerida: Cámara $_suggestedCam (${_suggestedType.label})',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          key: const ValueKey('folder_camera_selector'),
          value: _selectedCamera,
          decoration: const InputDecoration(
            labelText: 'Cámara Asignada',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: cameraList.map((c) {
            return DropdownMenuItem<String>(
              value: c.name,
              child: Text('Cámara ${c.name} (${c.type.label})'),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedCamera = val;
                _selectedType = _project.getCameraType(val);
              });
            }
          },
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: const ValueKey('manage_cameras_button'),
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Administrar Cámaras...'),
            onPressed: _openManageCameras,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              key: const ValueKey('accept_import_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
              onPressed: () {
                Navigator.of(context).pop(
                  FolderIngestionResult(
                    selectedCamera: _selectedCamera,
                    cameraType: _selectedType,
                    updatedCameras: _project.cameras,
                  ),
                );
              },
              child: const Text('Aceptar e Importar'),
            ),
          ],
        ),
      ],
    ));
  }

  Widget _buildFreshStartContent(ThemeData theme, bool isDark) {
    final folderName = p.basename(widget.folderPath);
    final mediaCount = widget.scannedFiles.where((f) => f.isVideo || f.isAudio).length;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.settings_suggest, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configurar Lote de Medios',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Carpeta: $folderName ($mediaCount clips)',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Se ha detectado una carpeta de medios pero no hay una bitácora cargada. Configura la información base para el renombrado:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          // Tipo de archivo
          const Text('Tipo de archivo:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                icon: Icon(Icons.videocam_outlined),
                label: Text('Video de Cámara'),
              ),
              ButtonSegment<bool>(
                value: true,
                icon: Icon(Icons.audiotrack_outlined),
                label: Text('Audio Multipista'),
              ),
            ],
            selected: {_isAudio},
            onSelectionChanged: (set) {
              setState(() {
                _isAudio = set.first;
              });
            },
          ),
          const SizedBox(height: 16),
          // Cámara y Tipo de Cámara
          const Text('Cámara:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  key: const ValueKey('fresh_camera_name_field'),
                  controller: _cameraNameController,
                  decoration: const InputDecoration(
                    labelText: 'Cámara',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: _onFreshCameraNameChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<CameraType>(
                  key: const ValueKey('fresh_camera_type_selector'),
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Cámara',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: CameraType.values.map((type) {
                    return DropdownMenuItem<CameraType>(
                      value: type,
                      child: Text(type.label),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) _onFreshCameraTypeChanged(val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Metadatos Base de Producción
          const Text('Metadatos Base de Producción:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('fresh_nomen_field'),
                  controller: _nomenclatureController,
                  decoration: const InputDecoration(
                    labelText: 'Nomenclatura (PROD)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('fresh_date_field'),
                  controller: _dateController,
                  decoration: const InputDecoration(
                    labelText: 'Fecha (DDMMYY)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('fresh_unit_field'),
                  controller: _unitController,
                  decoration: const InputDecoration(
                    labelText: 'Unidad',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const ValueKey('fresh_reel_field'),
                  controller: _reelController,
                  decoration: const InputDecoration(
                    labelText: 'Reel',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                key: const ValueKey('fresh_start_confirm_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
                onPressed: () {
                  final camName = _cameraNameController.text.trim().isNotEmpty
                      ? _cameraNameController.text.trim().toUpperCase()
                      : 'A';
                  Navigator.of(context).pop(
                    FolderIngestionResult(
                      selectedCamera: camName,
                      cameraType: _selectedType,
                      nomenclature: _nomenclatureController.text.trim(),
                      date: _dateController.text.trim(),
                      unit: _unitController.text.trim(),
                      reel: _reelController.text.trim(),
                      isAudio: _isAudio,
                    ),
                  );
                },
                child: const Text('Iniciar Proyecto con estos Medios'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

