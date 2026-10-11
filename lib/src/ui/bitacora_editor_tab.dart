import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/utils/timecode_formatter.dart';
import 'package:uuid/uuid.dart';

class BitacoraEditorTab extends StatefulWidget {
  final RenombrataProject project;
  final ValueChanged<RenombrataProject> onProjectChanged;

  const BitacoraEditorTab({
    super.key,
    required this.project,
    required this.onProjectChanged,
  });

  @override
  State<BitacoraEditorTab> createState() => _BitacoraEditorTabState();
}

class _BitacoraEditorTabState extends State<BitacoraEditorTab> {
  bool _isHeaderExpanded = true;
  ShotRecord? _lastDeletedRecord;
  int? _lastDeletedIndex;
  final Set<String> _expandedRecordIds = {};

  @override
  void didUpdateWidget(BitacoraEditorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.log.metadata.production != widget.project.log.metadata.production || 
        oldWidget.project.log.metadata.date != widget.project.log.metadata.date) {
      _lastDeletedRecord = null;
      _lastDeletedIndex = null;
      _expandedRecordIds.clear();
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
                    Expanded(child: _buildTextField('Producción', meta.production, (v) => _updateMetadata(meta.copyWith(production: v)))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField('Nomenclatura', meta.nomenclature, (v) => _updateMetadata(meta.copyWith(nomenclature: v)))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField('Fecha (DDMMAA)', meta.date, (v) => _updateMetadata(meta.copyWith(date: v)))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField('Día de grabación', meta.day, (v) => _updateMetadata(meta.copyWith(day: v)))),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildTextField('Unidad', meta.unit, (v) => _updateMetadata(meta.copyWith(unit: v)))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField('Locación', meta.location, (v) => _updateMetadata(meta.copyWith(location: v)))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField('Productor', meta.producer, (v) => _updateMetadata(meta.copyWith(producer: v)))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField('Ing. Responsable', meta.responsibleEngineer, (v) => _updateMetadata(meta.copyWith(responsibleEngineer: v)))),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildTextField('Ingestador', meta.ingestor, (v) => _updateMetadata(meta.copyWith(ingestor: v)))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildFrameRateDropdown(meta.frameRate, (v) => _updateMetadata(meta.copyWith(frameRate: v ?? '23.98')))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildVideoCodecAutocomplete(meta.videoCodec, (v) => _updateMetadata(meta.copyWith(videoCodec: v)))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField('Audio Format', meta.audioFormat, (v) => _updateMetadata(meta.copyWith(audioFormat: v)))),
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

  Widget _buildTextField(String label, String value, ValueChanged<String> onChanged) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }

  Widget _buildVideoCodecAutocomplete(String value, ValueChanged<String> onChanged) {
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
      initialValue: TextEditingValue(text: value),
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text == '') {
          return const Iterable<String>.empty();
        }
        return options.where((String option) {
          return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
        });
      },
      onSelected: (String selection) {
        onChanged(selection);
      },
      fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
        return Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) {
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
            onFieldSubmitted: (String value) {
              onFieldSubmitted();
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
      value: effectiveValue,
      decoration: const InputDecoration(
        labelText: 'Frame Rate',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: options.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
      onChanged: onChanged,
    );
  }

  void _addNewRecord() {
    final newRecord = ShotRecord(
      chapter: '',
      scene: '',
      plane: '',
      take: '',
      cameras: [],
      reel: widget.project.defaultReel,
    );
    final newRecords = List<ShotRecord>.from(widget.project.log.records);
    newRecords.add(newRecord);
    setState(() {
      _expandedRecordIds.clear();
      _expandedRecordIds.add(newRecord.id);
    });
    _updateRecords(newRecords);
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
                Icon(Icons.movie_filter_outlined, size: 48, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
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

    return Card(
      key: ValueKey('grid_${widget.project.cameraNames.join("_")}_${records.length}'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildGridHeader(),
          Expanded(
            child: ReorderableListView(
              buildDefaultDragHandles: false,
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
              children: [
                for (int i = 0; i < records.length; i++)
                  _buildGridRow(i, records[i]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final records = widget.project.log.records;
    final allExpanded = records.isNotEmpty && _expandedRecordIds.length == records.length;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF282832) : Colors.grey.shade200,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF383846) : Colors.grey.shade300)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 20),
          const SizedBox(width: 32, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          const SizedBox(width: 180, child: Text('Escena', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          const SizedBox(width: 55, child: Text('Plano', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          const SizedBox(width: 50, child: Text('Toma', style: TextStyle(fontWeight: FontWeight.bold))),
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
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildGridRow(int index, ShotRecord record) {
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
        : (isEven ? Colors.white : const Color(0xFFE8EBF0));

    final cardBorderColor = isDark
        ? (isEven ? const Color(0xFF282832) : const Color(0xFF424250))
        : (isEven ? Colors.grey.shade300 : const Color(0xFFCBD0D8));

    final tier2Color = isDark
        ? (isEven ? const Color(0xFF101014) : const Color(0xFF22222A))
        : (isEven ? const Color(0xFFF8F9FA) : const Color(0xFFDFE2E8));

    final tier2BorderColor = isDark
        ? (isEven ? const Color(0xFF1F1F26) : const Color(0xFF383844))
        : (isEven ? Colors.grey.shade200 : const Color(0xFFCBD0D8));

    return Container(
      key: ValueKey(record.id),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cardBorderColor,
          width: 1,
        ),
        boxShadow: isDark ? [] : [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
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
              SizedBox(width: 180, child: _buildGridCell(record.scene, (v) => updateRecord(record.copyWith(scene: v)), hintText: 'Escena')),
              const SizedBox(width: 8),
              SizedBox(width: 55, child: _buildGridCell(record.plane ?? '', (v) => updateRecord(record.copyWith(plane: v)), hintText: 'Plano')),
              const SizedBox(width: 8),
              SizedBox(width: 50, child: _buildGridCell(record.take, (v) => updateRecord(record.copyWith(take: v)), hintText: 'Toma')),
              const SizedBox(width: 8),
              for (var cam in widget.project.cameraNames)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: SizedBox(width: 80, child: _buildGridCell(getClipForCam(cam), (v) => updateCam(cam, v), hintText: 'Clip $cam')),
                ),
              SizedBox(width: 75, child: _buildGridCell(record.reel, (v) => updateRecord(record.copyWith(reel: v)), hintText: 'Reel')),
              const SizedBox(width: 8),
              SizedBox(
                width: 110, 
                child: Focus(
                  onFocusChange: (focused) {
                    if (!focused && record.tcIn != null && record.tcIn!.isNotEmpty) {
                      updateRecord(record.copyWith(tcIn: TimecodeUtils.normalize(record.tcIn!, widget.project.log.metadata.frameRate)));
                    }
                  },
                  child: _buildGridCell(record.tcIn ?? '', (v) => updateRecord(record.copyWith(tcIn: v)), formatters: [TimecodeTextInputFormatter(widget.project.log.metadata.frameRate)], hintText: 'TC In (00:00:00:00)'),
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
                  child: _buildGridCell(record.tcOut ?? '', (v) => updateRecord(record.copyWith(tcOut: v)), formatters: [TimecodeTextInputFormatter(widget.project.log.metadata.frameRate)], hintText: 'TC Out (00:00:00:00)'),
                ),
              ),
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
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
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
                        _lastDeletedRecord = record;
                        _lastDeletedIndex = index;
                        _expandedRecordIds.remove(record.id);
                      });
                      final newRecords = List<ShotRecord>.from(widget.project.log.records);
                      newRecords.removeAt(index);
                      _updateRecords(newRecords);
                    }
                  },
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
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGridCell(String value, ValueChanged<String> onChanged, {List<TextInputFormatter>? formatters, String? hintText}) {
    return TextFormField(
      initialValue: value,
      inputFormatters: formatters,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.all(8),
        border: const OutlineInputBorder(),
        hintText: hintText,
        hintStyle: TextStyle(
          color: Theme.of(context).hintColor.withOpacity(0.4),
          fontSize: 11,
        ),
      ),
      style: const TextStyle(fontSize: 12),
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
      padding: const EdgeInsets.all(16.0),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: _addNewRecord,
            icon: const Icon(Icons.add),
            label: const Text('Nueva Toma'),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: records.isEmpty ? null : () {
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
            },
            icon: const Icon(Icons.copy),
            label: const Text('Duplicar última toma'),
          ),

          Text(
            '${records.length} tomas registradas',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: _lastDeletedRecord == null ? null : () {
              final restoredRecords = List<ShotRecord>.from(widget.project.log.records);
              if (_lastDeletedIndex != null && _lastDeletedIndex! <= restoredRecords.length) {
                restoredRecords.insert(_lastDeletedIndex!, _lastDeletedRecord!);
              } else {
                restoredRecords.add(_lastDeletedRecord!);
              }
              setState(() {
                _lastDeletedRecord = null;
                _lastDeletedIndex = null;
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
