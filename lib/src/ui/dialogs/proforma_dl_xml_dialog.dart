import 'package:flutter/material.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/ui/tabs/metadata_generator_tab.dart';

/// Interactive dialog for inspecting detected media clips, reviewing/editing
/// batch metadata defaults, and generating strict DigitalLogic 3.2 Proforma_DL XML sidecars.
class ProformaDlXmlDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        child: MetadataGeneratorTab(
          initialFolderPath: initialFolderPath,
          project: project,
          mediaFiles: mediaFiles,
          onGenerated: onGenerated,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
