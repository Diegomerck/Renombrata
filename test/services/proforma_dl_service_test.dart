import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/services/digitallogic_xml_service.dart';
import 'package:renombrata/src/services/proforma_dl_service.dart';

void main() {
  group('DigitalLogic 3.2 Proforma_DL XML Generation', () {
    test('generates XML strictly matching the post-production Proforma_DL schema', () {
      final xml = DigitalLogicXmlService.generateProformaDlXml(
        produccionNombre: 'INOCENCIA ',
        convencionNombre: 'INOCENCIA_01_15_PROT1_CAM1_D03_UCR14%1_6_D03_U14B',
        clipName: 'INOCENCIA_01_15_PROT1_CAM1_D03_UCR14',
        fuente: 'Portátil',
        ubicacion: 'Exterior',
        temporalidad: 'Día',
        tomaSeleccionada: true,
        pais: 'MEXICO ',
        ciudad: 'CDMX ',
        lugar: 'TERMINAL DE AUTOBUSES DEL SUR',
        vfxCompuestos: 'No',
        descripcionVfx: '',
        observacionesVideo: 'OK SLOG 3',
        observacionesAudio: ' MIX Y MULTITRACK',
        sinopsis: 'LLEGA INOCENCIA EN AUTOBUS ',
        operadorIngesta: 'ANGEL ESTRADA DIAZ ',
      );

      final expectedXml = '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
          '<!DOCTYPE Proforma_DL>\n'
          '<digitallogic version="3.2">\n'
          '    <clip>\n'
          '        <metadata>\n'
          '            <produccionNombre>INOCENCIA </produccionNombre>\n'
          '            <convencionNombre>INOCENCIA_01_15_PROT1_CAM1_D03_UCR14%1_6_D03_U14B</convencionNombre>\n'
          '            <clipName>INOCENCIA_01_15_PROT1_CAM1_D03_UCR14</clipName>\n'
          '            <fuente>Portátil</fuente>\n'
          '            <ubicacion>Exterior</ubicacion>\n'
          '            <temporalidad>Día</temporalidad>\n'
          '            <tomaSeleccionada>SÍ</tomaSeleccionada>\n'
          '            <pais>MEXICO </pais>\n'
          '            <ciudad>CDMX </ciudad>\n'
          '            <lugar>TERMINAL DE AUTOBUSES DEL SUR</lugar>\n'
          '            <vfxCompuestos>No</vfxCompuestos>\n'
          '            <descripcionVfx/>\n'
          '            <observacionesVideo>OK SLOG 3</observacionesVideo>\n'
          '            <observacionesAudio> MIX Y MULTITRACK</observacionesAudio>\n'
          '            <sinopsis>LLEGA INOCENCIA EN AUTOBUS </sinopsis>\n'
          '            <operadorIngesta>ANGEL ESTRADA DIAZ </operadorIngesta>\n'
          '        </metadata>\n'
          '    </clip>\n'
          '</digitallogic>\n';

      expect(xml, equals(expectedXml));
    });

    test('renders self-closing <descripcionVfx/> when empty, and full tag with content when present', () {
      final xmlEmpty = DigitalLogicXmlService.generateProformaDlXml(
        produccionNombre: 'TEST',
        convencionNombre: 'TEST%1_1_D01_U1B',
        clipName: 'TEST',
        descripcionVfx: '   ',
      );
      expect(xmlEmpty, contains('<descripcionVfx/>'));

      final xmlFilled = DigitalLogicXmlService.generateProformaDlXml(
        produccionNombre: 'TEST',
        convencionNombre: 'TEST%1_1_D01_U1B',
        clipName: 'TEST',
        descripcionVfx: 'Wire removal on right crane',
      );
      expect(xmlFilled, contains('<descripcionVfx>Wire removal on right crane</descripcionVfx>'));
    });

    test('renders tomaSeleccionada as SÍ or NO properly', () {
      final xmlSi = DigitalLogicXmlService.generateProformaDlXml(
        produccionNombre: 'TEST',
        convencionNombre: 'TEST%1_1_D01_U1B',
        clipName: 'TEST',
        tomaSeleccionada: true,
      );
      expect(xmlSi, contains('<tomaSeleccionada>SÍ</tomaSeleccionada>'));

      final xmlNo = DigitalLogicXmlService.generateProformaDlXml(
        produccionNombre: 'TEST',
        convencionNombre: 'TEST%1_1_D01_U1B',
        clipName: 'TEST',
        tomaSeleccionada: false,
      );
      expect(xmlNo, contains('<tomaSeleccionada>NO</tomaSeleccionada>'));
    });

    test('escapes XML special characters in metadata fields', () {
      final xml = DigitalLogicXmlService.generateProformaDlXml(
        produccionNombre: 'Luz & Sombras <2026>',
        convencionNombre: 'CONV_1%1_1_D01_U1B',
        clipName: 'CLIP "SPECIAL"',
        lugar: 'Bar & Grill "El Gallo"',
        sinopsis: "Actor's entrance <stunt>",
        descripcionVfx: 'Green screen & clean plate',
      );

      expect(xml, contains('<produccionNombre>Luz &amp; Sombras &lt;2026&gt;</produccionNombre>'));
      expect(xml, contains('<clipName>CLIP &quot;SPECIAL&quot;</clipName>'));
      expect(xml, contains('<lugar>Bar &amp; Grill &quot;El Gallo&quot;</lugar>'));
      expect(xml, contains("<sinopsis>Actor&apos;s entrance &lt;stunt&gt;</sinopsis>"));
      expect(xml, contains('<descripcionVfx>Green screen &amp; clean plate</descripcionVfx>'));
    });
  });

  group('Convention Filename Parser & Sub-convention Generator', () {
    test('parses standard convention filename: INOCENCIA_01_15_PROT1_CAM1_D03_UCR14.mxf', () {
      final parsed = ProformaDlService.parseConventionFilename(
        'INOCENCIA_01_15_PROT1_CAM1_D03_UCR14.mxf',
      );

      expect(parsed.production, equals('INOCENCIA'));
      expect(parsed.chapter, equals('01'));
      expect(parsed.scene, equals('15'));
      expect(parsed.take, equals('PROT1'));
      expect(parsed.camera, equals('CAM1'));
      expect(parsed.day, equals('D03'));
      expect(parsed.unitCard, equals('UCR14'));
      expect(parsed.clipName, equals('INOCENCIA_01_15_PROT1_CAM1_D03_UCR14'));
      expect(parsed.existingSubConvention, isNull);
    });

    test('parses joined scene: INOCENCIA_01_06Y08_T2_CAM1_D03_UCR14.mov', () {
      final parsed = ProformaDlService.parseConventionFilename(
        'INOCENCIA_01_06Y08_T2_CAM1_D03_UCR14.mov',
      );

      expect(parsed.production, equals('INOCENCIA'));
      expect(parsed.chapter, equals('01'));
      expect(parsed.scene, equals('06Y08'));
      expect(parsed.take, equals('T2'));
      expect(parsed.camera, equals('CAM1'));
      expect(parsed.day, equals('D03'));
      expect(parsed.unitCard, equals('UCR14'));
    });

    test('parses extended take: INOCENCIA_01_15_PROT1_A_CAM1_D03_UCR14.mxf', () {
      final parsed = ProformaDlService.parseConventionFilename(
        'INOCENCIA_01_15_PROT1_A_CAM1_D03_UCR14.mxf',
      );

      expect(parsed.production, equals('INOCENCIA'));
      expect(parsed.chapter, equals('01'));
      expect(parsed.scene, equals('15'));
      expect(parsed.take, equals('PROT1_A'));
      expect(parsed.camera, equals('CAM1'));
      expect(parsed.day, equals('D03'));
      expect(parsed.unitCard, equals('UCR14'));
    });

    test('parses sequence and OK takes: SEC1 and T1OK', () {
      final parsedSec = ProformaDlService.parseConventionFilename(
        'INOCENCIA_01_15_SEC1_CAM1_D03_UCR14.mp4',
      );
      expect(parsedSec.take, equals('SEC1'));

      final parsedOk = ProformaDlService.parseConventionFilename(
        'INOCENCIA_01_15_T1OK_CAM1_D03_UCR14.mxf',
      );
      expect(parsedOk.take, equals('T1OK'));
    });

    test('parses filename containing already existing sub-convention with %', () {
      final parsed = ProformaDlService.parseConventionFilename(
        'INOCENCIA_01_15_PROT1_CAM1_D03_UCR14%1_6_D03_U14B.mxf',
      );

      expect(parsed.production, equals('INOCENCIA'));
      expect(parsed.chapter, equals('01'));
      expect(parsed.scene, equals('15'));
      expect(parsed.take, equals('PROT1'));
      expect(parsed.camera, equals('CAM1'));
      expect(parsed.day, equals('D03'));
      expect(parsed.unitCard, equals('UCR14'));
      expect(parsed.clipName, equals('INOCENCIA_01_15_PROT1_CAM1_D03_UCR14'));
      expect(parsed.existingSubConvention, equals('1_6_D03_U14B'));
    });

    test('builds sub-convention and full convention with % correctly', () {
      final sub = ProformaDlService.buildSubConvention(
        cardNumber: '1',
        clipSequenceNumber: 6,
        day: 'D03',
        unitSubId: 'U14B',
      );
      expect(sub, equals('1_6_D03_U14B'));

      final full = ProformaDlService.buildFullConvention(
        clipName: 'INOCENCIA_01_15_PROT1_CAM1_D03_UCR14',
        subConvention: sub,
      );
      expect(
        full,
        equals('INOCENCIA_01_15_PROT1_CAM1_D03_UCR14%1_6_D03_U14B'),
      );
    });

    test('extracts card number and derives sub-reel ID from unitCard', () {
      expect(ProformaDlService.extractCardNumber('CAM1'), equals('1'));
      expect(ProformaDlService.extractCardNumber('A001'), equals('1'));
      expect(ProformaDlService.extractCardNumber('CAMA'), equals('1'));

      expect(ProformaDlService.deriveSubReelId('UCR14'), equals('U14B'));
      expect(ProformaDlService.deriveSubReelId('U14'), equals('U14B'));
      expect(ProformaDlService.deriveSubReelId('U14B'), equals('U14B'));
      expect(ProformaDlService.deriveSubReelId('U11B'), equals('U11B'));
      expect(ProformaDlService.deriveSubReelId('DS'), equals('DSB'));
      expect(ProformaDlService.extractCardNumber('PORT16'), equals('16'));
    });

    test('parses INFAM_32_2_T1_PORT16_13_D40_U11B and derives dynamic sub-convention 16_1_D40_U11B', () {
      final parsed = ProformaDlService.parseConventionFilename(
        'INFAM_32_2_T1_PORT16_13_D40_U11B.mxf',
      );

      expect(parsed.production, equals('INFAM'));
      expect(parsed.chapter, equals('32'));
      expect(parsed.scene, equals('2'));
      expect(parsed.take, equals('T1'));
      expect(parsed.camera, equals('PORT16'));
      expect(parsed.day, equals('D40'));
      expect(parsed.unitCard, equals('U11B'));
      expect(parsed.clipName, equals('INFAM_32_2_T1_PORT16_13_D40_U11B'));

      final meta = ProformaDlService.createMetadata(
        filePath: '/media/INFAM_32_2_T1_PORT16_13_D40_U11B.mxf',
      );
      expect(meta.clipName, equals('INFAM_32_2_T1_PORT16_13_D40_U11B'));
      expect(meta.subConvention, equals('16_1_D40_U11B'));
      expect(
        meta.convencionNombre,
        equals('INFAM_32_2_T1_PORT16_13_D40_U11B%16_1_D40_U11B'),
      );
      expect(meta.lugar, isEmpty);
      expect(meta.sinopsis, isEmpty);
      expect(meta.operadorIngesta, isEmpty);
      expect(meta.observacionesVideo, isEmpty);
      expect(meta.observacionesAudio, isEmpty);
      expect(meta.descripcionVfx, isEmpty);

      final cam1Meta = ProformaDlService.createMetadata(
        filePath: '/media/INFAM_32_2_T1_CAM1_13_D40_U11B.mxf',
      );
      expect(cam1Meta.subConvention, equals('1_1_D40_U11B'));
    });
  });

  group('Batch XML Sidecar Generation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('proforma_dl_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writes XML sidecar file with neutral empty tags when metadata is not supplied', () async {
      final mediaFile = File(p.join(tempDir.path, 'INFAM_32_2_T1_PORT16_13_D40_U11B.mxf'));
      await mediaFile.writeAsString('dummy mxf binary');

      final meta = ProformaDlService.createMetadata(
        filePath: mediaFile.path,
        clipSequenceNumber: 1,
      );

      final results = await ProformaDlService.batchGenerateSidecars(
        items: [meta],
        overwrite: true,
      );

      final expectedXmlPath = p.join(tempDir.path, 'INFAM_32_2_T1_PORT16_13_D40_U11B.xml');
      expect(results.containsKey(mediaFile.path), isTrue);
      final generatedFile = results[mediaFile.path]!;
      expect(generatedFile.path, equals(expectedXmlPath));
      expect(await generatedFile.exists(), isTrue);

      final content = await generatedFile.readAsString();
      expect(content, contains('<!DOCTYPE Proforma_DL>'));
      expect(content, contains('<digitallogic version="3.2">'));
      expect(content, contains('<produccionNombre>INFAM</produccionNombre>'));
      expect(
        content,
        contains('<convencionNombre>INFAM_32_2_T1_PORT16_13_D40_U11B%16_1_D40_U11B</convencionNombre>'),
      );
      expect(content, contains('<clipName>INFAM_32_2_T1_PORT16_13_D40_U11B</clipName>'));
      expect(content, contains('<lugar></lugar>'));
      expect(content, contains('<descripcionVfx/>'));
      expect(content, contains('<observacionesVideo></observacionesVideo>'));
      expect(content, contains('<observacionesAudio></observacionesAudio>'));
      expect(content, contains('<sinopsis></sinopsis>'));
      expect(content, contains('<operadorIngesta></operadorIngesta>'));
    });

    test('writes XML sidecar file with supplied batch metadata values', () async {
      final mediaFile = File(p.join(tempDir.path, 'INOCENCIA_01_15_PROT1_CAM1_D03_UCR14.mxf'));
      await mediaFile.writeAsString('dummy mxf binary');

      final meta = ProformaDlService.createMetadata(
        filePath: mediaFile.path,
        clipSequenceNumber: 6,
        defaultOperador: 'Operador Prueba',
        defaultPais: 'MEXICO',
        defaultCiudad: 'CDMX',
        defaultLugar: 'Locacion Central',
        defaultSinopsis: 'Entrada principal',
        defaultVideoObs: 'LOG C',
        defaultAudioObs: 'MIX',
      );

      final results = await ProformaDlService.batchGenerateSidecars(
        items: [meta],
        overwrite: true,
      );

      final generatedFile = results[mediaFile.path]!;
      final content = await generatedFile.readAsString();
      expect(content, contains('<convencionNombre>INOCENCIA_01_15_PROT1_CAM1_D03_UCR14%1_6_D03_U14B</convencionNombre>'));
      expect(content, contains('<lugar>Locacion Central</lugar>'));
      expect(content, contains('<observacionesVideo>LOG C</observacionesVideo>'));
      expect(content, contains('<observacionesAudio>MIX</observacionesAudio>'));
      expect(content, contains('<sinopsis>Entrada principal</sinopsis>'));
      expect(content, contains('<operadorIngesta>Operador Prueba</operadorIngesta>'));
    });
  });
}
