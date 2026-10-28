import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/services/digitallogic_xml_service.dart';

void main() {
  group('DigitalLogicXmlService - generateXml', () {
    test('generates valid DigitalLogic 4.0 XML structure with all required fields', () {
      final xml = DigitalLogicXmlService.generateXml(
        productionName: 'LUZ DE MIS NOCHES',
        chapter: '16',
        scene: '12',
        plane: '1',
        take: 'T1',
        cameraReel: 'A001',
        clipIndex: '2',
        shootingDay: 'D24',
        unit: 'F11',
        conventionName: 'LUZDMIN_16_12_T1_NFF_2_D24_F11',
        proformaName: 'LUZDMIN_16_12_T1_NFF_2_D24_F11%1_2_D24_F11',
        originalClipName: 'LUZDMIN_221026_NFF_0002',
        isSelectedTake: true,
        cameraType: 'DIGITAL',
        notes: 'Director note here',
        recordingDate: DateTime(2026, 10, 22, 18, 51, 51),
      );

      expect(xml, contains('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(xml, contains('<digitallogic version="4.0">'));
      expect(xml, contains('<produccionNombre>LUZ DE MIS NOCHES</produccionNombre>'));
      expect(xml, contains('<capitulo>16</capitulo>'));
      expect(xml, contains('<escena>12</escena>'));
      expect(xml, contains('<plano>1</plano>'));
      expect(xml, contains('<toma>T1</toma>'));
      expect(xml, contains('<camara>A001</camara>'));
      expect(xml, contains('<clipIndex>2</clipIndex>'));
      expect(xml, contains('<diaGrabacion>D24</diaGrabacion>'));
      expect(xml, contains('<unidad>F11</unidad>'));
      expect(xml, contains('<convencionNombre>LUZDMIN_16_12_T1_NFF_2_D24_F11</convencionNombre>'));
      expect(xml, contains('<proformaNombre>LUZDMIN_16_12_T1_NFF_2_D24_F11%1_2_D24_F11</proformaNombre>'));
      expect(xml, contains('<clipName>LUZDMIN_221026_NFF_0002</clipName>'));
      expect(xml, contains('<tomaSeleccionada>SI</tomaSeleccionada>'));
      expect(xml, contains('<tipoCamara>DIGITAL</tipoCamara>'));
      expect(xml, contains('<descripcion>Director note here</descripcion>'));
      expect(xml, contains('<fechaGrabacion>2026-10-22 18:51:51.000</fechaGrabacion>'));
      expect(xml, contains('</metadata>'));
      expect(xml, contains('</clip>'));
      expect(xml, contains('</digitallogic>'));
    });

    test('handles default fallbacks: isSelectedTake false, plane null, date null, empty notes', () {
      final xml = DigitalLogicXmlService.generateXml(
        productionName: 'MY PROD',
        chapter: '1',
        scene: '5',
        take: '1',
        cameraReel: 'A001',
        clipIndex: '001',
        shootingDay: 'D01',
        unit: 'U1',
        conventionName: 'MYPROD_01_05_T1_A001_D01_U1',
        proformaName: 'MYPROD_01_05_T1_A001_D01_U1%A001_001_D01_U1',
        originalClipName: 'A001C001.MP4',
      );

      expect(xml, contains('<tomaSeleccionada>NO</tomaSeleccionada>'));
      expect(xml, contains('<plano></plano>'));
      expect(xml, contains('<tipoCamara>DIGITAL</tipoCamara>'));
      expect(xml, contains('<descripcion></descripcion>'));
      expect(xml, contains('<fechaGrabacion></fechaGrabacion>'));
    });

    test('escapes special XML characters in string fields', () {
      final xml = DigitalLogicXmlService.generateXml(
        productionName: 'Tom & Jerry <Live> "Special"',
        chapter: '1',
        scene: '2 & 3',
        plane: '<A>',
        take: 'T"1"',
        cameraReel: "A'01",
        clipIndex: '1',
        shootingDay: 'D01',
        unit: 'U1',
        conventionName: 'TEST & PROD',
        proformaName: 'TEST & PROD%U1',
        originalClipName: 'clip<1>.mov',
        notes: "Don't forget & remember <notes>",
      );

      expect(xml, contains('<produccionNombre>Tom &amp; Jerry &lt;Live&gt; &quot;Special&quot;</produccionNombre>'));
      expect(xml, contains('<escena>2 &amp; 3</escena>'));
      expect(xml, contains('<plano>&lt;A&gt;</plano>'));
      expect(xml, contains('<toma>T&quot;1&quot;</toma>'));
      expect(xml, contains("<camara>A&apos;01</camara>"));
      expect(xml, contains('<clipName>clip&lt;1&gt;.mov</clipName>'));
      expect(xml, contains("<descripcion>Don&apos;t forget &amp; remember &lt;notes&gt;</descripcion>"));
    });
  });

  group('DigitalLogicXmlService - writeXmlSidecar', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('digitallogic_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writes XML sidecar file adjacent to media file', () async {
      final mediaFile = File(p.join(tempDir.path, 'A001C001_260608ZY.MP4'));
      await mediaFile.writeAsString('video data placeholder');

      const xmlContent = '<digitallogic version="4.0"></digitallogic>';
      final savedFile = await DigitalLogicXmlService.writeXmlSidecar(
        mediaFilePath: mediaFile.path,
        xmlContent: xmlContent,
      );

      final expectedSidecarPath = p.join(tempDir.path, 'A001C001_260608ZY.xml');
      expect(savedFile.path, equals(expectedSidecarPath));
      expect(await savedFile.exists(), isTrue);
      expect(await savedFile.readAsString(), equals(xmlContent));
    });

    test('throws FileSystemException if sidecar exists and overwrite is false', () async {
      final mediaFile = File(p.join(tempDir.path, 'A001C002.MOV'));
      await mediaFile.writeAsString('video data');

      final sidecarFile = File(p.join(tempDir.path, 'A001C002.xml'));
      await sidecarFile.writeAsString('existing content');

      expect(
        () => DigitalLogicXmlService.writeXmlSidecar(
          mediaFilePath: mediaFile.path,
          xmlContent: '<new_xml/>',
          overwrite: false,
        ),
        throwsA(isA<FileSystemException>()),
      );

      // Verify original content is untouched
      expect(await sidecarFile.readAsString(), equals('existing content'));
    });

    test('overwrites existing sidecar file when overwrite is true', () async {
      final mediaFile = File(p.join(tempDir.path, 'A001C003.MXF'));
      await mediaFile.writeAsString('video data');

      final sidecarFile = File(p.join(tempDir.path, 'A001C003.xml'));
      await sidecarFile.writeAsString('old content');

      final savedFile = await DigitalLogicXmlService.writeXmlSidecar(
        mediaFilePath: mediaFile.path,
        xmlContent: '<updated_xml/>',
        overwrite: true,
      );

      expect(await savedFile.readAsString(), equals('<updated_xml/>'));
    });
  });
}
