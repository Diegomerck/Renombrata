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

  @override
  void didUpdateWidget(BitacoraEditorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.log.metadata.production != widget.project.log.metadata.production || 
        oldWidget.project.log.metadata.date != widget.project.log.metadata.date) {
      _lastDeletedRecord = null;
      _lastDeletedIndex = null;
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
                    Expanded(child: _buildTextField('Video Codec', meta.videoCodec, (v) => _updateMetadata(meta.copyWith(videoCodec: v)))),
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

  Widget _buildDataGrid() {
    final records = widget.project.log.records;
    final double totalWidth = 962 + (widget.project.cameraNames.length * 100).toDouble();
    
    return Card(
      key: ValueKey('grid_${widget.project.cameraNames.join("_")}_${records.length}'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
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
        ),
      ),
    );
  }

  Widget _buildGridHeader() {
    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          const SizedBox(width: 40), // For drag handle
          const SizedBox(width: 40, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 80, child: Text('Escena', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 80, child: Text('Plano', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 80, child: Text('Toma', style: TextStyle(fontWeight: FontWeight.bold))),
          for (var cam in widget.project.cameraNames)
            SizedBox(width: 100, child: Text('Clip $cam', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 80, child: Text('Reel', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 100, child: Text('TC In', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 100, child: Text('TC Out', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 48, child: Text('MOS', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 250, child: Text('Observaciones', style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 48), // Action column
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

    return Container(
      key: ValueKey(record.id),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: const SizedBox(width: 40, child: MouseRegion(cursor: SystemMouseCursors.grab, child: Icon(Icons.drag_indicator, color: Colors.grey))),
          ),
          SizedBox(width: 40, child: Text('${index + 1}')),
          SizedBox(width: 80, child: _buildGridCell(record.scene, (v) => updateRecord(record.copyWith(scene: v)))),
          SizedBox(width: 80, child: _buildGridCell(record.plane ?? '', (v) => updateRecord(record.copyWith(plane: v)))),
          SizedBox(width: 80, child: _buildGridCell(record.take, (v) => updateRecord(record.copyWith(take: v)))),
          for (var cam in widget.project.cameraNames)
            SizedBox(width: 100, child: _buildGridCell(getClipForCam(cam), (v) => updateCam(cam, v))),
          SizedBox(width: 80, child: _buildGridCell(record.reel, (v) => updateRecord(record.copyWith(reel: v)))),
          SizedBox(
            width: 100, 
            child: Focus(
              onFocusChange: (focused) {
                if (!focused && record.tcIn != null && record.tcIn!.isNotEmpty) {
                  updateRecord(record.copyWith(tcIn: TimecodeUtils.normalize(record.tcIn!, widget.project.log.metadata.frameRate)));
                }
              },
              child: _buildGridCell(record.tcIn ?? '', (v) => updateRecord(record.copyWith(tcIn: v)), formatters: [TimecodeTextInputFormatter(widget.project.log.metadata.frameRate)])
            )
          ),
          SizedBox(
            width: 100, 
            child: Focus(
              onFocusChange: (focused) {
                if (!focused && record.tcOut != null && record.tcOut!.isNotEmpty) {
                  updateRecord(record.copyWith(tcOut: TimecodeUtils.normalize(record.tcOut!, widget.project.log.metadata.frameRate)));
                }
              },
              child: _buildGridCell(record.tcOut ?? '', (v) => updateRecord(record.copyWith(tcOut: v)), formatters: [TimecodeTextInputFormatter(widget.project.log.metadata.frameRate)])
            )
          ),
          SizedBox(
            width: 48,
            child: Checkbox(
              value: record.isMos,
              onChanged: (val) => updateRecord(record.copyWith(isMos: val ?? false)),
            ),
          ),
          SizedBox(width: 250, child: _buildGridCell(record.observations ?? '', (v) => updateRecord(record.copyWith(observations: v)))),
          SizedBox(
            width: 48,
            child: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                setState(() {
                  _lastDeletedRecord = record;
                  _lastDeletedIndex = index;
                });
                final newRecords = List<ShotRecord>.from(widget.project.log.records);
                newRecords.removeAt(index);
                _updateRecords(newRecords);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridCell(String value, ValueChanged<String> onChanged, {List<TextInputFormatter>? formatters}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextFormField(
        initialValue: value,
        inputFormatters: formatters,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.all(8),
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: onChanged,
      ),
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
            onPressed: () {
              final newRecords = List<ShotRecord>.from(records);
              newRecords.add(ShotRecord(
                chapter: '',
                scene: '',
                plane: '',
                take: '',
                cameras: [],
                reel: widget.project.defaultReel,
              ));
              _updateRecords(newRecords);
            },
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
