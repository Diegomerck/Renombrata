
import 'package:renombrata/src/models/shooting_log.dart';

class RenombrataProject {
  final String version;
  final String lastModified;
  final ShootingLog log;
  final String defaultReel;
  final String activeCamera;
  final List<String> cameraNames;
  final bool autoSortByClip;

  RenombrataProject({
    this.version = "2.0",
    String? lastModified,
    required this.log,
    required this.defaultReel,
    required this.activeCamera,
    this.cameraNames = const ['A', 'B', 'C'],
    this.autoSortByClip = true,
  }) : lastModified = lastModified ?? DateTime.now().toUtc().toIso8601String();

  RenombrataProject copyWith({
    String? version,
    String? lastModified,
    ShootingLog? log,
    String? defaultReel,
    String? activeCamera,
    List<String>? cameraNames,
    bool? autoSortByClip,
  }) {
    return RenombrataProject(
      version: version ?? this.version,
      lastModified: lastModified ?? this.lastModified,
      log: log ?? this.log,
      defaultReel: defaultReel ?? this.defaultReel,
      activeCamera: activeCamera ?? this.activeCamera,
      cameraNames: cameraNames ?? this.cameraNames,
      autoSortByClip: autoSortByClip ?? this.autoSortByClip,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'lastModified': lastModified,
    'metadata': log.metadata.toJson(),
    'defaultReel': defaultReel,
    'activeCamera': activeCamera,
    'cameraNames': cameraNames,
    'autoSortByClip': autoSortByClip,
    'records': log.records.map((r) => r.toJson()).toList(),
  };

  factory RenombrataProject.fromJson(Map<String, dynamic> json) {
    return RenombrataProject(
      version: json['version'] as String? ?? "2.0",
      lastModified: json['lastModified'] as String?,
      log: ShootingLog(
        metadata: ShootingLogMetadata.fromJson(json['metadata'] as Map<String, dynamic>? ?? {}),
        records: (json['records'] as List<dynamic>?)
            ?.map((e) => ShotRecord.fromJson(e as Map<String, dynamic>))
            .toList() ?? [],
      ),
      defaultReel: (json['defaultReel'] as String? ?? '').isNotEmpty
          ? json['defaultReel'] as String
          : '001',
      activeCamera: json['activeCamera'] as String? ?? 'A',
      cameraNames: (json['cameraNames'] as List<dynamic>?)?.map((e) => e as String).toList() ?? ['A', 'B', 'C'],
      autoSortByClip: json['autoSortByClip'] as bool? ?? true,
    );
  }
}
