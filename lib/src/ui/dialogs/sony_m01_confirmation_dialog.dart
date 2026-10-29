import 'package:flutter/material.dart';

/// Confirmation dialog displayed when Sony MXF companion metadata XML files
/// ending in "M01" (e.g. A055C001_230309CVM01.xml) are detected.
class SonyM01ConfirmationDialog extends StatelessWidget {
  final String? sampleVideoName;
  final String? sampleXmlName;

  const SonyM01ConfirmationDialog({
    super.key,
    this.sampleVideoName,
    this.sampleXmlName,
  });

  /// Displays the confirmation dialog and returns `true` to link/rename,
  /// or `false` to ignore M01 files.
  static Future<bool?> show(
    BuildContext context, {
    String? sampleVideoName,
    String? sampleXmlName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SonyM01ConfirmationDialog(
        sampleVideoName: sampleVideoName,
        sampleXmlName: sampleXmlName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final videoName = sampleVideoName ?? 'A055C001_230309CV.mxf';
    final xmlName = sampleXmlName ?? 'A055C001_230309CVM01.xml';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      actionsPadding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 12 / 100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.video_file_outlined,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Archivos de Metadatos Sony (M01.XML) Detectados',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se encontraron archivos de metadatos XML que terminan en M01. '
              '¿Deseas vincularlos a sus clips de video para renombrarlos en conjunto?',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 40 / 100)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 20 / 100),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.preview_rounded,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Ejemplo detectado:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Video: [$videoName] <--> Metadatos: [$xmlName]',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          key: const ValueKey('sony_m01_ignore_button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Ignorar Archivos M01'),
        ),
        FilledButton.icon(
          key: const ValueKey('sony_m01_confirm_button'),
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.link, size: 16),
          label: const Text('Vincular y Renombrar Metadatos'),
        ),
      ],
    );
  }
}
