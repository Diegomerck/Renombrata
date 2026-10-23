import 'package:uuid/uuid.dart';

class ShootingLogMetadata {
  final String nomenclature;
  final String date;
  final String unit;
  final String day;
  final String producer;
  final String production;
  final String location;
  final String audioFormat;
  final String frameRate;
  final String videoCodec;
  final String responsibleEngineer;
  final String ingestor;

  ShootingLogMetadata({
    required this.nomenclature,
    required this.date,
    required this.unit,
    required this.day,
    required this.producer,
    required this.production,
    required this.location,
    required this.audioFormat,
    required this.frameRate,
    required this.videoCodec,
    required this.responsibleEngineer,
    required this.ingestor,
  });

  factory ShootingLogMetadata.empty() {
    return ShootingLogMetadata(
      nomenclature: '',
      date: '',
      unit: '',
      day: '',
      producer: '',
      production: '',
      location: '',
      audioFormat: '',
      frameRate: '23.98',
      videoCodec: '',
      responsibleEngineer: '',
      ingestor: '',
    );
  }

  ShootingLogMetadata copyWith({
    String? nomenclature,
    String? date,
    String? unit,
    String? day,
    String? producer,
    String? production,
    String? location,
    String? audioFormat,
    String? frameRate,
    String? videoCodec,
    String? responsibleEngineer,
    String? ingestor,
  }) {
    return ShootingLogMetadata(
      nomenclature: nomenclature ?? this.nomenclature,
      date: date ?? this.date,
      unit: unit ?? this.unit,
      day: day ?? this.day,
      producer: producer ?? this.producer,
      production: production ?? this.production,
      location: location ?? this.location,
      audioFormat: audioFormat ?? this.audioFormat,
      frameRate: frameRate ?? this.frameRate,
      videoCodec: videoCodec ?? this.videoCodec,
      responsibleEngineer: responsibleEngineer ?? this.responsibleEngineer,
      ingestor: ingestor ?? this.ingestor,
    );
  }

  Map<String, dynamic> toJson() => {
    'nomenclature': nomenclature,
    'date': date,
    'unit': unit,
    'day': day,
    'producer': producer,
    'production': production,
    'location': location,
    'audioFormat': audioFormat,
    'frameRate': frameRate,
    'videoCodec': videoCodec,
    'responsibleEngineer': responsibleEngineer,
    'ingestor': ingestor,
  };

  factory ShootingLogMetadata.fromJson(Map<String, dynamic> json) => ShootingLogMetadata(
    nomenclature: json['nomenclature'] as String? ?? '',
    date: json['date'] as String? ?? '',
    unit: json['unit'] as String? ?? '',
    day: json['day'] as String? ?? '',
    producer: json['producer'] as String? ?? '',
    production: json['production'] as String? ?? '',
    location: json['location'] as String? ?? '',
    audioFormat: json['audioFormat'] as String? ?? json['format'] as String? ?? '',
    frameRate: json['frameRate'] as String? ?? '',
    videoCodec: json['videoCodec'] as String? ?? '',
    responsibleEngineer: json['responsibleEngineer'] as String? ?? '',
    ingestor: json['ingestor'] as String? ?? '',
  );
}

class CameraTakeRecord {
  final String cameraName;
  final String clipName;

  CameraTakeRecord({
    required this.cameraName,
    required this.clipName,
  });

  CameraTakeRecord copyWith({
    String? cameraName,
    String? clipName,
  }) {
    return CameraTakeRecord(
      cameraName: cameraName ?? this.cameraName,
      clipName: clipName ?? this.clipName,
    );
  }

  Map<String, dynamic> toJson() => {
    'cameraName': cameraName,
    'clipName': clipName,
  };

  factory CameraTakeRecord.fromJson(Map<String, dynamic> json) => CameraTakeRecord(
    cameraName: json['cameraName'] as String? ?? '',
    clipName: json['clipName'] as String? ?? '',
  );
}

class ShotRecord {
  final String id;
  final String chapter;
  final String scene;
  final String? plane;
  final String take;
  final List<CameraTakeRecord> cameras;
  final String reel;
  final String? tcIn;
  final String? tcOut;
  final String? observations;
  final bool isMos;

  String? get notes => observations;

  ShotRecord({
    String? id,
    required this.chapter,
    required this.scene,
    this.plane,
    required this.take,
    required this.cameras,
    required this.reel,
    this.tcIn,
    this.tcOut,
    this.observations,
    this.isMos = false,
  }) : id = id ?? Uuid().v4();

  ShotRecord copyWith({
    String? id,
    String? chapter,
    String? scene,
    String? plane,
    String? take,
    List<CameraTakeRecord>? cameras,
    String? reel,
    String? tcIn,
    String? tcOut,
    String? observations,
    bool? isMos,
  }) {
    return ShotRecord(
      id: id ?? this.id,
      chapter: chapter ?? this.chapter,
      scene: scene ?? this.scene,
      plane: plane ?? this.plane,
      take: take ?? this.take,
      cameras: cameras ?? this.cameras,
      reel: reel ?? this.reel,
      tcIn: tcIn ?? this.tcIn,
      tcOut: tcOut ?? this.tcOut,
      observations: observations ?? this.observations,
      isMos: isMos ?? this.isMos,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'chapter': chapter,
    'scene': scene,
    'plane': plane ?? '',
    'take': take,
    'cameras': cameras.map((c) => c.toJson()).toList(),
    'reel': reel,
    'tcIn': tcIn ?? '',
    'tcOut': tcOut ?? '',
    'observations': observations ?? '',
    'isMos': isMos,
  };

  factory ShotRecord.fromJson(Map<String, dynamic> json) => ShotRecord(
    id: json['id'] as String?,
    chapter: json['chapter'] as String? ?? '',
    scene: json['scene'] as String? ?? '',
    plane: (json['plane'] == null || json['plane'] == '') ? null : json['plane'] as String,
    take: json['take'] as String? ?? '',
    cameras: (json['cameras'] as List<dynamic>?)
            ?.map((e) => CameraTakeRecord.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    reel: json['reel'] as String? ?? '',
    tcIn: (json['tcIn'] == null || json['tcIn'] == '') ? null : json['tcIn'] as String,
    tcOut: (json['tcOut'] == null || json['tcOut'] == '') ? null : json['tcOut'] as String,
    observations: (json['observations'] == null || json['observations'] == '') ? null : json['observations'] as String,
    isMos: json['isMos'] as bool? ?? false,
  );
}

class ShootingLog {
  final ShootingLogMetadata metadata;
  final List<ShotRecord> records;

  ShootingLog({
    required this.metadata,
    required this.records,
  });

  ShootingLog copyWith({
    ShootingLogMetadata? metadata,
    List<ShotRecord>? records,
  }) {
    return ShootingLog(
      metadata: metadata ?? this.metadata,
      records: records ?? this.records,
    );
  }

  Map<String, dynamic> toJson() => {
    'metadata': metadata.toJson(),
    'records': records.map((r) => r.toJson()).toList(),
  };

  factory ShootingLog.fromJson(Map<String, dynamic> json) => ShootingLog(
    metadata: ShootingLogMetadata.fromJson(json['metadata'] as Map<String, dynamic>? ?? {}),
    records: (json['records'] as List<dynamic>?)
            ?.map((e) => ShotRecord.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
