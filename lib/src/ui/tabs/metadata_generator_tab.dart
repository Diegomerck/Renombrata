import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/proforma_dl_metadata.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/services/proforma_dl_service.dart';

/// Full tab view (and reusable workspace) for DigitalLogic 3.2 / Proforma DL
/// metadata editing, inspection, and XML sidecar generation.
class MetadataGeneratorTab extends StatefulWidget {
  final String? initialFolderPath;
  final RenombrataProject project;
  final List<String>? mediaFiles;
  final void Function(int count)? onGenerated;
  final VoidCallback? onClose;

  const MetadataGeneratorTab({
    super.key,
    this.initialFolderPath,
    required this.project,
    this.mediaFiles,
    this.onGenerated,
    this.onClose,
  });

  @override
  State<MetadataGeneratorTab> createState() => _MetadataGeneratorTabState();
}

class _MetadataGeneratorTabState extends State<MetadataGeneratorTab>
    with AutomaticKeepAliveClientMixin {
  String? _currentFolder;
  List<String>? _customFilePaths;
  bool _useCustomSelection = false;
  final List<ProformaDlMetadata> _clips = [];
  bool _isLoading = false;
  bool _isDragging = false;
  bool _isBatchPanelExpanded = true;
  String? _statusMessage;
  bool _isStatusError = false;

  // Batch Defaults Controllers (neutral/clean defaults)
  late TextEditingController _operadorController;
  late TextEditingController _paisController;
  late TextEditingController _ciudadController;
  late TextEditingController _lugarController;
  late TextEditingController _videoObsController;
  late TextEditingController _audioObsController;
  late TextEditingController _sinopsisController;
  late TextEditingController _fuenteController;
  late TextEditingController _descripcionVfxController;
  late TextEditingController _cardNumberController;
  late TextEditingController _unitSubIdController;

  String _ubicacion = 'Exterior';
  String _temporalidad = 'Día';
  String _vfxCompuestos = 'No';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _currentFolder = widget.initialFolderPath;

    final meta = widget.project.log.metadata;
    _operadorController = TextEditingController(text: meta.ingestor);
    _paisController = TextEditingController(text: 'MEXICO');
    _ciudadController = TextEditingController(text: 'CDMX');
    _lugarController = TextEditingController(text: meta.location);
    _videoObsController = TextEditingController(text: '');
    _audioObsController = TextEditingController(text: '');
    _sinopsisController = TextEditingController(text: '');
    _fuenteController = TextEditingController(text: 'Portátil');
    _descripcionVfxController = TextEditingController(text: '');
    _cardNumberController = TextEditingController(text: '');
    _unitSubIdController = TextEditingController(text: '');

    _loadClips();
  }

  @override
  void didUpdateWidget(covariant MetadataGeneratorTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.project != oldWidget.project) {
      final oldMeta = oldWidget.project.log.metadata;
      final newMeta = widget.project.log.metadata;
      if (_operadorController.text.isEmpty ||
          _operadorController.text == oldMeta.ingestor) {
        _operadorController.text = newMeta.ingestor;
      }
      if (_lugarController.text.isEmpty ||
          _lugarController.text == oldMeta.location) {
        _lugarController.text = newMeta.location;
      }
    }

    final folderChanged = widget.initialFolderPath != oldWidget.initialFolderPath;
    final filesChanged = !_listEquals(widget.mediaFiles, oldWidget.mediaFiles);

    if (!_useCustomSelection && (folderChanged || filesChanged)) {
      _currentFolder = widget.initialFolderPath;
      _loadClips();
    } else if (widget.project != oldWidget.project && !_useCustomSelection) {
      _loadClips();
    }
  }

  bool _listEquals(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _operadorController.dispose();
    _paisController.dispose();
    _ciudadController.dispose();
    _lugarController.dispose();
    _videoObsController.dispose();
    _audioObsController.dispose();
    _sinopsisController.dispose();
    _fuenteController.dispose();
    _descripcionVfxController.dispose();
    _cardNumberController.dispose();
    _unitSubIdController.dispose();
    super.dispose();
  }

  void _loadClips() {
    _clips.clear();

    List<String> filePaths = [];
    if (_useCustomSelection) {
      if (_customFilePaths != null && _customFilePaths!.isNotEmpty) {
        filePaths = List.from(_customFilePaths!);
      } else if (_currentFolder != null &&
          Directory(_currentFolder!).existsSync()) {
        filePaths = _scanVideoPaths(_currentFolder!);
      }
    } else {
      if (widget.mediaFiles != null && widget.mediaFiles!.isNotEmpty) {
        filePaths = List.from(widget.mediaFiles!);
      } else if (_currentFolder != null &&
          Directory(_currentFolder!).existsSync()) {
        filePaths = _scanVideoPaths(_currentFolder!);
      }
    }

    // Sort files naturally by filename
    filePaths.sort((a, b) => p.basename(a).compareTo(p.basename(b)));

    final cardOverride = _cardNumberController.text.trim();
    final unitOverride = _unitSubIdController.text.trim();

    for (int i = 0; i < filePaths.length; i++) {
      final path = filePaths[i];
      final item = ProformaDlService.createMetadata(
        filePath: path,
        clipSequenceNumber: i + 1,
        project: widget.project,
        defaultOperador: _operadorController.text,
        defaultPais: _paisController.text,
        defaultCiudad: _ciudadController.text,
        defaultUbicacion: _ubicacion,
        defaultTemporalidad: _temporalidad,
        defaultVideoObs: _videoObsController.text,
        defaultAudioObs: _audioObsController.text,
        defaultLugar: _lugarController.text,
        defaultSinopsis: _sinopsisController.text,
        defaultVfxCompuestos: _vfxCompuestos,
        defaultDescripcionVfx: _descripcionVfxController.text,
      );
      item.fuente = _fuenteController.text;

      // Apply batch overrides ONLY when explicitly entered by the user
      if (cardOverride.isNotEmpty || unitOverride.isNotEmpty) {
        final customSub = ProformaDlService.buildSubConvention(
          cardNumber: cardOverride.isNotEmpty ? cardOverride : item.cardNumber,
          clipSequenceNumber: i + 1,
          day: item.day,
          unitSubId: unitOverride.isNotEmpty ? unitOverride : item.unitSubId,
        );
        item.subConvention = customSub;
        item.convencionNombre = ProformaDlService.buildFullConvention(
          clipName: item.clipName,
          subConvention: customSub,
        );
      }

      _clips.add(item);
    }

    if (mounted) {
      setState(() {});
    }
  }

  List<String> _scanVideoPaths(String folderPath) {
    final scanned = MediaScannerService.scanDirectory(
      folderPath,
      searchSubdirectories: true,
    );
    final primary = scanned
        .where((f) => f.isPrimaryVideo)
        .map((f) => f.path)
        .toList();
    if (primary.isNotEmpty) return primary;
    return scanned.where((f) => f.isVideo).map((f) => f.path).toList();
  }

  Future<void> _pickFolder() async {
    try {
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: 'Seleccionar carpeta con archivos de video',
      );
      if (selected != null) {
        setState(() {
          _useCustomSelection = true;
          _customFilePaths = null;
          _currentFolder = selected;
          _statusMessage = null;
        });
        _loadClips();
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error al seleccionar carpeta: $e';
        _isStatusError = true;
      });
    }
  }

  void _handleDrop(List<dynamic> files) {
    if (files.isEmpty) return;

    final droppedPaths = files
        .map((f) => (f.path as String?)?.trim() ?? '')
        .where((path) => path.isNotEmpty)
        .toList();
    if (droppedPaths.isEmpty) return;

    final dirPath = droppedPaths.cast<String?>().firstWhere(
          (path) => path != null && Directory(path).existsSync(),
          orElse: () => null,
        );

    if (dirPath != null) {
      setState(() {
        _useCustomSelection = true;
        _customFilePaths = null;
        _currentFolder = dirPath;
        _statusMessage = null;
      });
      _loadClips();
      return;
    }

    final videoPaths = droppedPaths.where((path) {
      final scanned = ScannedFile(path);
      return File(path).existsSync() && (scanned.isPrimaryVideo || scanned.isVideo);
    }).toList();

    if (videoPaths.isNotEmpty) {
      setState(() {
        _useCustomSelection = true;
        _customFilePaths = videoPaths;
        _currentFolder = p.dirname(videoPaths.first);
        _statusMessage = null;
      });
      _loadClips();
    }
  }

  void _applyBatchDefaultsToAll() {
    ProformaDlService.applyBatchDefaults(
      items: _clips,
      operador: _operadorController.text,
      pais: _paisController.text,
      ciudad: _ciudadController.text,
      ubicacion: _ubicacion,
      temporalidad: _temporalidad,
      fuente: _fuenteController.text,
      videoObs: _videoObsController.text,
      audioObs: _audioObsController.text,
      lugar: _lugarController.text,
      sinopsis: _sinopsisController.text,
      vfxCompuestos: _vfxCompuestos,
      descripcionVfx: _descripcionVfxController.text,
      cardNumberOverride: _cardNumberController.text,
      unitSubIdOverride: _unitSubIdController.text,
    );

    setState(() {
      _statusMessage =
          'Se aplicaron los valores por lote a los ${_clips.length} clips.';
      _isStatusError = false;
    });
  }

  Future<void> _generateAllSidecars() async {
    if (_clips.isEmpty) {
      setState(() {
        _statusMessage = 'No hay clips cargados para generar XML.';
        _isStatusError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final results = await ProformaDlService.batchGenerateSidecars(
        items: _clips,
        overwrite: true,
      );

      setState(() {
        _isLoading = false;
        _statusMessage =
            '¡Éxito! Se generaron ${results.length} archivos XML sidecar.';
        _isStatusError = false;
      });

      widget.onGenerated?.call(results.length);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error al generar archivos XML: $e';
        _isStatusError = true;
      });
    }
  }

  void _showXmlPreview(ProformaDlMetadata item) {
    final xmlContent = ProformaDlService.generateXml(item);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.code, color: Color(0xFF6366F1)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'XML Proforma_DL: ${item.originalFileName}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 480,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: SingleChildScrollView(
              child: Text(
                xmlContent,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                  color: Color(0xFF38BDF8),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_all),
            label: const Text('Copiar al Portapapeles'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: xmlContent));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('XML copiado al portapapeles')),
              );
            },
          ),
          FilledButton(
            child: const Text('Cerrar'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _handleDrop(details.files);
      },
      child: Stack(
        children: [
          Padding(
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
                        color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.data_object_rounded,
                        color: Color(0xFF6366F1),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Generador de Metadatos XML (DigitalLogic 3.2 / Proforma DL)',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Genera sidecars XML estrictamente compatibles con la norma de post-producción Televisa / ViX.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onClose != null)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: widget.onClose,
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                // Folder selection bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF16161A)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF2E2E38)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.folder_special,
                        size: 20,
                        color: Color(0xFF6366F1),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentFolder ?? 'Ninguna carpeta seleccionada',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _currentFolder != null
                                ? (isDark ? Colors.white : Colors.black87)
                                : Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('metadata_pick_folder_button'),
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: Text(
                          _currentFolder == null
                              ? 'Seleccionar Carpeta'
                              : 'Cambiar Carpeta',
                        ),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: _pickFolder,
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF6366F1).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_clips.length} clips detectados',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Collapsible Batch Defaults Panel
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF16161A)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF2E2E38)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.tune,
                            size: 16,
                            color: Color(0xFF6366F1),
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Valores por Lote',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isBatchPanelExpanded) ...[
                            const SizedBox(width: 8),
                            FilledButton.tonalIcon(
                              icon: const Icon(Icons.sync, size: 15),
                              label: const Text('Aplicar a todos los clips'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                              onPressed: _applyBatchDefaultsToAll,
                            ),
                          ],
                          const SizedBox(width: 4),
                          IconButton(
                            key: const ValueKey('toggle_batch_panel_button'),
                            icon: Icon(
                              _isBatchPanelExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 20,
                            ),
                            tooltip: _isBatchPanelExpanded
                                ? 'Contraer panel'
                                : 'Expandir panel',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() {
                              _isBatchPanelExpanded = !_isBatchPanelExpanded;
                            }),
                          ),
                        ],
                      ),
                      if (_isBatchPanelExpanded) ...[
                        const SizedBox(height: 10),
                        // Row 1
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildSmallTextField(
                                'Operador Ingesta',
                                _operadorController,
                                hintText: 'Nombre del operador',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: _buildSmallTextField(
                                'País',
                                _paisController,
                                hintText: 'MEXICO',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: _buildSmallTextField(
                                'Ciudad',
                                _ciudadController,
                                hintText: 'CDMX',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: _buildSmallTextField(
                                'Lugar',
                                _lugarController,
                                hintText: 'Locación o set',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Row 2
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildDropdown(
                                label: 'Ubicación',
                                value: _ubicacion,
                                items: const ['Exterior', 'Interior'],
                                onChanged: (val) =>
                                    setState(() => _ubicacion = val!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: _buildDropdown(
                                label: 'Temporalidad',
                                value: _temporalidad,
                                items: const ['Día', 'Noche'],
                                onChanged: (val) =>
                                    setState(() => _temporalidad = val!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: _buildSmallTextField(
                                'Fuente',
                                _fuenteController,
                                hintText: 'Portátil',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: _buildDropdown(
                                label: 'VFX Compuestos',
                                value: _vfxCompuestos,
                                items: const ['No', 'Sí'],
                                onChanged: (val) =>
                                    setState(() => _vfxCompuestos = val!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: _buildSmallTextField(
                                'Tarjeta / Reel',
                                _cardNumberController,
                                hintText: 'Auto (de cámara)',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: _buildSmallTextField(
                                'Sub-Reel / Unidad',
                                _unitSubIdController,
                                hintText: 'Auto (de unidad)',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Row 3
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildSmallTextField(
                                'Obs. Video',
                                _videoObsController,
                                hintText: 'Notas de video',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: _buildSmallTextField(
                                'Obs. Audio',
                                _audioObsController,
                                hintText: 'Notas de audio',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: _buildSmallTextField(
                                'Sinopsis Predeterminada',
                                _sinopsisController,
                                hintText: 'Descripción de la toma',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: _buildSmallTextField(
                                'Descripción VFX',
                                _descripcionVfxController,
                                hintText: 'Detalle VFX',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Notification banner if any
                if (_statusMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _isStatusError
                          ? (isDark
                              ? Colors.red.shade900.withValues(alpha: 0.25)
                              : Colors.red.shade50)
                          : (isDark
                              ? Colors.green.shade900.withValues(alpha: 0.25)
                              : Colors.green.shade50),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _isStatusError
                            ? Colors.red.shade400
                            : Colors.green.shade400,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isStatusError
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          size: 18,
                          color: _isStatusError ? Colors.red : Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _isStatusError
                                  ? (isDark
                                      ? Colors.red.shade200
                                      : Colors.red.shade900)
                                  : (isDark
                                      ? Colors.green.shade200
                                      : Colors.green.shade900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Clips Table
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF16161A) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF282832)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: _clips.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.video_library_outlined,
                                  size: 42,
                                  color: isDark
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'No se detectaron archivos de video en la carpeta seleccionada.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.grey.shade300
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Arrastra una carpeta de medios aquí o presiona "Seleccionar Carpeta".',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.grey.shade500
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _clips.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              color: isDark
                                  ? const Color(0xFF282832)
                                  : const Color(0xFFF1F5F9),
                            ),
                            itemBuilder: (context, index) {
                              final clip = _clips[index];
                              return _buildClipRow(clip, index, isDark);
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                // Bottom Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_clips.length} sidecars listos para generar.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                    Row(
                      children: [
                        if (widget.onClose != null) ...[
                          OutlinedButton(
                            onPressed: widget.onClose,
                            child: const Text('Cerrar'),
                          ),
                          const SizedBox(width: 12),
                        ],
                        FilledButton.icon(
                          key: const ValueKey('generate_sidecars_confirm_button'),
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_as_rounded),
                          label: const Text('Generar XMLs Sidecar'),
                          onPressed: _isLoading || _clips.isEmpty
                              ? null
                              : _generateAllSidecars,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isDragging)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF6366F1).withValues(alpha: 0.14),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E24) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF6366F1),
                        width: 2,
                      ),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.drive_folder_upload_rounded,
                          size: 40,
                          color: Color(0xFF6366F1),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Suelta la carpeta de medios para generar metadatos XML',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClipRow(ProformaDlMetadata clip, int index, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: index % 2 == 1
          ? (isDark ? const Color(0xFF1B1B22) : const Color(0xFFF8FAFC))
          : Colors.transparent,
      child: Row(
        children: [
          // Index
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),

          // Original filename
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clip.originalFileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'ClipName: ${clip.clipName}',
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Full Convention Name (with %)
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF23232E)
                    : const Color(0xFFEEF2F6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                clip.convencionNombre,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF818CF8)
                      : const Color(0xFF4338CA),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Toma Seleccionada Checkbox
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: clip.tomaSeleccionada,
                onChanged: (val) {
                  setState(() {
                    clip.tomaSeleccionada = val ?? true;
                  });
                },
              ),
              Text(
                clip.tomaSeleccionada ? 'SÍ' : 'NO',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: clip.tomaSeleccionada ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // Action: Ver XML
          OutlinedButton.icon(
            icon: const Icon(Icons.code, size: 14),
            label: const Text('Ver XML'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: () => _showXmlPreview(clip),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallTextField(
    String label,
    TextEditingController controller, {
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              fontSize: 11,
              color: Colors.grey.withValues(alpha: 0.7),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        DropdownButtonFormField<String>(
          initialValue: value,
          isDense: true,
          items: items
              .map((it) => DropdownMenuItem(
                    value: it,
                    child: Text(it, style: const TextStyle(fontSize: 12)),
                  ))
              .toList(),
          onChanged: onChanged,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
