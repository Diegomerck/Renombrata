import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/proforma_dl_metadata.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/services/proforma_dl_service.dart';

/// Interactive dialog for inspecting detected media clips, reviewing/editing
/// batch metadata defaults, and generating strict DigitalLogic 3.2 Proforma_DL XML sidecars.
class ProformaDlXmlDialog extends StatefulWidget {
  final String? initialFolderPath;
  final RenombrataProject project;
  final List<String>? mediaFiles;
  final void Function(int count)? onGenerated;

  const ProformaDlXmlDialog({
    super.key,
    this.initialFolderPath,
    required this.project,
    this.mediaFiles,
    this.onGenerated,
  });

  /// Displays the [ProformaDlXmlDialog].
  static Future<int?> show({
    required BuildContext context,
    String? initialFolderPath,
    required RenombrataProject project,
    List<String>? mediaFiles,
    void Function(int count)? onGenerated,
  }) async {
    return showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ProformaDlXmlDialog(
        initialFolderPath: initialFolderPath,
        project: project,
        mediaFiles: mediaFiles,
        onGenerated: onGenerated,
      ),
    );
  }

  @override
  State<ProformaDlXmlDialog> createState() => _ProformaDlXmlDialogState();
}

class _ProformaDlXmlDialogState extends State<ProformaDlXmlDialog> {
  String? _currentFolder;
  final List<ProformaDlMetadata> _clips = [];
  bool _isLoading = false;
  String? _statusMessage;
  bool _isStatusError = false;

  // Batch Defaults Controllers
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
  void initState() {
    super.initState();
    _currentFolder = widget.initialFolderPath;

    final meta = widget.project.log.metadata;
    _operadorController = TextEditingController(
      text: meta.ingestor.isNotEmpty ? meta.ingestor : 'ANGEL ESTRADA DIAZ',
    );
    _paisController = TextEditingController(text: 'MEXICO');
    _ciudadController = TextEditingController(text: 'CDMX');
    _lugarController = TextEditingController(
      text: meta.location.isNotEmpty ? meta.location : 'TERMINAL DE AUTOBUSES DEL SUR',
    );
    _videoObsController = TextEditingController(text: 'OK SLOG 3');
    _audioObsController = TextEditingController(text: 'MIX Y MULTITRACK');
    _sinopsisController = TextEditingController(text: 'LLEGA INOCENCIA EN AUTOBUS');
    _fuenteController = TextEditingController(text: 'Portátil');
    _descripcionVfxController = TextEditingController(text: '');
    _cardNumberController = TextEditingController(text: '1');
    _unitSubIdController = TextEditingController(text: 'U14B');

    _loadClips();
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
    if (widget.mediaFiles != null && widget.mediaFiles!.isNotEmpty) {
      filePaths = List.from(widget.mediaFiles!);
    } else if (_currentFolder != null && Directory(_currentFolder!).existsSync()) {
      final scanned = MediaScannerService.scanDirectory(
        _currentFolder!,
        searchSubdirectories: false,
      );
      filePaths = scanned
          .where((f) => f.isPrimaryVideo || f.isVideo)
          .map((f) => f.path)
          .toList();
    }

    // Sort files naturally by filename
    filePaths.sort((a, b) => p.basename(a).compareTo(p.basename(b)));

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

      // Overwrite cardNumber / unitSubId if customized
      final customSub = ProformaDlService.buildSubConvention(
        cardNumber: _cardNumberController.text.trim().isNotEmpty
            ? _cardNumberController.text.trim()
            : item.cardNumber,
        clipSequenceNumber: i + 1,
        day: item.day,
        unitSubId: _unitSubIdController.text.trim().isNotEmpty
            ? _unitSubIdController.text.trim()
            : item.unitSubId,
      );
      item.subConvention = customSub;
      item.convencionNombre = ProformaDlService.buildFullConvention(
        clipName: item.clipName,
        subConvention: customSub,
      );

      _clips.add(item);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickFolder() async {
    try {
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: 'Seleccionar carpeta con archivos de video',
      );
      if (selected != null) {
        setState(() {
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

  void _applyBatchDefaultsToAll() {
    for (int i = 0; i < _clips.length; i++) {
      final item = _clips[i];
      item.operadorIngesta = _operadorController.text;
      item.pais = _paisController.text;
      item.ciudad = _ciudadController.text;
      item.ubicacion = _ubicacion;
      item.temporalidad = _temporalidad;
      item.fuente = _fuenteController.text;
      item.observacionesVideo = _videoObsController.text;
      item.observacionesAudio = _audioObsController.text;
      item.lugar = _lugarController.text;
      item.sinopsis = _sinopsisController.text;
      item.vfxCompuestos = _vfxCompuestos;
      item.descripcionVfx = _descripcionVfxController.text;

      final cardNum = _cardNumberController.text.trim().isNotEmpty
          ? _cardNumberController.text.trim()
          : item.cardNumber;
      final unitSub = _unitSubIdController.text.trim().isNotEmpty
          ? _unitSubIdController.text.trim()
          : item.unitSubId;

      final sub = ProformaDlService.buildSubConvention(
        cardNumber: cardNum,
        clipSequenceNumber: i + 1,
        day: item.day,
        unitSubId: unitSub,
      );
      item.subConvention = sub;
      item.convencionNombre = ProformaDlService.buildFullConvention(
        clipName: item.clipName,
        subConvention: sub,
      );
    }
    setState(() {
      _statusMessage = 'Se aplicaron los valores por lote a los ${_clips.length} clips.';
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
        _statusMessage = '¡Éxito! Se generaron ${results.length} archivos XML sidecar.';
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
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? const Color(0xFF282832) : const Color(0xFFCBD5E1),
        ),
      ),
      child: SizedBox(
        width: 1080,
        height: 750,
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
                      color: const Color(0xFF6366F1).withOpacity(0.12),
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
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Folder selection bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF16161A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF2E2E38) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_special, size: 20, color: Color(0xFF6366F1)),
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
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Cambiar Carpeta'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: _pickFolder,
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withOpacity(0.15),
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

              // Batch Defaults Accordion / Panel
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF16161A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF2E2E38) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune, size: 16, color: Color(0xFF6366F1)),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Valores por Lote (Metadatos Generales y Sub-convención %)',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.sync, size: 15),
                          label: const Text('Aplicar a todos los clips'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: _applyBatchDefaultsToAll,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Row 1
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildSmallTextField('Operador Ingesta', _operadorController),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _buildSmallTextField('País', _paisController),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _buildSmallTextField('Ciudad', _ciudadController),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: _buildSmallTextField('Lugar', _lugarController),
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
                            onChanged: (val) => setState(() => _ubicacion = val!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _buildDropdown(
                            label: 'Temporalidad',
                            value: _temporalidad,
                            items: const ['Día', 'Noche'],
                            onChanged: (val) => setState(() => _temporalidad = val!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _buildSmallTextField('Fuente', _fuenteController),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _buildDropdown(
                            label: 'VFX Compuestos',
                            value: _vfxCompuestos,
                            items: const ['No', 'Sí'],
                            onChanged: (val) => setState(() => _vfxCompuestos = val!),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _buildSmallTextField('Tarjeta / Reel', _cardNumberController),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: _buildSmallTextField('Sub-Reel / Unidad', _unitSubIdController),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Row 3
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildSmallTextField('Obs. Video', _videoObsController),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: _buildSmallTextField('Obs. Audio', _audioObsController),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 5,
                          child: _buildSmallTextField('Sinopsis Predeterminada', _sinopsisController),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Notification banner if any
              if (_statusMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isStatusError
                        ? Colors.red.shade900.withOpacity(0.2)
                        : Colors.green.shade900.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _isStatusError ? Colors.red.shade400 : Colors.green.shade400,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isStatusError ? Icons.error_outline : Icons.check_circle_outline,
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
                            color: _isStatusError ? Colors.red.shade200 : Colors.green.shade200,
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
                      color: isDark ? const Color(0xFF282832) : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: _clips.isEmpty
                      ? Center(
                          child: Text(
                            'No se detectaron archivos de video en la carpeta seleccionada.',
                            style: TextStyle(
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _clips.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: isDark ? const Color(0xFF282832) : const Color(0xFFF1F5F9),
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
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cerrar'),
                      ),
                      const SizedBox(width: 12),
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'ClipName: ${clip.clipName}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
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
                color: isDark ? const Color(0xFF23232E) : const Color(0xFFEEF2F6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                clip.convencionNombre,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF818CF8) : const Color(0xFF4338CA),
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

  Widget _buildSmallTextField(String label, TextEditingController controller) {
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
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            border: OutlineInputBorder(),
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
          value: value,
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
