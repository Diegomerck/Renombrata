import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:renombrata/src/models/app_settings.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/utils/timecode_formatter.dart';
import 'package:uuid/uuid.dart';

class BitacoraEditorTab extends StatefulWidget {
  final RenombrataProject project;
  final ValueChanged<RenombrataProject> onProjectChanged;
  final AppSettings settings;

  const BitacoraEditorTab({
    super.key,
    required this.project,
    required this.onProjectChanged,
    this.settings = const AppSettings(),
  });

  /// Sorts records by the numeric clip identifier for the active camera.
  /// If clip numbers differ, sorts ascending. If equal or unparseable,
  /// compares [tcIn] if available, otherwise preserves relative order.
  static List<ShotRecord> sortRecordsByClip(List<ShotRecord> records, String activeCamera) {
    final indexed = records.asMap().entries.toList();
    indexed.sort((a, b) {
      final clipStrA = a.value.cameras.where((c) => c.cameraName == activeCamera).firstOrNull?.clipName ?? '';
      final clipStrB = b.value.cameras.where((c) => c.cameraName == activeCamera).firstOrNull?.clipName ?? '';

      final numA = _parseClipNumber(clipStrA);
      final numB = _parseClipNumber(clipStrB);

      if (numA != numB) {
        return numA.compareTo(numB);
      }

      final tcA = a.value.tcIn?.trim() ?? '';
      final tcB = b.value.tcIn?.trim() ?? '';
      if (tcA.isNotEmpty && tcB.isNotEmpty && tcA != tcB) {
        return tcA.compareTo(tcB);
      }

      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList();
  }

  static int _parseClipNumber(String clipStr) {
    if (clipStr.trim().isEmpty) return 999999;
    final extracted = ClipMatcherService.extractClipNumber(clipStr);
    return int.tryParse(extracted) ?? 999999;
  }

  @override
  State<BitacoraEditorTab> createState() => _BitacoraEditorTabState();
}

class _BitacoraEditorTabState extends State<BitacoraEditorTab> {
  bool _isHeaderExpanded = true;
  List<({int index, ShotRecord record})>? _lastDeletedRecords;
  final Set<String> _expandedRecordIds = {};
  final Set<String> _selectedRecordIds = {};

  final ScrollController _scrollController = ScrollController();

  late final TextEditingController _productionController;
  late final TextEditingController _nomenclatureController;
  late final TextEditingController _dateController;
  late final TextEditingController _dayController;
  late final TextEditingController _unitController;
  late final TextEditingController _locationController;
  late final TextEditingController _producerController;
  late final TextEditingController _responsibleEngineerController;
  late final TextEditingController _ingestorController;
  late final TextEditingController _frameRateController;
  late final TextEditingController _videoCodecController;
  late final TextEditingController _audioFormatController;

  @override
  void initState() {
    super.initState();
    final meta = widget.project.log.metadata;
    _productionController = TextEditingController(text: meta.production);
    _nomenclatureController = TextEditingController(text: meta.nomenclature);
    _dateController = TextEditingController(text: meta.date);
    _dayController = TextEditingController(text: meta.day);
    _unitController = TextEditingController(text: meta.unit);
    _locationController = TextEditingController(text: meta.location);
    _producerController = TextEditingController(text: meta.producer);
    _responsibleEngineerController = TextEditingController(text: meta.responsibleEngineer);
    _ingestorController = TextEditingController(text: meta.ingestor);
    _frameRateController = TextEditingController(text: meta.frameRate);
    _videoCodecController = TextEditingController(text: meta.videoCodec);
    _audioFormatController = TextEditingController(text: meta.audioFormat);
  }

  @override
  void didUpdateWidget(BitacoraEditorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.log.metadata.production != widget.project.log.metadata.production || 
        oldWidget.project.log.metadata.date != widget.project.log.metadata.date) {
      _lastDeletedRecords = null;
      _expandedRecordIds.clear();
      _selectedRecordIds.clear();
    }

    final meta = widget.project.log.metadata;
    void syncController(TextEditingController controller, String value) {
      if (controller.text != value) {
        controller.text = value;
      }
    }

    syncController(_productionController, meta.production);
    syncController(_nomenclatureController, meta.nomenclature);
    syncController(_dateController, meta.date);
    syncController(_dayController, meta.day);
    syncController(_unitController, meta.unit);
    syncController(_locationController, meta.location);
    syncController(_producerController, meta.producer);
    syncController(_responsibleEngineerController, meta.responsibleEngineer);
    syncController(_ingestorController, meta.ingestor);
    syncController(_frameRateController, meta.frameRate);
    syncController(_videoCodecController, meta.videoCodec);
    syncController(_audioFormatController, meta.audioFormat);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _productionController.dispose();
    _nomenclatureController.dispose();
    _dateController.dispose();
    _dayController.dispose();
    _unitController.dispose();
    _locationController.dispose();
    _producerController.dispose();
    _responsibleEngineerController.dispose();
    _ingestorController.dispose();
    _frameRateController.dispose();
    _videoCodecController.dispose();
    _audioFormatController.dispose();
    super.dispose();
  }

  Future<void> _deleteSingleRecord(int index, ShotRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar toma?'),
        content: Text('¿Estás seguro de que deseas eliminar la Toma ${record.take} (Escena ${record.scene})? Podrás recuperarla usando "Deshacer eliminación".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _lastDeletedRecords = [(index: index, record: record)];
        _expandedRecordIds.remove(record.id);
        _selectedRecordIds.remove(record.id);
      });
      final newRecords = List<ShotRecord>.from(widget.project.log.records);
      newRecords.removeAt(index);
      _updateRecords(newRecords);
    }
  }

  Future<void> _deleteSelectedRecords() async {
    final count = _selectedRecordIds.length;
    if (count == 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar tomas seleccionadas?'),
        content: Text('¿Eliminar $count tomas seleccionadas? Podrás recuperarlas usando "Deshacer eliminación".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final records = widget.project.log.records;
      final deleted = <({int index, ShotRecord record})>[];
      for (int i = 0; i < records.length; i++) {
        if (_selectedRecordIds.contains(records[i].id)) {
          deleted.add((index: i, record: records[i]));
        }
      }

      setState(() {
        _lastDeletedRecords = deleted;
        for (final item in deleted) {
          _expandedRecordIds.remove(item.record.id);
        }
        _selectedRecordIds.clear();
      });

      final newRecords = records.where((r) => !deleted.any((d) => d.record.id == r.id)).toList();
      _updateRecords(newRecords);
    }
  }

  void _updateMetadata(ShootingLogMetadata newMetadata) {
    final updatedLog = widget.project.log.copyWith(metadata: newMetadata);
    widget.onProjectChanged(widget.project.copyWith(log: updatedLog));
  }

  void _updateRecords(List<ShotRecord> newRecords) {
    final updatedLog = widget.project.log.copyWith(records: newRecords);
    widget.onProjectChanged(widget.project.copyWith(log: updatedLog));
  }

  void _reorderRecordsByClip() {
    final sorted = BitacoraEditorTab.sortRecordsByClip(
      widget.project.log.records,
      widget.project.activeCamera,
    );
    _updateRecords(sorted);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeaderCard(),
        Expanded(
          child: _buildDataGrid(),
        ),
        _buildFooterActions(),
      ],
    );
  }

  Widget _buildHeaderCard() {
    final meta = widget.project.log.metadata;

    return Card(
      margin: const EdgeInsets.all(16),
      child: ExpansionTile(
        title: const Text('Metadata de Producción', style: TextStyle(fontWeight: FontWeight.bold)),
        initiallyExpanded: _isHeaderExpanded,
        onExpansionChanged: (expanded) {
          setState(() {
            _isHeaderExpanded = expanded;
          });
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double width = constraints.maxWidth > 900 ? constraints.maxWidth : 900;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints.tightFor(width: width),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildTextField('Producción', _productionController, (v) => _updateMetadata(meta.copyWith(production: v)))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField('Nomenclatura', _nomenclatureController, (v) => _updateMetadata(meta.copyWith(nomenclature: v)))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField('Fecha (DDMMAA)', _dateController, (v) => _updateMetadata(meta.copyWith(date: v)))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField('Día de grabación', _dayController, (v) => _updateMetadata(meta.copyWith(day: v)))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildTextField('Unidad', _unitController, (v) => _updateMetadata(meta.copyWith(unit: v)))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField('Locación', _locationController, (v) => _updateMetadata(meta.copyWith(location: v)))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField('Productor', _producerController, (v) => _updateMetadata(meta.copyWith(producer: v)))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField('Ing. Responsable', _responsibleEngineerController, (v) => _updateMetadata(meta.copyWith(responsibleEngineer: v)))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildTextField('Ingestador', _ingestorController, (v) => _updateMetadata(meta.copyWith(ingestor: v)))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildFrameRateDropdown(meta.frameRate, (v) => _updateMetadata(meta.copyWith(frameRate: v ?? '23.98')))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildVideoCodecAutocomplete(_videoCodecController, (v) => _updateMetadata(meta.copyWith(videoCodec: v)))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildTextField('Audio Format', _audioFormatController, (v) => _updateMetadata(meta.copyWith(audioFormat: v)))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _showCameraConfigDialog,
                            icon: const Icon(Icons.videocam),
                            label: const Text('Configurar Cámaras'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, ValueChanged<String> onChanged) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildVideoCodecAutocomplete(TextEditingController controller, ValueChanged<String> onChanged) {
    const options = [
      'XDCAM HD422 (50 Mbps)',
      'XAVC Intra',
      'XAVC Long GOP',
      'ProRes 422 HQ',
      'ProRes 422',
      'ProRes 422 LT',
      'ProRes 4444',
      'Sony X-OCN',
      'ARRIRAW',
      'REDCODE RAW (R3D)',
      'Cinema RAW Light (CRM)',
      'Blackmagic RAW (BRAW)',
      'DNxHD',
      'DNxHR',
      'H.264 (AVC)',
      'H.265 (HEVC)',
    ];

    return Autocomplete<String>(
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text == '') {
          return const Iterable<String>.empty();
        }
        return options.where((String option) {
          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (String selection) {
        controller.text = selection;
        onChanged(selection);
      },
      fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
        if (fieldTextEditingController.text != controller.text) {
          fieldTextEditingController.text = controller.text;
        }
        return Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) {
              controller.text = fieldTextEditingController.text;
              onChanged(fieldTextEditingController.text);
            }
          },
          child: TextFormField(
            controller: fieldTextEditingController,
            focusNode: fieldFocusNode,
            decoration: const InputDecoration(
              labelText: 'Video Codec',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (val) {
              controller.text = val;
              onChanged(val);
            },
            onFieldSubmitted: (String value) {
              onFieldSubmitted();
              controller.text = value;
              onChanged(value);
            },
          ),
        );
      },
    );
  }

  Widget _buildFrameRateDropdown(String value, ValueChanged<String?> onChanged) {
    const options = ['23.98', '24', '25', '29.97nd', '29.97df', '30nd', '30df'];
    final effectiveValue = options.contains(value) ? value : '23.98';

    return DropdownButtonFormField<String>(
      key: ValueKey('frame_rate_$effectiveValue'),
      initialValue: effectiveValue,
      decoration: const InputDecoration(
        labelText: 'Frame Rate',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
      onChanged: (v) {
        _frameRateController.text = v ?? '';
        onChanged(v);
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addNewRecord() {
    final newRecord = ShotRecord(
      chapter: '',
      scene: '',
      plane: '',
      take: '',
      cameras: [],
      reel: widget.project.defaultReel.isNotEmpty ? widget.project.defaultReel : '001',
    );
    final newRecords = List<ShotRecord>.from(widget.project.log.records);
    newRecords.add(newRecord);
    setState(() {
      _expandedRecordIds.clear();
      _expandedRecordIds.add(newRecord.id);
    });
    _updateRecords(newRecords);
    _scrollToBottom();
  }

  void _duplicateLastRecord() {
    final records = widget.project.log.records;
    if (records.isEmpty) return;

    final lastRecord = records.last;
    // Try to increment take if numeric
    String nextTake = lastRecord.take;
    final takeNum = int.tryParse(nextTake);
    if (takeNum != null) {
      nextTake = (takeNum + 1).toString();
    }

    final duplicated = lastRecord.copyWith(
      id: const Uuid().v4(), // Force new ID
      take: nextTake,
      cameras: [], // Empty cameras for new take
      tcIn: '',
      tcOut: '',
      observations: '',
    );
    final newRecords = List<ShotRecord>.from(records);
    newRecords.add(duplicated);
    setState(() {
      _expandedRecordIds.clear();
      _expandedRecordIds.add(duplicated.id);
    });
    _updateRecords(newRecords);
    _scrollToBottom();
  }

  Widget _buildDataGrid() {
    final records = widget.project.log.records;
    
    if (records.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.movie_filter_outlined, size: 48, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                const Text('No hay tomas en esta bitácora', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Puedes importar una bitácora (.xlsx) o agregar una nueva toma manualmente para comenzar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar Primera Toma'),
                  onPressed: () {
                    _addNewRecord();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    final usePagesStyle = widget.settings.usePagesStyleLayout;

    // Precompute scene cluster boundaries and counts in a single O(N) pass
    final List<bool> isNewSceneList = List<bool>.filled(records.length, false);
    final List<int> sceneTakeCounts = List<int>.filled(records.length, 0);

    if (records.isNotEmpty) {
      int currentClusterStartIndex = 0;
      int currentClusterCount = 0;

      for (int i = 0; i < records.length; i++) {
        final r = records[i];
        final bool isNew = (i == 0) ||
            (records[i - 1].chapter != r.chapter ||
             records[i - 1].scene != r.scene ||
             (records[i - 1].plane ?? '') != (r.plane ?? ''));

        if (isNew) {
          if (i > 0) {
            sceneTakeCounts[currentClusterStartIndex] = currentClusterCount;
          }
          isNewSceneList[i] = true;
          currentClusterStartIndex = i;
          currentClusterCount = 1;
        } else {
          currentClusterCount++;
        }
      }
      sceneTakeCounts[currentClusterStartIndex] = currentClusterCount;
    }

    return Card(
      key: ValueKey('grid_card_${widget.project.cameraNames.join("_")}'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double baseWidth = widget.settings.usePagesStyleLayout ? 640.0 : 880.0;
          final double minGridWidth = baseWidth + (widget.project.cameraNames.length * 88.0);
          final double gridWidth = constraints.maxWidth < minGridWidth ? minGridWidth : constraints.maxWidth;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: gridWidth,
              height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
              child: Column(
                children: [
                  _buildGridHeader(),
                  Expanded(
                    child: ReorderableListView.builder(
                      scrollController: _scrollController,
                      buildDefaultDragHandles: false,
                      itemCount: records.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          final newRecords = List<ShotRecord>.from(records);
                          final item = newRecords.removeAt(oldIndex);
                          newRecords.insert(newIndex, item);
                          _updateRecords(newRecords);
                        });
                      },
                      itemBuilder: (context, index) {
                        return _buildGridRow(
                          index,
                          records[index],
                          isNewScene: isNewSceneList[index],
                          sceneTakeCount: sceneTakeCounts[index],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGridHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final records = widget.project.log.records;
    final allExpanded = records.isNotEmpty && _expandedRecordIds.length == records.length;
    final usePagesStyle = widget.settings.usePagesStyleLayout;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF282832) : const Color(0xFFE2E7F0),
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF383846) : const Color(0xFFCBD2DC))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (usePagesStyle) ...[
            const SizedBox(width: 3),
            const SizedBox(width: 8),
          ],
          const SizedBox(width: 20),
          const SizedBox(width: 32, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          if (!usePagesStyle) ...[
            const SizedBox(width: 55, child: Text('Cap', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            const SizedBox(width: 130, child: Text('Escena', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            const SizedBox(width: 55, child: Text('Plano', style: TextStyle(fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            const SizedBox(width: 60, child: Text('Toma', style: TextStyle(fontWeight: FontWeight.bold))),
          ] else ...[
            const SizedBox(width: 60, child: Text('Toma', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          const SizedBox(width: 8),
          for (var cam in widget.project.cameraNames)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 80, 
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Clip Cam', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 10)),
                    Text('"$cam"', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 75, child: Text('Reel', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          const SizedBox(width: 110, child: Text('TC In', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          const SizedBox(width: 110, child: Text('TC Out', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          const Spacer(),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: Icon(allExpanded ? Icons.unfold_less : Icons.unfold_more),
              tooltip: 'Expandir / Colapsar todas las notas',
              onPressed: () {
                setState(() {
                  if (allExpanded) {
                    _expandedRecordIds.clear();
                  } else {
                    _expandedRecordIds.addAll(records.map((r) => r.id));
                  }
                });
              },
            ),
          ),
          SizedBox(
            width: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Checkbox(
                  key: const ValueKey('master_select_all_checkbox'),
                  tristate: true,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  value: records.isEmpty
                      ? false
                      : (_selectedRecordIds.length == records.length
                          ? true
                          : (_selectedRecordIds.isNotEmpty ? null : false)),
                  onChanged: records.isEmpty
                      ? null
                      : (val) {
                          setState(() {
                            final allSelected = records.isNotEmpty && _selectedRecordIds.length == records.length;
                            if (allSelected) {
                              _selectedRecordIds.clear();
                            } else {
                              _selectedRecordIds.clear();
                              _selectedRecordIds.addAll(records.map((r) => r.id));
                            }
                          });
                        },
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Eliminar tomas seleccionadas',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: _selectedRecordIds.isNotEmpty ? _deleteSelectedRecords : null,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: _selectedRecordIds.isNotEmpty
                            ? Colors.red.shade400
                            : (isDark ? Colors.grey.shade700 : Colors.grey.shade400),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSceneHeaderBanner(ShotRecord record, int sceneTakeCount) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bannerBg = theme.colorScheme.primaryContainer.withValues(alpha: 0.7);
    final bannerBorder = Border.all(
      color: theme.colorScheme.primary,
      width: 1.5,
    );
    final badgeBg = isDark
        ? theme.colorScheme.surface.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.8);
    final badgeBorder = BorderSide(
      color: theme.colorScheme.primary.withValues(alpha: 0.3),
      width: 1,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(8),
        border: bannerBorder,
      ),
      child: Row(
        children: [
          Icon(
            Icons.movie_outlined,
            size: 20,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 10),
          Text(
            'ESCENA ${record.scene.isNotEmpty ? record.scene : 'S/E'}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.fromBorderSide(badgeBorder),
            ),
            child: Text(
              'CAP: ${record.chapter.isNotEmpty ? record.chapter : '—'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.fromBorderSide(badgeBorder),
            ),
            child: Text(
              'PLANO: ${(record.plane != null && record.plane!.isNotEmpty) ? record.plane! : '1'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$sceneTakeCount ${sceneTakeCount == 1 ? 'toma' : 'tomas'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridRow(
    int index, 
    ShotRecord record, {
    required bool isNewScene,
    required int sceneTakeCount,
  }) {
    String getClipForCam(String cam) {
      final camRecord = record.cameras.where((c) => c.cameraName == cam).firstOrNull;
      return camRecord?.clipName ?? '';
    }

    void updateRecord(ShotRecord newRecord) {
      final newRecords = List<ShotRecord>.from(widget.project.log.records);
      newRecords[index] = newRecord;
      _updateRecords(newRecords);
    }

    void updateCam(String camName, String clipName) {
      final updatedCameras = List<CameraTakeRecord>.from(record.cameras);
      final existingIndex = updatedCameras.indexWhere((c) => c.cameraName == camName);
      
      if (clipName.trim().isEmpty) {
        if (existingIndex >= 0) updatedCameras.removeAt(existingIndex);
      } else {
        if (existingIndex >= 0) {
          updatedCameras[existingIndex] = updatedCameras[existingIndex].copyWith(clipName: clipName);
        } else {
          updatedCameras.add(CameraTakeRecord(cameraName: camName, clipName: clipName));
        }
      }
      updateRecord(record.copyWith(cameras: updatedCameras));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEven = index % 2 == 0;
    final isExpanded = _expandedRecordIds.contains(record.id);

    final cardColor = isDark
        ? (isEven ? const Color(0xFF16161B) : const Color(0xFF2C2C36))
        : (isEven ? Colors.white : const Color(0xFFDFE4ED));

    final cardBorderColor = isDark
        ? (isEven ? const Color(0xFF282832) : const Color(0xFF424250))
        : (isEven ? const Color(0xFFCBD2DC) : const Color(0xFFB0B9C7));

    final tier2Color = isDark
        ? (isEven ? const Color(0xFF101014) : const Color(0xFF22222A))
        : (isEven ? const Color(0xFFF1F3F7) : const Color(0xFFD3DAE5));

    final tier2BorderColor = isDark
        ? (isEven ? const Color(0xFF1F1F26) : const Color(0xFF383844))
        : (isEven ? const Color(0xFFCBD2DC) : const Color(0xFFB0B9C7));

    final usePagesStyle = widget.settings.usePagesStyleLayout;

    final cardWidget = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cardBorderColor,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              if (usePagesStyle)
                Container(
                  width: 3,
                  height: 24,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ReorderableDragStartListener(
                index: index,
                child: const SizedBox(width: 20, child: MouseRegion(cursor: SystemMouseCursors.grab, child: Icon(Icons.drag_indicator, color: Colors.grey))),
              ),
              SizedBox(
                width: 32,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      '#${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!usePagesStyle) ...[
                SizedBox(
                  width: 55, 
                  child: _buildGridCell(
                    record.chapter, 
                    (v) => updateRecord(record.copyWith(chapter: v)), 
                    hintText: 'Cap',
                    labelText: 'Cap',
                    key: ValueKey('${record.id}_cap'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 130, 
                  child: _buildGridCell(
                    record.scene, 
                    (v) => updateRecord(record.copyWith(scene: v)), 
                    hintText: 'Escena',
                    labelText: 'Escena',
                    key: ValueKey('${record.id}_scene'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 55, 
                  child: _buildGridCell(
                    record.plane ?? '', 
                    (v) => updateRecord(record.copyWith(plane: v)), 
                    hintText: 'Plano',
                    labelText: 'Plano',
                    key: ValueKey('${record.id}_plane'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60, 
                  child: _buildGridCell(
                    record.take, 
                    (v) => updateRecord(record.copyWith(take: v)), 
                    hintText: 'Toma',
                    labelText: 'Toma',
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: 60, 
                  child: _buildGridCell(
                    record.take, 
                    (v) => updateRecord(record.copyWith(take: v)), 
                    hintText: 'Toma',
                    labelText: 'Toma',
                  ),
                ),
              ],
              const SizedBox(width: 8),
              for (var cam in widget.project.cameraNames)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: SizedBox(
                    width: 80, 
                    child: _buildGridCell(
                      getClipForCam(cam), 
                      (v) => updateCam(cam, v), 
                      hintText: 'Clip $cam',
                      labelText: 'Cam $cam',
                    ),
                  ),
                ),
              SizedBox(
                width: 75, 
                child: _buildGridCell(
                  record.reel, 
                  (v) => updateRecord(record.copyWith(reel: v)), 
                  hintText: 'Reel',
                  labelText: 'Reel',
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110, 
                child: Focus(
                  onFocusChange: (focused) {
                    if (!focused && record.tcIn != null && record.tcIn!.isNotEmpty) {
                      updateRecord(record.copyWith(tcIn: TimecodeUtils.normalize(record.tcIn!, widget.project.log.metadata.frameRate)));
                    }
                  },
                  child: _buildGridCell(
                    record.tcIn ?? '', 
                    (v) => updateRecord(record.copyWith(tcIn: v)), 
                    formatters: [TimecodeTextInputFormatter(widget.project.log.metadata.frameRate)], 
                    hintText: 'TC In (00:00:00:00)',
                    labelText: 'TC In',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110, 
                child: Focus(
                  onFocusChange: (focused) {
                    if (!focused && record.tcOut != null && record.tcOut!.isNotEmpty) {
                      updateRecord(record.copyWith(tcOut: TimecodeUtils.normalize(record.tcOut!, widget.project.log.metadata.frameRate)));
                    }
                  },
                  child: _buildGridCell(
                    record.tcOut ?? '', 
                    (v) => updateRecord(record.copyWith(tcOut: v)), 
                    formatters: [TimecodeTextInputFormatter(widget.project.log.metadata.frameRate)], 
                    hintText: 'TC Out (00:00:00:00)',
                    labelText: 'TC Out',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Spacer(),
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                  tooltip: isExpanded ? 'Colapsar notas' : 'Expandir notas',
                  onPressed: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedRecordIds.remove(record.id);
                      } else {
                        _expandedRecordIds.add(record.id);
                      }
                    });
                  },
                ),
              ),
              SizedBox(
                width: 70,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Checkbox(
                      key: ValueKey('row_checkbox_${record.id}'),
                      value: _selectedRecordIds.contains(record.id),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedRecordIds.add(record.id);
                          } else {
                            _selectedRecordIds.remove(record.id);
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Eliminar toma',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _deleteSingleRecord(index, record),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.delete_outline, size: 16, color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isExpanded)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: tier2Color,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: tier2BorderColor,
                ),
              ),
              child: Row(
                children: [
                  if (usePagesStyle) ...[
                    SizedBox(
                      width: 55,
                      child: _buildGridCell(
                        record.chapter,
                        (v) => updateRecord(record.copyWith(chapter: v)),
                        hintText: 'Cap',
                        labelText: 'Cap',
                        key: ValueKey('${record.id}_tier2_cap'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: _buildGridCell(
                        record.scene,
                        (v) => updateRecord(record.copyWith(scene: v)),
                        hintText: 'Escena',
                        labelText: 'Escena',
                        key: ValueKey('${record.id}_tier2_scene'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 55,
                      child: _buildGridCell(
                        record.plane ?? '',
                        (v) => updateRecord(record.copyWith(plane: v)),
                        hintText: 'Plano',
                        labelText: 'Plano',
                        key: ValueKey('${record.id}_tier2_plane'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: record.isMos,
                        onChanged: (val) => updateRecord(record.copyWith(isMos: val ?? false)),
                        visualDensity: VisualDensity.compact,
                      ),
                      const Text('MOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildGridCell(
                      record.observations ?? '',
                      (v) => updateRecord(record.copyWith(observations: v)),
                      hintText: 'Observaciones / Notas del director',
                      labelText: 'Observaciones / Notas del director',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    if (usePagesStyle && isNewScene) {
      return Column(
        key: ValueKey(record.id),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSceneHeaderBanner(record, sceneTakeCount),
          cardWidget,
        ],
      );
    }

    return KeyedSubtree(
      key: ValueKey(record.id),
      child: cardWidget,
    );
  }

  Widget _buildGridCell(
    String value, 
    ValueChanged<String> onChanged, {
    List<TextInputFormatter>? formatters, 
    String? hintText,
    String? labelText,
    bool isGhosted = false,
    Key? key,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultTextColor = isDark ? Colors.white : Colors.black87;
    final textColor = isGhosted ? Colors.grey.withValues(alpha: 0.3) : defaultTextColor;

    return TextFormField(
      key: key,
      initialValue: isGhosted ? '' : value,
      inputFormatters: formatters,
      decoration: InputDecoration(
        labelText: labelText,
        floatingLabelBehavior: labelText != null ? FloatingLabelBehavior.always : FloatingLabelBehavior.auto,
        floatingLabelStyle: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
        labelStyle: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).hintColor.withValues(alpha: 0.7),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF16161A) : Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF383846) : const Color(0xFFBCC4D2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF383846) : const Color(0xFFBCC4D2),
          ),
        ),
        hintText: isGhosted ? '—' : hintText,
        hintStyle: TextStyle(
          color: isGhosted ? Colors.grey.withValues(alpha: 0.3) : Theme.of(context).hintColor.withValues(alpha: 0.4),
          fontSize: isGhosted ? 12 : 11,
          fontWeight: isGhosted ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
      onChanged: onChanged,
    );
  }

  void _showCameraConfigDialog() {
    List<String> tempCameras = List.from(widget.project.cameraNames);
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Configurar Cámaras'),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < tempCameras.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: tempCameras[i],
                                onChanged: (val) => tempCameras[i] = val,
                                decoration: const InputDecoration(labelText: 'Nombre de cámara', isDense: true),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setStateDialog(() {
                                  tempCameras.removeAt(i);
                                });
                              },
                            )
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar cámara'),
                      onPressed: () {
                        setStateDialog(() {
                          tempCameras.add('CÁMARA ${tempCameras.length + 1}');
                        });
                      },
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    tempCameras.removeWhere((c) => c.trim().isEmpty);
                    if (tempCameras.isEmpty) tempCameras.add('A');
                    
                    final updatedRecords = widget.project.log.records.map((record) {
                      final updatedCameras = List<CameraTakeRecord>.from(record.cameras);
                      for (var cam in tempCameras) {
                        if (!updatedCameras.any((c) => c.cameraName == cam)) {
                          updatedCameras.add(CameraTakeRecord(cameraName: cam, clipName: ''));
                        }
                      }
                      return record.copyWith(cameras: updatedCameras);
                    }).toList();

                    final updatedLog = widget.project.log.copyWith(records: updatedRecords);
                    widget.onProjectChanged(widget.project.copyWith(
                      cameraNames: tempCameras,
                      log: updatedLog,
                    ));
                    setState(() {});
                    Navigator.pop(context);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Widget _buildFooterActions() {
    final records = widget.project.log.records;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: _addNewRecord,
            icon: const Icon(Icons.add),
            label: const Text('Nueva Toma'),
          ),
          ElevatedButton.icon(
            onPressed: records.isEmpty ? null : _duplicateLastRecord,
            icon: const Icon(Icons.copy),
            label: const Text('Duplicar última toma'),
          ),
          Tooltip(
            message: 'Reorganizar todas las tomas según la secuencia numérica de clips',
            child: OutlinedButton.icon(
              icon: const Icon(Icons.sort_by_alpha, size: 16),
              label: const Text('Reordenar por Clip'),
              onPressed: records.isEmpty ? null : _reorderRecordsByClip,
            ),
          ),
          Text(
            '${records.length} tomas registradas',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          ElevatedButton.icon(
            onPressed: (_lastDeletedRecords == null || _lastDeletedRecords!.isEmpty) ? null : () {
              final restoredRecords = List<ShotRecord>.from(widget.project.log.records);
              final itemsToRestore = List<({int index, ShotRecord record})>.from(_lastDeletedRecords!)
                ..sort((a, b) => a.index.compareTo(b.index));

              for (final item in itemsToRestore) {
                if (item.index <= restoredRecords.length) {
                  restoredRecords.insert(item.index, item.record);
                } else {
                  restoredRecords.add(item.record);
                }
              }
              setState(() {
                _lastDeletedRecords = null;
              });
              _updateRecords(restoredRecords);
            },
            icon: const Icon(Icons.undo),
            label: const Text('Deshacer eliminación'),
          ),
        ],
      ),
    );
  }
}
