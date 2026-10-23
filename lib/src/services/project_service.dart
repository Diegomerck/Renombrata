import 'dart:convert';
import 'dart:io';
import 'package:renombrata/src/models/renombrata_project.dart';

class ProjectService {
  /// Loads a .renombrata file from the disk and parses it into a RenombrataProject
  static Future<RenombrataProject> loadProject(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('El archivo de proyecto no existe: $path');
    }

    final contents = await file.readAsString();
    final json = jsonDecode(contents) as Map<String, dynamic>;
    return RenombrataProject.fromJson(json);
  }

  /// Saves a RenombrataProject to the disk at the specified path
  static Future<void> saveProject(RenombrataProject project, String path) async {
    final file = File(path);
    
    // Update the lastModified timestamp right before saving
    final projectToSave = project.copyWith(
      lastModified: DateTime.now().toUtc().toIso8601String(),
    );

    final jsonString = jsonEncode(projectToSave.toJson());
    await file.writeAsString(jsonString);
  }
}
