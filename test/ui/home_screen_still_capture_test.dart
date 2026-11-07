import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/still_capture_service.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:renombrata/src/ui/media_preview_dialog.dart';

class _FakeStillStream extends Fake implements PlayerStream {
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _volume = StreamController<double>.broadcast();
  final _log = StreamController<PlayerLog>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _tracks = StreamController<Tracks>.broadcast();

  @override
  Stream<bool> get playing => _playing.stream;
  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<Duration> get duration => _duration.stream;
  @override
  Stream<double> get volume => _volume.stream;
  @override
  Stream<PlayerLog> get log => _log.stream;
  @override
  Stream<String> get error => _error.stream;
  @override
  Stream<Tracks> get tracks => _tracks.stream;

  void close() {
    _playing.close();
    _position.close();
    _duration.close();
    _volume.close();
    _log.close();
    _error.close();
    _tracks.close();
  }
}

class _FakeCapturePlayer extends Fake implements Player {
  final _FakeStillStream _stream = _FakeStillStream();
  Uint8List? screenshotBytes;
  String? capturedFormat;
  bool shouldFail = false;

  _FakeCapturePlayer({this.screenshotBytes, this.shouldFail = false});

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> open(Playable playable, {bool? play}) async {}

  @override
  Future<void> dispose({int? code}) async {
    _stream.close();
  }

  @override
  Future<Uint8List?> screenshot({
    String? format = 'image/jpeg',
    bool includeLibassSubtitles = false,
  }) async {
    capturedFormat = format;
    if (shouldFail) return null;
    return screenshotBytes;
  }
}

void main() {
  void setupWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final metadata = ShootingLogMetadata(
    nomenclature: 'NOVELA_STILL',
    date: '2026-11-06',
    unit: 'U1',
    day: 'D1',
    producer: '',
    production: '',
    location: '',
    audioFormat: '',
    frameRate: '24',
    videoCodec: '',
    responsibleEngineer: '',
    ingestor: '',
  );

  final project = RenombrataProject(
    log: ShootingLog(metadata: metadata, records: []),
    defaultReel: 'A001',
    activeCamera: 'A',
  );

  RenameProposal createProposal(String name) => RenameProposal(
    originalFilePath: '/clips/$name',
    proposedFileName: 'CONV_$name',
    fileReel: 'A001',
    fileTcIn: '01:00:00:00',
    fileTcOut: '01:00:10:00',
    status: ProposalStatus.ready,
  );

  group('HomeScreen Studio Still Capture Tests', () {
    late Directory expectedStillsDir;

    setUp(() {
      expectedStillsDir = StillCaptureService.getProjectStillsDirectory(
        projectName: metadata.nomenclature,
        date: metadata.date,
      );
    });

    tearDown(() {
      if (expectedStillsDir.existsSync()) {
        try {
          expectedStillsDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    testWidgets(
      'renders studio_capture_still_button and saves snapshot with notification',
      (tester) async {
        setupWindow(tester, const Size(1920, 1080));
        final fakeBytes = Uint8List.fromList([0x12, 0x34, 0x56, 0x78]);
        final player = _FakeCapturePlayer(screenshotBytes: fakeBytes);

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              initialProject: project,
              initialReport: DryRunReport(
                proposals: [createProposal('A001C001.MP4')],
              ),
              customStudioPlayer: player,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Renombrador tab
        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        // Ensure in Studio mode
        final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
        if (studioBtn.evaluate().isNotEmpty) {
          await tester.tap(studioBtn);
          await tester.pumpAndSettle();
        }

        // Verify button exists with proper tooltip and icon
        final captureButtonFinder = find.byKey(
          const ValueKey('studio_capture_still_button'),
        );
        expect(captureButtonFinder, findsOneWidget);
        final captureWidget = tester.widget<IconButton>(captureButtonFinder);
        expect(
          captureWidget.tooltip,
          'Capturar fotograma (Guardar en Escritorio)',
        );

        // Tap capture button
        await tester.tap(captureButtonFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify notification banner is displayed
        expect(find.textContaining('Fotograma guardado:'), findsOneWidget);
        expect(
          find.textContaining(p.basename(expectedStillsDir.path)),
          findsOneWidget,
        );

        // Verify file was written to disk
        expect(expectedStillsDir.existsSync(), isTrue);
        final savedFiles = expectedStillsDir.listSync();
        expect(savedFiles.isNotEmpty, isTrue);
      },
    );

    testWidgets(
      'displays error notification when still capture fails',
      (tester) async {
        setupWindow(tester, const Size(1920, 1080));
        final failingPlayer = _FakeCapturePlayer(shouldFail: true);

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(
              initialProject: project,
              initialReport: DryRunReport(
                proposals: [createProposal('A001C002.MP4')],
              ),
              customStudioPlayer: failingPlayer,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Renombrador tab
        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        final captureButtonFinder = find.byKey(
          const ValueKey('studio_capture_still_button'),
        );
        expect(captureButtonFinder, findsOneWidget);

        await tester.tap(captureButtonFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.text('No se pudo capturar el fotograma del video'),
          findsOneWidget,
        );
      },
    );
  });

  group('MediaPreviewDialog Still Capture Tests', () {
    testWidgets(
      'renders preview_capture_still_button and triggers capture feedback',
      (tester) async {
        setupWindow(tester, const Size(1920, 1080));
        final fakeBytes = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
        final player = _FakeCapturePlayer(screenshotBytes: fakeBytes);

        String? receivedNotification;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaPreviewDialog(
                playlist: [createProposal('A001C003.MP4')],
                initialIndex: 0,
                projectMetadata: metadata,
                activeCamera: 'A',
                customPlayer: player,
                onSaveTake:
                    (proposal, cap, sc, pl, tk, mos, notes) async {},
                onNotification: (msg, {isError = false}) {
                  receivedNotification = msg;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final captureButtonFinder = find.byKey(
          const ValueKey('preview_capture_still_button'),
        );
        expect(captureButtonFinder, findsOneWidget);

        await tester.tap(captureButtonFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Check dialog feedback banner & callback
        expect(find.textContaining('Fotograma guardado:'), findsOneWidget);
        expect(receivedNotification, contains('Fotograma guardado:'));
      },
    );

    testWidgets(
      'displays error feedback when player screenshot fails in MediaPreviewDialog',
      (tester) async {
        setupWindow(tester, const Size(1920, 1080));
        final failingPlayer = _FakeCapturePlayer(shouldFail: true);

        String? receivedError;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaPreviewDialog(
                playlist: [createProposal('A001C004.MP4')],
                initialIndex: 0,
                projectMetadata: metadata,
                activeCamera: 'A',
                customPlayer: failingPlayer,
                onSaveTake:
                    (proposal, cap, sc, pl, tk, mos, notes) async {},
                onNotification: (msg, {isError = false}) {
                  if (isError) receivedError = msg;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final captureButtonFinder = find.byKey(
          const ValueKey('preview_capture_still_button'),
        );
        expect(captureButtonFinder, findsOneWidget);

        await tester.tap(captureButtonFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.text('No se pudo capturar el fotograma del video'),
          findsOneWidget,
        );
        expect(
          receivedError,
          equals('No se pudo capturar el fotograma del video'),
        );
      },
    );
  });
}
