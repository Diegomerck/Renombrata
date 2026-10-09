import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/dry_run_report.dart';

class RenameService {
  static Future<void> executeRename({
    required String mediaFolderPath,
    required List<RenameProposal> proposals,
    required bool renameMetadata,
  }) async {
    List<Map<String, dynamic>> auditLog = [];

    for (var proposal in proposals) {
      if (proposal.status == ProposalStatus.ready) {
        if (!renameMetadata && proposal.isCompanionFile) {
          continue;
        }

        if (proposal.originalFilePath == null) continue;

        final originalFile = File(proposal.originalFilePath!);
        if (await originalFile.exists()) {
          final newPath = p.join(
            p.dirname(proposal.originalFilePath!),
            proposal.proposedFileName,
          );

          await originalFile.rename(newPath);

          auditLog.add({
            'timestamp': DateTime.now().toIso8601String(),
            'originalPath': proposal.originalFilePath,
            'renamedPath': newPath,
            'takeInfo': proposal.associatedRecord != null
                ? 'Esc. ${proposal.associatedRecord!.scene} - T${proposal.associatedRecord!.take}'
                : null,
          });
        }
      }
    }

    if (auditLog.isNotEmpty) {
      final logFile = File(p.join(mediaFolderPath, 'rename_history.json'));
      List<dynamic> existingLog = [];
      if (await logFile.exists()) {
        final content = await logFile.readAsString();
        try {
          existingLog = jsonDecode(content);
        } catch (_) {}
      }

      existingLog.addAll(auditLog);
      await logFile.writeAsString(const JsonEncoder.withIndent('  ').convert(existingLog));
    }
  }

  static Future<List<Map<String, dynamic>>> readRenameHistory(String mediaFolderPath) async {
    final logFile = File(p.join(mediaFolderPath, 'rename_history.json'));
    if (await logFile.exists()) {
      final content = await logFile.readAsString();
      try {
        final decoded = jsonDecode(content) as List;
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
    return [];
  }

  static Future<void> undoRename(String mediaFolderPath) async {
    final history = await readRenameHistory(mediaFolderPath);
    if (history.isEmpty) return;

    List<Map<String, dynamic>> remainingHistory = [];

    // Reverse iterate so we undo the most recent renames first (though order shouldn't strictly matter here)
    for (var entry in history.reversed) {
      final String? originalPath = entry['originalPath'];
      final String? renamedPath = entry['renamedPath'];

      if (originalPath != null && renamedPath != null) {
        final renamedFile = File(renamedPath);
        if (await renamedFile.exists()) {
          try {
            await renamedFile.rename(originalPath);
          } catch (e) {
            remainingHistory.add(entry);
          }
        } else {
          remainingHistory.add(entry);
        }
      } else {
        remainingHistory.add(entry);
      }
    }

    final logFile = File(p.join(mediaFolderPath, 'rename_history.json'));
    if (remainingHistory.isEmpty) {
      if (await logFile.exists()) {
        await logFile.delete();
      }
    } else {
      // Re-reverse to keep chronological order
      await logFile.writeAsString(const JsonEncoder.withIndent('  ').convert(remainingHistory.reversed.toList()));
    }
  }
}
