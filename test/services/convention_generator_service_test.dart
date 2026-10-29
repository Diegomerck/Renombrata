import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/convention_generator_service.dart';

void main() {
  group('ConventionGeneratorService - Date & Format Helpers', () {
    test('formatDateDDMMYY formats ISO date YYYY-MM-DD to DDMMYY', () {
      expect(
        ConventionGeneratorService.formatDateDDMMYY('2026-06-08'),
        '080626',
      );
    });

    test('formatDateDDMMYY formats slash date DD/MM/YYYY to DDMMYY', () {
      expect(
        ConventionGeneratorService.formatDateDDMMYY('08/06/2026'),
        '080626',
      );
    });

    test('formatDateDDMMYY preserves 6 digits', () {
      expect(ConventionGeneratorService.formatDateDDMMYY('080626'), '080626');
    });

    test('formatReelWithCamera handles numeric and camera prefixed reels', () {
      expect(
        ConventionGeneratorService.formatReelWithCamera('001', 'A'),
        'A001',
      );
      expect(ConventionGeneratorService.formatReelWithCamera('1', 'A'), 'A001');
      expect(
        ConventionGeneratorService.formatReelWithCamera('A001', 'A'),
        'A001',
      );
      expect(
        ConventionGeneratorService.formatReelWithCamera('B001', 'A'),
        'A001',
      );
    });

    test('formatTake formats numeric take with T and preserves TF', () {
      expect(ConventionGeneratorService.formatTake('1'), 'T1');
      expect(ConventionGeneratorService.formatTake('T1'), 'T1');
      expect(ConventionGeneratorService.formatTake('TF1'), 'TF1');
      expect(ConventionGeneratorService.formatTake(''), 'T1');
    });
  });

  group('ConventionGeneratorService - generateConventionName', () {
    late RenombrataProject baseProject;

    setUp(() {
      final metadata = ShootingLogMetadata(
        nomenclature: 'MNBOENC',
        date: '2026-06-08',
        unit: '3',
        day: '1',
        producer: '',
        production: '',
        location: '',
        audioFormat: '',
        frameRate: '23.98',
        videoCodec: '',
        responsibleEngineer: '',
        ingestor: '',
      );

      baseProject = RenombrataProject(
        log: ShootingLog(metadata: metadata, records: []),
        defaultReel: '001',
        activeCamera: 'A',
        showChapter: true,
        showPlane: false,
        conventionNameOrder: const ['capitulo', 'escena', 'plano', 'toma'],
      );
    });

    test(
      'generates standard convention name without plane when showPlane is false',
      () {
        final result = ConventionGeneratorService.generateConventionName(
          project: baseProject,
          chapter: '17',
          scene: '11',
          plane: null,
          take: '1',
          reel: '001',
          camera: 'A',
          clipIndex: 1,
        );

        expect(result, 'MNBOENC_080626_17_11_T1_A001_1_D1_U3');
      },
    );

    test(
      'includes plane token when showPlane is true and plane is present',
      () {
        final projectWithPlane = baseProject.copyWith(showPlane: true);

        final result = ConventionGeneratorService.generateConventionName(
          project: projectWithPlane,
          chapter: '17',
          scene: '11',
          plane: 'A',
          take: '1',
          reel: '001',
          camera: 'A',
          clipIndex: 1,
        );

        expect(result, 'MNBOENC_080626_17_11_A_T1_A001_1_D1_U3');
      },
    );

    test(
      'omits plane token when showPlane is false even if plane is provided',
      () {
        final projectNoPlane = baseProject.copyWith(showPlane: false);

        final result = ConventionGeneratorService.generateConventionName(
          project: projectNoPlane,
          chapter: '17',
          scene: '11',
          plane: 'A',
          take: '1',
          reel: '001',
          camera: 'A',
          clipIndex: 1,
        );

        expect(result, 'MNBOENC_080626_17_11_T1_A001_1_D1_U3');
      },
    );

    test('respects custom conventionNameOrder: escena, capitulo, toma', () {
      final reorderedProject = baseProject.copyWith(
        conventionNameOrder: const ['escena', 'capitulo', 'toma'],
        showPlane: false,
      );

      final result = ConventionGeneratorService.generateConventionName(
        project: reorderedProject,
        chapter: '17',
        scene: '11',
        take: '1',
        reel: '001',
        camera: 'A',
        clipIndex: 1,
      );

      expect(result, 'MNBOENC_080626_11_17_T1_A001_1_D1_U3');
    });

    test('omits chapter if showChapter is false', () {
      final noChapterProject = baseProject.copyWith(
        showChapter: false,
        conventionNameOrder: const ['capitulo', 'escena', 'toma'],
      );

      final result = ConventionGeneratorService.generateConventionName(
        project: noChapterProject,
        chapter: '17',
        scene: '11',
        take: '1',
        reel: '001',
        camera: 'A',
        clipIndex: 1,
      );

      expect(result, 'MNBOENC_080626_11_T1_A001_1_D1_U3');
    });
  });

  group('ConventionGeneratorService - parseConventionLine', () {
    late RenombrataProject project;

    setUp(() {
      final metadata = ShootingLogMetadata(
        nomenclature: 'MNBOENC',
        date: '2026-06-08',
        unit: '3',
        day: '1',
        producer: '',
        production: '',
        location: '',
        audioFormat: '',
        frameRate: '23.98',
        videoCodec: '',
        responsibleEngineer: '',
        ingestor: '',
      );

      project = RenombrataProject(
        log: ShootingLog(metadata: metadata, records: []),
        defaultReel: '001',
        activeCamera: 'A',
        showChapter: true,
        showPlane: true,
        conventionNameOrder: const ['capitulo', 'escena', 'plano', 'toma'],
      );
    });

    test('parses standard convention line into metadata tokens', () {
      const line = 'MNBOENC_080626_17_11_T1_A001_1_D1_U3';
      final parsed = ConventionGeneratorService.parseConventionLine(
        line: line,
        project: project.copyWith(showPlane: false),
      );

      expect(parsed, isNotNull);
      expect(parsed!['chapter'], '17');
      expect(parsed['scene'], '11');
      expect(parsed['take'], '1');
      expect(parsed['reel'], '001');
      expect(parsed['clipIndex'], '1');
    });

    test('parses convention line with plane token', () {
      const line = 'MNBOENC_080626_17_11_A_T1_A001_1_D1_U3';
      final parsed = ConventionGeneratorService.parseConventionLine(
        line: line,
        project: project,
      );

      expect(parsed, isNotNull);
      expect(parsed!['chapter'], '17');
      expect(parsed['scene'], '11');
      expect(parsed['plane'], 'A');
      expect(parsed['take'], '1');
      expect(parsed['reel'], '001');
      expect(parsed['clipIndex'], '1');
    });

    test('parses reordered convention line', () {
      const line = 'MNBOENC_080626_11_17_T1_A001_1_D1_U3';
      final reorderedProject = project.copyWith(
        conventionNameOrder: const ['escena', 'capitulo', 'toma'],
        showPlane: false,
      );

      final parsed = ConventionGeneratorService.parseConventionLine(
        line: line,
        project: reorderedProject,
      );

      expect(parsed, isNotNull);
      expect(parsed!['scene'], '11');
      expect(parsed['chapter'], '17');
      expect(parsed['take'], '1');
      expect(parsed['reel'], '001');
      expect(parsed['clipIndex'], '1');
    });

    test('returns null for arbitrary invalid string like TEST', () {
      final parsed = ConventionGeneratorService.parseConventionLine(
        line: 'TEST',
        project: project,
      );

      expect(parsed, isNull);
    });

    test('returns null for arbitrary short string', () {
      final parsed = ConventionGeneratorService.parseConventionLine(
        line: 'RANDOM_STRING',
        project: project,
      );

      expect(parsed, isNull);
    });
  });
}
