
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
  final bool showDs;
  final bool showFf;
  final bool showGpr;
  final bool showDr;
  final bool showTf;
  final bool showTcOut;
  final List<String> bitacoraElementOrder;
  final List<String> conventionNameOrder;

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
    this.showDs = true,
    this.showFf = true,
    this.showGpr = true,
    this.showDr = true,
    this.showTf = true,
    this.showTcOut = true,
    this.bitacoraElementOrder = const ['capitulo', 'escena', 'plano', 'toma'],
    this.conventionNameOrder = const ['capitulo', 'escena', 'plano', 'toma'],
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
    bool? showDs,
    bool? showFf,
    bool? showGpr,
    bool? showDr,
    bool? showTf,
    bool? showTcOut,
    List<String>? bitacoraElementOrder,
    List<String>? conventionNameOrder,
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
      showDs: showDs ?? this.showDs,
      showFf: showFf ?? this.showFf,
      showGpr: showGpr ?? this.showGpr,
      showDr: showDr ?? this.showDr,
      showTf: showTf ?? this.showTf,
      showTcOut: showTcOut ?? this.showTcOut,
      bitacoraElementOrder: bitacoraElementOrder ?? this.bitacoraElementOrder,
      conventionNameOrder: conventionNameOrder ?? this.conventionNameOrder,
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
    'showDs': showDs,
    'showFf': showFf,
    'showGpr': showGpr,
    'showDr': showDr,
    'showTf': showTf,
    'showTcOut': showTcOut,
    'bitacoraElementOrder': bitacoraElementOrder,
    'conventionNameOrder': conventionNameOrder,
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
      showDs: json['showDs'] as bool? ?? true,
      showFf: json['showFf'] as bool? ?? true,
      showGpr: json['showGpr'] as bool? ?? true,
      showDr: json['showDr'] as bool? ?? true,
      showTf: json['showTf'] as bool? ?? true,
      showTcOut: json['showTcOut'] as bool? ?? true,
      bitacoraElementOrder: (json['bitacoraElementOrder'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const ['capitulo', 'escena', 'plano', 'toma'],
      conventionNameOrder: (json['conventionNameOrder'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const ['capitulo', 'escena', 'plano', 'toma'],
    );
  }
}
