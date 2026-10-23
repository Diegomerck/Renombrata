import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/app_settings.dart';
import '../services/settings_service.dart';

class SettingsDialog extends StatefulWidget {
  final AppSettings currentSettings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const SettingsDialog({
    super.key,
    required this.currentSettings,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.currentSettings;
  }

  void _updateSettings(AppSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    widget.onSettingsChanged(_settings);
    SettingsService.saveSettings(_settings);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.settings, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Text('Configuración', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
