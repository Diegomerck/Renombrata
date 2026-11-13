/// Model representing metadata for DigitalLogic 3.2 / Proforma_DL XML sidecars.
class ProformaDlMetadata {
  String filePath;
  String originalFileName;
  String produccionNombre;
  String convencionNombre;
  String clipName;
  String subConvention;
  String fuente;
  String ubicacion;
  String temporalidad;
  bool tomaSeleccionada;
  String pais;
  String ciudad;
  String lugar;
  String vfxCompuestos;
  String descripcionVfx;
  String observacionesVideo;
  String observacionesAudio;
  String sinopsis;
  String operadorIngesta;

  // Breakdown fields used to assemble convention and sub-convention
  String chapter;
  String scene;
  String take;
  String camera;
  String day;
  String unitCard;
  String cardNumber;
  int clipSequenceNumber;
  String unitSubId;

  ProformaDlMetadata({
    required this.filePath,
    required this.originalFileName,
    required this.produccionNombre,
    required this.convencionNombre,
    required this.clipName,
    required this.subConvention,
    this.fuente = 'Portátil',
    this.ubicacion = 'Exterior',
    this.temporalidad = 'Día',
    this.tomaSeleccionada = true,
    this.pais = 'MEXICO',
    this.ciudad = 'CDMX',
    this.lugar = '',
    this.vfxCompuestos = 'No',
    this.descripcionVfx = '',
    this.observacionesVideo = 'OK SLOG 3',
    this.observacionesAudio = 'MIX Y MULTITRACK',
    this.sinopsis = '',
    this.operadorIngesta = '',
    this.chapter = '',
    this.scene = '',
    this.take = 'T1',
    this.camera = 'CAM1',
    this.day = 'D01',
    this.unitCard = 'U1',
    this.cardNumber = '1',
    this.clipSequenceNumber = 1,
    this.unitSubId = 'U1B',
  });

  ProformaDlMetadata copyWith({
    String? filePath,
    String? originalFileName,
    String? produccionNombre,
    String? convencionNombre,
    String? clipName,
    String? subConvention,
    String? fuente,
    String? ubicacion,
    String? temporalidad,
    bool? tomaSeleccionada,
    String? pais,
    String? ciudad,
    String? lugar,
    String? vfxCompuestos,
    String? descripcionVfx,
    String? observacionesVideo,
    String? observacionesAudio,
    String? sinopsis,
    String? operadorIngesta,
    String? chapter,
    String? scene,
    String? take,
    String? camera,
    String? day,
    String? unitCard,
    String? cardNumber,
    int? clipSequenceNumber,
    String? unitSubId,
  }) {
    return ProformaDlMetadata(
      filePath: filePath ?? this.filePath,
      originalFileName: originalFileName ?? this.originalFileName,
      produccionNombre: produccionNombre ?? this.produccionNombre,
      convencionNombre: convencionNombre ?? this.convencionNombre,
      clipName: clipName ?? this.clipName,
      subConvention: subConvention ?? this.subConvention,
      fuente: fuente ?? this.fuente,
      ubicacion: ubicacion ?? this.ubicacion,
      temporalidad: temporalidad ?? this.temporalidad,
      tomaSeleccionada: tomaSeleccionada ?? this.tomaSeleccionada,
      pais: pais ?? this.pais,
      ciudad: ciudad ?? this.ciudad,
      lugar: lugar ?? this.lugar,
      vfxCompuestos: vfxCompuestos ?? this.vfxCompuestos,
      descripcionVfx: descripcionVfx ?? this.descripcionVfx,
      observacionesVideo: observacionesVideo ?? this.observacionesVideo,
      observacionesAudio: observacionesAudio ?? this.observacionesAudio,
      sinopsis: sinopsis ?? this.sinopsis,
      operadorIngesta: operadorIngesta ?? this.operadorIngesta,
      chapter: chapter ?? this.chapter,
      scene: scene ?? this.scene,
      take: take ?? this.take,
      camera: camera ?? this.camera,
      day: day ?? this.day,
      unitCard: unitCard ?? this.unitCard,
      cardNumber: cardNumber ?? this.cardNumber,
      clipSequenceNumber: clipSequenceNumber ?? this.clipSequenceNumber,
      unitSubId: unitSubId ?? this.unitSubId,
    );
  }
}
