class ShootingLogMetadata {
  final String nomenclature;
  final String date;
  final String unit;
  final String day;
  final String producer;
  final String production;
  final String location;
  final String format;
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
    required this.format,
    required this.responsibleEngineer,
    required this.ingestor,
  });
}

class CameraTakeRecord {
  final String cameraName;
  final String clipName;

  CameraTakeRecord({
    required this.cameraName,
    required this.clipName,
  });
}

class ShotRecord {
  final String chapter;
  final String scene;
  final String? plane;
  final String take;
  final List<CameraTakeRecord> cameras;
  final String reel;
  final String? tcIn;
  final String? tcOut;
  final String? observations;

  ShotRecord({
    required this.chapter,
    required this.scene,
    this.plane,
    required this.take,
    required this.cameras,
    required this.reel,
    this.tcIn,
    this.tcOut,
    this.observations,
  });
}

class ShootingLog {
  final ShootingLogMetadata metadata;
  final List<ShotRecord> records;

  ShootingLog({
    required this.metadata,
    required this.records,
  });
}
