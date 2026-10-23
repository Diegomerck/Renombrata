
import 'package:renombrata/src/models/shooting_log.dart';

class RenombrataProject {
  final String version;
  final String lastModified;
  final ShootingLog log;
  final String defaultReel;
  final String activeCamera;
  final List<String> cameraNames;
  final bool autoSortByClip;
  final bool showChapter;
  final bool showPlane;
  final bool showMos;
  final bool showTcOut;

  RenombrataProject({
    this.version = "2.0",
    String? lastModified,
    required this.log,
    required this.defaultReel,
    required this.activeCamera,
    this.cameraNames = const ['A', 'B', 'C'],
    this.autoSortByClip = true,
    this.showChapter = true,
    this.showPlane = true,
    this.showMos = true,
    this.showTcOut = true,
  }) : lastModified = lastModified ?? DateTime.now().toUtc().toIso8601String();

  RenombrataProject copyWith({
    String? version,
    String? lastModified,
    ShootingLog? log,
    String? defaultReel,
    String? activeCamera,
    List<String>? cameraNames,
    bool? autoSortByClip,
    bool? showChapter,
    bool? showPlane,
    bool? showMos,
    bool? showTcOut,
  }) {
    return RenombrataProject(
      version: version ?? this.version,
      lastModified: lastModified ?? this.lastModified,
      log: log ?? this.log,
      defaultReel: defaultReel ?? this.defaultReel,
      activeCamera: activeCamera ?? this.activeCamera,
      cameraNames: cameraNames ?? this.cameraNames,
      autoSortByClip: autoSortByClip ?? this.autoSortByClip,
      showChapter: showChapter ?? this.showChapter,
      showPlane: showPlane ?? this.showPlane,
      showMos: showMos ?? this.showMos,
      showTcOut: showTcOut ?? this.showTcOut,
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
    'showChapter': showChapter,
    'showPlane': showPlane,
    'showMos': showMos,
    'showTcOut': showTcOut,
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
      showChapter: json['showChapter'] as bool? ?? true,
      showPlane: json['showPlane'] as bool? ?? true,
      showMos: json['showMos'] as bool? ?? true,
      showTcOut: json['showTcOut'] as bool? ?? true,
    );
  }
}
