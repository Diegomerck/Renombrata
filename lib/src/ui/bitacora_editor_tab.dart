import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:renombrata/src/models/app_settings.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/services/live_timecode_service.dart';
import 'package:renombrata/src/utils/shortcut_utils.dart';
import 'package:renombrata/src/utils/timecode_formatter.dart';
import 'package:uuid/uuid.dart';
import 'settings_dialog.dart';

class BitacoraEditorTab extends StatefulWidget {
  final RenombrataProject project;
  final ValueChanged<RenombrataProject> onProjectChanged;
  final AppSettings settings;
  final ValueChanged<AppSettings>? onSettingsChanged;
  final VoidCallback? onSaveProject;
  final LiveTimecodeService? timecodeService;

  const BitacoraEditorTab({
    super.key,
    required this.project,
    required this.onProjectChanged,
    this.settings = const AppSettings(),
    this.onSettingsChanged,
    this.onSaveProject,
    this.timecodeService,
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
  String? _autofocusFieldId;
  FocusNode? _activeAutofocusNode;
  String? _cutFeedbackMessage;
  Timer? _cutFeedbackTimer;
  int? _editingClusterStartIndex;
  late TextEditingController _inlineCapController;
  late TextEditingController _inlineSceneController;
  late TextEditingController _inlinePlaneController;

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

  late final LiveTimecodeService _timecodeService;
  bool _ownsTimecodeService = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    if (widget.timecodeService != null) {
      _timecodeService = widget.timecodeService!;
      _ownsTimecodeService = false;
    } else {
      _timecodeService = LiveTimecodeService(
        frameRate: widget.project.log.metadata.frameRate,
      );
      _ownsTimecodeService = true;
    }

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
    _inlineCapController = TextEditingController();
    _inlineSceneController = TextEditingController();
    _inlinePlaneController = TextEditingController();
  }

  @override
  void didUpdateWidget(BitacoraEditorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.log.metadata.frameRate != widget.project.log.metadata.frameRate) {
      _timecodeService.updateFrameRate(widget.project.log.metadata.frameRate);
    }

    if (oldWidget.project.log.metadata.production != widget.project.log.metadata.production || 
        oldWidget.project.log.metadata.date != widget.project.log.metadata.date) {
      _lastDeletedRecords = null;
      _expandedRecordIds.clear();
      _selectedRecordIds.clear();
      _editingClusterStartIndex = null;
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
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    _cutFeedbackTimer?.cancel();
    _activeAutofocusNode?.dispose();
    if (_ownsTimecodeService) {
      _timecodeService.dispose();
    }
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
    _inlineCapController.dispose();
    _inlineSceneController.dispose();
    _inlinePlaneController.dispose();
    super.dispose();
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final hasRecords = widget.project.log.records.isNotEmpty;
    final hasDeleted = _lastDeletedRecords != null && _lastDeletedRecords!.isNotEmpty;

    if (_matchesShortcut('new_take', event)) {
      _addNewRecord();
      return true;
    }
    if (_matchesShortcut('stamp_cut', event)) {
      if (hasRecords) {
        _stampCutOnLastRecord();
      }
      return true;
    }
    if (_matchesShortcut('duplicate_take', event)) {
      if (hasRecords) {
        _duplicateLastRecord();
      }
      return true;
    }
    if (_matchesShortcut('undo_delete', event)) {
      if (hasDeleted) {
        _undoLastDeletion();
      }
      return true;
    }
    if (_matchesShortcut('save_project', event)) {
      if (widget.onSaveProject != null) {
        widget.onSaveProject!();
      }
      return true;
    }

    return false;
  }

  bool _matchesShortcut(String actionKey, KeyEvent event) {
    final shortcutStr = widget.settings.shortcuts[actionKey] ?? AppSettings.defaultShortcuts[actionKey];
    if (shortcutStr == null || shortcutStr.isEmpty) return false;
    final activators = ShortcutUtils.parseActivators(shortcutStr);
    for (final activator in activators) {
      if (activator.accepts(event, HardwareKeyboard.instance)) {
        return true;
      }
    }
    return false;
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

  void _updateSetupForCluster(
    int startIndex,
    int count, {
    required String chapter,
    required String scene,
    required String plane,
  }) {
    final allRecords = List<ShotRecord>.from(widget.project.log.records);
    final endIndex = (startIndex + count).clamp(0, allRecords.length);
    for (int i = startIndex; i < endIndex; i++) {
      allRecords[i] = allRecords[i].copyWith(
        chapter: chapter,
        scene: scene,
        plane: plane,
      );
    }
    _updateRecords(allRecords);
  }

  void _reorderRecordsByClip() {
    final sorted = BitacoraEditorTab.sortRecordsByClip(
      widget.project.log.records,
      widget.project.activeCamera,
    );
    _updateRecords(sorted);
  }

  void _undoLastDeletion() {
    if (_lastDeletedRecords == null || _lastDeletedRecords!.isEmpty) return;
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
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: _activeAutofocusNode == null,
      child: Column(
        children: [
          _buildHeaderCard(),
          Expanded(
            child: _buildDataGrid(),
          ),
          _buildFooterActions(),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final meta = widget.project.log.metadata;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _showConfigDialog,
                            icon: const Icon(Icons.tune, size: 18),
                            label: const Text('Configurar', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
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
    final tcIn = _timecodeService.isAutoStampEnabled
        ? _timecodeService.currentFormattedTimecodeZeroFrames
        : '';

    final records = widget.project.log.records;
    String inheritedReel = widget.project.defaultReel.trim().isNotEmpty
        ? widget.project.defaultReel.trim()
        : '001';
    for (int i = records.length - 1; i >= 0; i--) {
      final r = records[i].reel.trim();
      if (r.isNotEmpty) {
        inheritedReel = r;
        break;
      }
    }
    // Normalize inherited reel just in case
    final camMatch = RegExp(r'^[A-Za-z](\d+)$').firstMatch(inheritedReel);
    if (camMatch != null) {
      inheritedReel = camMatch.group(1)!;
    }

    final newRecord = ShotRecord(
      chapter: '',
      scene: '',
      plane: '',
      take: '1',
      cameras: [],
      reel: inheritedReel,
      tcIn: tcIn,
    );
    final newRecords = List<ShotRecord>.from(widget.project.log.records);
    newRecords.add(newRecord);
    final targetField = widget.project.showChapter ? 'cap' : 'scene';
    _activeAutofocusNode?.dispose();
    final focusNode = FocusNode();
    _activeAutofocusNode = focusNode;
    _autofocusFieldId = '${newRecord.id}_$targetField';

    setState(() {
      _expandedRecordIds.clear();
      _expandedRecordIds.add(newRecord.id);
    });
    _updateRecords(newRecords);
    _scrollToBottom();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _activeAutofocusNode == focusNode) {
        focusNode.requestFocus();
        _autofocusFieldId = null;
      }
    });
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

    final tcIn = _timecodeService.isAutoStampEnabled
        ? _timecodeService.currentFormattedTimecodeZeroFrames
        : '';

    String effectiveReel = lastRecord.reel.trim();
    if (effectiveReel.isEmpty) {
      effectiveReel = widget.project.defaultReel.trim().isNotEmpty
          ? widget.project.defaultReel.trim()
          : '001';
      for (int i = records.length - 1; i >= 0; i--) {
        final r = records[i].reel.trim();
        if (r.isNotEmpty) {
          effectiveReel = r;
          break;
        }
      }
    }
    final camMatch = RegExp(r'^[A-Za-z](\d+)$').firstMatch(effectiveReel);
    if (camMatch != null) {
      effectiveReel = camMatch.group(1)!;
    }

    final duplicated = lastRecord.copyWith(
      id: const Uuid().v4(), // Force new ID
      take: nextTake,
      reel: effectiveReel,
      cameras: [], // Empty cameras for new take
      tcIn: tcIn,
      tcOut: '',
      observations: '',
    );
    final newRecords = List<ShotRecord>.from(records);
    newRecords.add(duplicated);
    final targetCam = widget.project.cameraNames.isNotEmpty ? widget.project.cameraNames.first : null;
    final targetFieldId = targetCam != null ? '${duplicated.id}_clip_$targetCam' : '${duplicated.id}_take';

    _activeAutofocusNode?.dispose();
    final focusNode = FocusNode();
    _activeAutofocusNode = focusNode;
    _autofocusFieldId = targetFieldId;

    setState(() {
      _expandedRecordIds.clear();
    });
    _updateRecords(newRecords);
    _scrollToBottom();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _activeAutofocusNode == focusNode) {
        focusNode.requestFocus();
        _autofocusFieldId = null;
      }
    });
  }

  void _stampCutOnLastRecord() {
    final records = widget.project.log.records;
    if (records.isEmpty) return;

    final lastIndex = records.length - 1;
    final lastRecord = records[lastIndex];
    final cutTc = _timecodeService.currentFormattedTimecodeZeroFrames;
    final updatedRecord = lastRecord.copyWith(tcOut: cutTc);

    final newRecords = List<ShotRecord>.from(records);
    newRecords[lastIndex] = updatedRecord;
    _updateRecords(newRecords);

    _cutFeedbackTimer?.cancel();
    setState(() {
      _cutFeedbackMessage = 'TC Out: $cutTc (Toma ${lastRecord.take.isNotEmpty ? lastRecord.take : "#${lastIndex + 1}"})';
    });
    _cutFeedbackTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _cutFeedbackMessage = null;
        });
      }
    });
  }

  Future<void> _showJamSyncDialog() async {
    final currentTc = _timecodeService.currentFormattedTimecode;
    final controller = TextEditingController(text: currentTc);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajustar Código Manual (Jam Sync)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ingresa el código de tiempo maestro (HH:MM:SS:FF) a sincronizar:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              inputFormatters: [TimecodeTextInputFormatter(_timecodeService.frameRate)],
              decoration: const InputDecoration(
                labelText: 'Código Jam',
                hintText: '01:00:00:00',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Sincronizar Jam'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final normalized = TimecodeUtils.normalize(result, _timecodeService.frameRate);
      final parts = normalized.split(':');
      if (parts.length == 4) {
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final s = int.tryParse(parts[2]) ?? 0;
        final f = int.tryParse(parts[3]) ?? 0;
        _timecodeService.jamTimecode(h, m, s, f);
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Jam Sync fijado en: $normalized'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
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

    // Precompute scene cluster boundaries and counts in a single O(N) pass
    final List<bool> isNewSceneList = List<bool>.filled(records.length, false);
    final List<int> sceneTakeCounts = List<int>.filled(records.length, 0);
    final List<int> clusterStartIndices = List<int>.filled(records.length, 0);
    final List<int> clusterCounts = List<int>.filled(records.length, 1);

    if (records.isNotEmpty) {
      int currentClusterStartIndex = 0;
      int currentClusterCount = 0;

      for (int i = 0; i < records.length; i++) {
        final r = records[i];
        bool isNew = (i == 0);
        if (i > 0) {
          final prev = records[i - 1];
          final sameSetup = (r.chapter == prev.chapter &&
                             r.scene == prev.scene &&
                             (r.plane ?? '') == (prev.plane ?? ''));

          // If chapter and scene are both empty, do not merge into the previous scene
          // unless both takes share the same setup identity or non-empty scene.
          if (r.chapter.isEmpty && r.scene.isEmpty) {
            isNew = true; // Every fresh unassigned "Nueva Toma" gets its own separator banner
          } else {
            isNew = !sameSetup;
          }
        }

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
        clusterStartIndices[i] = currentClusterStartIndex;
      }
      sceneTakeCounts[currentClusterStartIndex] = currentClusterCount;

      for (int i = 0; i < records.length; i++) {
        clusterCounts[i] = sceneTakeCounts[clusterStartIndices[i]];
      }
    }

    return Card(
      key: ValueKey('grid_card_${widget.project.cameraNames.join("_")}'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double baseWidth = widget.settings.usePagesStyleLayout ? 640.0 : 880.0;
          final double minGridWidth = baseWidth + (widget.project.cameraNames.length * 88.0);
          final bool needsHorizontalScroll = constraints.maxWidth < minGridWidth;
          final double gridWidth = needsHorizontalScroll ? minGridWidth : constraints.maxWidth;

          final gridContent = SizedBox(
            width: gridWidth,
            height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
            child: Column(
              children: [
                _buildGridHeader(),
                Expanded(
                  child: ReorderableListView.builder(
                    scrollController: _scrollController,
                    cacheExtent: 800,
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
                        clusterStartIndex: clusterStartIndices[index],
                        clusterCount: clusterCounts[index],
                      );
                    },
                  ),
                ),
              ],
            ),
          );

          if (!needsHorizontalScroll) {
            return SizedBox(
              width: constraints.maxWidth,
              child: gridContent,
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            dragStartBehavior: DragStartBehavior.down,
            child: gridContent,
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
        color: isDark ? const Color(0xFF282832) : const Color(0xFFE2E8F0),
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF383846) : const Color(0xFFCBD5E1))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (usePagesStyle) ...[
            const SizedBox(width: 3),
            const SizedBox(width: 8),
          ],
          const SizedBox(width: 20),
          const SizedBox(
            width: 32, 
            child: Center(
              child: Text(
                '#', 
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!usePagesStyle) ...[
            for (final elem in widget.project.bitacoraElementOrder) ...[
              if (elem == 'capitulo' && widget.project.showChapter) ...[
                const SizedBox(
                  width: 55, 
                  child: Center(
                    child: Text(
                      'Cap', 
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (elem == 'escena') ...[
                const SizedBox(
                  width: 130, 
                  child: Center(
                    child: Text(
                      'Escena', 
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (elem == 'plano' && widget.project.showPlane) ...[
                const SizedBox(
                  width: 55, 
                  child: Center(
                    child: Text(
                      'Plano', 
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (elem == 'toma') ...[
                const SizedBox(
                  width: 60, 
                  child: Center(
                    child: Text(
                      'Toma', 
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ] else ...[
            const SizedBox(
              width: 60, 
              child: Center(
                child: Text(
                  'Toma', 
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          for (var cam in widget.project.cameraNames)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: SizedBox(
                width: 80, 
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Clip Cam', 
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w500, fontSize: 10),
                    ),
                    Text(
                      '"$cam"', 
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), 
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(
            width: 75, 
            child: Center(
              child: Text(
                'Reel', 
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const SizedBox(
            width: 110, 
            child: Center(
              child: Text(
                'TC In', 
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (widget.project.showTcOut) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 110, 
              child: Center(
                child: Text(
                  'TC Out', 
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
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

  void _confirmInlineEdit(int startIndex, int count) {
    _updateSetupForCluster(
      startIndex,
      count,
      chapter: _inlineCapController.text.trim(),
      scene: _inlineSceneController.text.trim(),
      plane: _inlinePlaneController.text.trim(),
    );
    setState(() {
      _editingClusterStartIndex = null;
    });
  }

  void _cancelInlineEdit() {
    setState(() {
      _editingClusterStartIndex = null;
    });
  }

  Widget _buildSceneHeaderBanner(ShotRecord record, int sceneTakeCount, int startIndex) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bannerBg = isDark
        ? const Color(0xFF1E1B2E)
        : const Color(0xFFEEF2FF);
    final bannerBorder = Border.all(
      color: const Color(0xFF6366F1),
      width: 1.5,
    );
    final bannerTextColor = isDark
        ? Colors.white
        : const Color(0xFF312E81);
    final badgeBg = isDark
        ? theme.colorScheme.surface.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.8);
    final badgeBorder = BorderSide(
      color: theme.colorScheme.primary.withValues(alpha: 0.3),
      width: 1,
    );

    final isEditing = _editingClusterStartIndex == startIndex;

    if (isEditing) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bannerBg,
          borderRadius: BorderRadius.circular(8),
          border: bannerBorder,
        ),
        child: Row(
          children: [
            Icon(
              Icons.edit_note,
              size: 20,
              color: bannerTextColor,
            ),
            const SizedBox(width: 8),
            for (final elem in widget.project.bitacoraElementOrder) ...[
              if (elem == 'capitulo' && widget.project.showChapter) ...[
                SizedBox(
                  width: 70,
                  height: 32,
                  child: TextField(
                    key: const ValueKey('inline_banner_cap'),
                    controller: _inlineCapController,
                    decoration: const InputDecoration(
                      labelText: 'Cap',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onSubmitted: (_) => _confirmInlineEdit(startIndex, sceneTakeCount),
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (elem == 'escena') ...[
                SizedBox(
                  width: 130,
                  height: 32,
                  child: TextField(
                    key: const ValueKey('inline_banner_scene'),
                    controller: _inlineSceneController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Escena',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    onSubmitted: (_) => _confirmInlineEdit(startIndex, sceneTakeCount),
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (elem == 'plano' && widget.project.showPlane) ...[
                SizedBox(
                  width: 70,
                  height: 32,
                  child: TextField(
                    key: const ValueKey('inline_banner_plane'),
                    controller: _inlinePlaneController,
                    decoration: const InputDecoration(
                      labelText: 'Plano',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onSubmitted: (_) => _confirmInlineEdit(startIndex, sceneTakeCount),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
            IconButton(
              icon: const Icon(Icons.check, size: 20, color: Colors.green),
              tooltip: 'Guardar cambios del grupo',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              splashRadius: 18,
              onPressed: () => _confirmInlineEdit(startIndex, sceneTakeCount),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: Colors.redAccent),
              tooltip: 'Cancelar',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              splashRadius: 18,
              onPressed: _cancelInlineEdit,
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$sceneTakeCount ${sceneTakeCount == 1 ? 'toma' : 'tomas'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(8),
        border: bannerBorder,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          mouseCursor: SystemMouseCursors.click,
          onTap: () {
            setState(() {
              _editingClusterStartIndex = startIndex;
              _inlineCapController.text = record.chapter;
              _inlineSceneController.text = record.scene;
              _inlinePlaneController.text = record.plane ?? '';
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              children: [
                Icon(
                  Icons.movie_outlined,
                  size: 20,
                  color: bannerTextColor,
                ),
                const SizedBox(width: 10),
                for (final elem in widget.project.bitacoraElementOrder) ...[
                  if (elem == 'capitulo' && widget.project.showChapter) ...[
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
                    const SizedBox(width: 10),
                  ] else if (elem == 'escena') ...[
                    Text(
                      'ESCENA ${record.scene.isNotEmpty ? record.scene : 'S/E'}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: bannerTextColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ] else if (elem == 'plano' && widget.project.showPlane) ...[
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
                    const SizedBox(width: 10),
                  ],
                ],
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Haz clic para editar Escena, Capítulo y Plano de este grupo ($sceneTakeCount ${sceneTakeCount == 1 ? "toma" : "tomas"})',
                  child: Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: bannerTextColor.withValues(alpha: 0.8),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$sceneTakeCount ${sceneTakeCount == 1 ? 'toma' : 'tomas'}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridRow(
    int index, 
    ShotRecord record, {
    required bool isNewScene,
    required int sceneTakeCount,
    required int clusterStartIndex,
    required int clusterCount,
  }) {
    String getClipForCam(String cam) {
      final camRecord = record.cameras.where((c) => c.cameraName == cam).firstOrNull;
      return camRecord?.clipName ?? '';
    }

    void updateRecord(ShotRecord newRecord, {String? defaultReel}) {
      final newRecords = List<ShotRecord>.from(widget.project.log.records);
      newRecords[index] = newRecord;
      final updatedLog = widget.project.log.copyWith(records: newRecords);
      if (defaultReel != null && defaultReel.isNotEmpty && defaultReel != widget.project.defaultReel.trim()) {
        widget.onProjectChanged(widget.project.copyWith(log: updatedLog, defaultReel: defaultReel));
      } else {
        widget.onProjectChanged(widget.project.copyWith(log: updatedLog));
      }
    }

    void updateSetupField({String? chapter, String? scene, String? plane}) {
      final newCap = chapter ?? record.chapter;
      final newScene = scene ?? record.scene;
      final newPlane = plane ?? (record.plane ?? '');
      if (clusterCount > 1) {
        _updateSetupForCluster(
          clusterStartIndex,
          clusterCount,
          chapter: newCap,
          scene: newScene,
          plane: newPlane,
        );
      } else {
        updateRecord(record.copyWith(
          chapter: newCap,
          scene: newScene,
          plane: newPlane,
        ));
      }
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
        : (isEven ? Colors.white : const Color(0xFFF8FAFC));

    final cardBorderColor = isDark
        ? (isEven ? const Color(0xFF282832) : const Color(0xFF424250))
        : const Color(0xFFCBD5E1);

    final tier2Color = isDark
        ? (isEven ? const Color(0xFF101014) : const Color(0xFF22222A))
        : (isEven ? const Color(0xFFF1F5F9) : const Color(0xFFE2E8F0));

    final tier2BorderColor = isDark
        ? (isEven ? const Color(0xFF1F1F26) : const Color(0xFF383844))
        : const Color(0xFFCBD5E1);

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
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
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
                for (final elem in widget.project.bitacoraElementOrder) ...[
                  if (elem == 'capitulo' && widget.project.showChapter) ...[
                    SizedBox(
                      width: 55, 
                      child: _buildGridCell(
                        record.chapter, 
                        (v) => updateSetupField(chapter: v), 
                        hintText: 'Cap',
                        labelText: 'Cap',
                        autofocus: _autofocusFieldId == '${record.id}_cap',
                        focusNode: (_autofocusFieldId == '${record.id}_cap') ? _activeAutofocusNode : null,
                        key: ValueKey('${record.id}_cap'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (elem == 'escena') ...[
                    SizedBox(
                      width: 130, 
                      child: _buildGridCell(
                        record.scene, 
                        (v) => updateSetupField(scene: v), 
                        hintText: 'Escena',
                        labelText: 'Escena',
                        autofocus: _autofocusFieldId == '${record.id}_scene',
                        focusNode: (_autofocusFieldId == '${record.id}_scene') ? _activeAutofocusNode : null,
                        key: ValueKey('${record.id}_scene'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (elem == 'plano' && widget.project.showPlane) ...[
                    SizedBox(
                      width: 55, 
                      child: _buildGridCell(
                        record.plane ?? '', 
                        (v) => updateSetupField(plane: v), 
                        hintText: 'Plano',
                        labelText: 'Plano',
                        key: ValueKey('${record.id}_plane'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (elem == 'toma') ...[
                    SizedBox(
                      width: 60, 
                      child: _buildGridCell(
                        record.take, 
                        (v) => updateRecord(record.copyWith(take: v)), 
                        hintText: 'Toma',
                        labelText: 'Toma',
                        autofocus: _autofocusFieldId == '${record.id}_take',
                        focusNode: (_autofocusFieldId == '${record.id}_take') ? _activeAutofocusNode : null,
                        key: ValueKey('${record.id}_take'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ] else ...[
                SizedBox(
                  width: 60, 
                  child: _buildGridCell(
                    record.take, 
                    (v) => updateRecord(record.copyWith(take: v)), 
                    hintText: 'Toma',
                    labelText: 'Toma',
                    autofocus: _autofocusFieldId == '${record.id}_take',
                    focusNode: (_autofocusFieldId == '${record.id}_take') ? _activeAutofocusNode : null,
                    key: ValueKey('${record.id}_take'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
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
                      autofocus: _autofocusFieldId == '${record.id}_clip_$cam',
                      focusNode: (_autofocusFieldId == '${record.id}_clip_$cam') ? _activeAutofocusNode : null,
                      key: ValueKey('${record.id}_clip_$cam'),
                    ),
                  ),
                ),
              SizedBox(
                width: 75, 
                child: _buildGridCell(
                  record.reel, 
                  (v) {
                    var clean = v.trim();
                    final match = RegExp(r'^[A-Za-z](\d+)$').firstMatch(clean);
                    if (match != null) {
                      clean = match.group(1)!;
                    }
                    updateRecord(
                      record.copyWith(reel: clean),
                      defaultReel: clean.isNotEmpty ? clean : null,
                    );
                  }, 
                  hintText: 'Reel',
                  labelText: 'Reel',
                  key: ValueKey('${record.id}_reel'),
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
                    key: ValueKey('${record.id}_tcIn_${record.tcIn ?? ""}'),
                  ),
                ),
              ),
              if (widget.project.showTcOut) ...[
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
                      key: ValueKey('${record.id}_tcOut_${record.tcOut ?? ""}'),
                    ),
                  ),
                ),
              ],
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
                    for (final elem in widget.project.bitacoraElementOrder) ...[
                      if (elem == 'capitulo' && widget.project.showChapter) ...[
                        SizedBox(
                          width: 55,
                          child: _buildGridCell(
                            record.chapter,
                            (v) => updateSetupField(chapter: v),
                            hintText: 'Cap',
                            labelText: 'Cap',
                            autofocus: _autofocusFieldId == '${record.id}_cap',
                            focusNode: (_autofocusFieldId == '${record.id}_cap') ? _activeAutofocusNode : null,
                            key: ValueKey('${record.id}_tier2_cap'),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else if (elem == 'escena') ...[
                        SizedBox(
                          width: 80,
                          child: _buildGridCell(
                            record.scene,
                            (v) => updateSetupField(scene: v),
                            hintText: 'Escena',
                            labelText: 'Escena',
                            autofocus: _autofocusFieldId == '${record.id}_scene',
                            focusNode: (_autofocusFieldId == '${record.id}_scene') ? _activeAutofocusNode : null,
                            key: ValueKey('${record.id}_tier2_scene'),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else if (elem == 'plano' && widget.project.showPlane) ...[
                        SizedBox(
                          width: 55,
                          child: _buildGridCell(
                            record.plane ?? '',
                            (v) => updateSetupField(plane: v),
                            hintText: 'Plano',
                            labelText: 'Plano',
                            key: ValueKey('${record.id}_tier2_plane'),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                    const SizedBox(width: 4),
                  ],
                  if (widget.project.showMos) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => updateRecord(record.copyWith(isMos: !record.isMos)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            key: ValueKey('${record.id}_is_mos'),
                            value: record.isMos,
                            onChanged: (val) => updateRecord(record.copyWith(isMos: val ?? false)),
                            visualDensity: VisualDensity.compact,
                          ),
                          const Text('MOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (widget.project.showDs) ...[
                    Tooltip(
                      message: 'Driving Shot',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => updateRecord(record.copyWith(isDs: !record.isDs)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              key: ValueKey('${record.id}_is_ds'),
                              value: record.isDs,
                              onChanged: (val) => updateRecord(record.copyWith(isDs: val ?? false)),
                              visualDensity: VisualDensity.compact,
                            ),
                            const Text('DS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (widget.project.showFf) ...[
                    Tooltip(
                      message: 'Free Fly',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => updateRecord(record.copyWith(isFf: !record.isFf)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              key: ValueKey('${record.id}_is_ff'),
                              value: record.isFf,
                              onChanged: (val) => updateRecord(record.copyWith(isFf: val ?? false)),
                              visualDensity: VisualDensity.compact,
                            ),
                            const Text('FF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (widget.project.showGpr) ...[
                    Tooltip(
                      message: 'GoPro',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => updateRecord(record.copyWith(isGpr: !record.isGpr)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              key: ValueKey('${record.id}_is_gpr'),
                              value: record.isGpr,
                              onChanged: (val) => updateRecord(record.copyWith(isGpr: val ?? false)),
                              visualDensity: VisualDensity.compact,
                            ),
                            const Text('GPR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (widget.project.showDr) ...[
                    Tooltip(
                      message: 'Drone',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => updateRecord(record.copyWith(isDr: !record.isDr)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              key: ValueKey('${record.id}_is_dr'),
                              value: record.isDr,
                              onChanged: (val) => updateRecord(record.copyWith(isDr: val ?? false)),
                              visualDensity: VisualDensity.compact,
                            ),
                            const Text('DR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (widget.project.showTf) ...[
                    Tooltip(
                      message: 'Toma Falsa / Descartada',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => updateRecord(record.copyWith(isTf: !record.isTf)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              key: ValueKey('${record.id}_is_tf'),
                              value: record.isTf,
                              onChanged: (val) => updateRecord(record.copyWith(isTf: val ?? false)),
                              visualDensity: VisualDensity.compact,
                            ),
                            const Text('TF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
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

    final rowContent = Column(
      key: ValueKey('row_${record.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (usePagesStyle && isNewScene)
          _buildSceneHeaderBanner(record, sceneTakeCount, clusterStartIndex),
        KeyedSubtree(
          key: ValueKey('card_${record.id}'),
          child: cardWidget,
        ),
      ],
    );

    return _KeepAliveGridRowItem(
      key: ValueKey(record.id),
      child: rowContent,
    );
  }

  Widget _buildGridCell(
    String value, 
    ValueChanged<String> onChanged, {
    List<TextInputFormatter>? formatters, 
    String? hintText,
    String? labelText,
    bool isGhosted = false,
    bool autofocus = false,
    FocusNode? focusNode,
    Key? key,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultTextColor = isDark ? Colors.white : Colors.black87;
    final textColor = isGhosted ? Colors.grey.withValues(alpha: 0.3) : defaultTextColor;

    final cellField = TextFormField(
      key: key,
      initialValue: isGhosted ? '' : value,
      autofocus: autofocus,
      focusNode: focusNode,
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

    return cellField;
  }

  void _showConfigDialog() {
    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        currentSettings: widget.settings,
        onSettingsChanged: (newSettings) {
          widget.onSettingsChanged?.call(newSettings);
        },
        project: widget.project,
        onProjectChanged: widget.onProjectChanged,
        initialTabIndex: 1,
      ),
    );
  }

  Widget _buildFooterActions() {
    final records = widget.project.log.records;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 1. Live Timecode Badge with TOD/JAM & Sync PopupMenu
          ListenableBuilder(
            listenable: _timecodeService,
            builder: (context, _) {
              return Container(
                constraints: const BoxConstraints(minWidth: 172),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: isDark ? 0.4 : 0.6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.colorScheme.primary, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fiber_manual_record, size: 10, color: Colors.redAccent),
                        const SizedBox(width: 5),
                        SizedBox(
                          width: 92,
                          child: Text(
                            _timecodeService.currentFormattedTimecode,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _timecodeService.isTimeOfDay ? 'TOD' : 'JAM',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.access_time, size: 18),
                      tooltip: 'Sincronización de Reloj',
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      onSelected: (value) {
                        if (value == 'tod') {
                          _timecodeService.syncToTimeOfDay();
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Sincronizado a Reloj del Sistema (Time of Day - TOD)'),
                              duration: Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        } else if (value == 'jam') {
                          _showJamSyncDialog();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'tod',
                          child: Row(
                            children: [
                              Icon(Icons.schedule, size: 16),
                              SizedBox(width: 8),
                              Text('Sincronizar Reloj (TOD - Hora Real)'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'jam',
                          child: Row(
                            children: [
                              Icon(Icons.tune, size: 16),
                              SizedBox(width: 8),
                              Text('Ajustar Código Manual (Jam Sync)...'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          // 2. Auto TC Checkbox
          ListenableBuilder(
            listenable: _timecodeService,
            builder: (context, _) {
              return Tooltip(
                message: 'Aplica automáticamente el código de tiempo a nuevas tomas',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _timecodeService.isAutoStampEnabled,
                      onChanged: (val) {
                        _timecodeService.toggleAutoStamp(val ?? true);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                    const Text('Auto TC', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            },
          ),
          // 3. Nueva Toma (Ctrl+N)
          Tooltip(
            message: 'Crear una nueva toma vacía (Ctrl+N)',
            child: ElevatedButton.icon(
              onPressed: _addNewRecord,
              icon: const Icon(Icons.add),
              label: const Text('Nueva Toma'),
            ),
          ),
          // 4. Marcar Corte (Ctrl+K)
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Tooltip(
                message: 'Estampa el código de tiempo actual en TC Out de la última toma (Ctrl+K)',
                child: ElevatedButton.icon(
                  onPressed: records.isEmpty ? null : _stampCutOnLastRecord,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('Marcar Corte'),
                ),
              ),
              if (_cutFeedbackMessage != null)
                Positioned(
                  bottom: 42,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Theme.of(context).colorScheme.primary : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 13,
                          color: isDark ? const Color(0xFF181824) : const Color(0xFF4ADE80),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _cutFeedbackMessage!,
                          style: TextStyle(
                            color: isDark ? const Color(0xFF181824) : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          // 5. Duplicar última toma (Ctrl+D)
          Tooltip(
            message: 'Duplica la última toma incrementando el número de toma (Ctrl+D)',
            child: ElevatedButton.icon(
              onPressed: records.isEmpty ? null : _duplicateLastRecord,
              icon: const Icon(Icons.copy),
              label: const Text('Duplicar última toma'),
            ),
          ),
          // 6. Reordenar por Clip
          Tooltip(
            message: 'Reorganizar todas las tomas según la secuencia numérica de clips',
            child: OutlinedButton.icon(
              icon: const Icon(Icons.sort_by_alpha, size: 16),
              label: const Text('Reordenar por Clip'),
              onPressed: records.isEmpty ? null : _reorderRecordsByClip,
            ),
          ),
          // 7. Contador de tomas registradas
          Text(
            '${records.length} tomas registradas',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          // 8. Deshacer eliminación (Ctrl+Z)
          Tooltip(
            message: 'Restaurar las últimas tomas eliminadas (Ctrl+Z)',
            child: ElevatedButton.icon(
              onPressed: (_lastDeletedRecords == null || _lastDeletedRecords!.isEmpty)
                  ? null
                  : _undoLastDeletion,
              icon: const Icon(Icons.undo),
              label: const Text('Deshacer eliminación'),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeepAliveGridRowItem extends StatefulWidget {
  final Widget child;
  const _KeepAliveGridRowItem({super.key, required this.child});

  @override
  State<_KeepAliveGridRowItem> createState() => _KeepAliveGridRowItemState();
}

class _KeepAliveGridRowItemState extends State<_KeepAliveGridRowItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
