import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';

class FakePlayerStream extends Fake implements PlayerStream {
  final StreamController<bool> _playingController = StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController = StreamController<Duration>.broadcast();
  final StreamController<double> _volumeController = StreamController<double>.broadcast();

  @override
  Stream<bool> get playing => _playingController.stream;

  @override
  Stream<Duration> get position => _positionController.stream;

  @override
  Stream<Duration> get duration => _durationController.stream;

  @override
  Stream<double> get volume => _volumeController.stream;

  void close() {
    _playingController.close();
    _positionController.close();
    _durationController.close();
    _volumeController.close();
  }
}

class FakePlayer extends Fake implements Player {
  bool pauseCalled = false;
  bool disposeCalled = false;
  final FakePlayerStream _stream = FakePlayerStream();

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> pause() async {
    pauseCalled = true;
  }

  @override
  Future<void> dispose({int? code}) async {
    disposeCalled = true;
    _stream.close();
  }

  @override
  Future<void> open(Playable playable, {bool? play}) async {}
}

void main() {
  void setupDesktopWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  final metadata = ShootingLogMetadata(
    nomenclature: 'PROJ',
    date: '261028',
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

  final prop1 = RenameProposal(
    originalFilePath: '/media/A001C001_260817AB.MP4',
    proposedFileName: 'A001C001_260817AB.MP4',
    fileReel: 'A001',
    fileTcIn: '01:00:00:00',
    fileTcOut: '01:02:15:12',
    status: ProposalStatus.ready,
  );

  final prop2 = RenameProposal(
    originalFilePath: '/media/A001C002_260817AB.MP4',
    proposedFileName: 'A001C002_260817AB.MP4',
    fileReel: 'A001',
    fileTcIn: '01:05:00:00',
    fileTcOut: '01:07:30:00',
    status: ProposalStatus.ready,
  );

  final report = DryRunReport(proposals: [prop1, prop2]);

  group('HomeScreen - Studio Player Lifecycle & Teardown Tests', () {
    testWidgets('Test 1: reassemble() safely pauses active studio playback without throwing', (tester) async {
      setupDesktopWindow(tester);

      final fakePlayer = FakePlayer();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            customStudioPlayer: fakePlayer,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic homeState = tester.state(find.byType(HomeScreen));
      expect(fakePlayer.pauseCalled, isFalse);

      // Trigger reassemble() as during hot restart
      homeState.reassemble();
      await tester.pumpAndSettle();

      // Verify that active native Direct3D rendering/playback is safely halted
      expect(fakePlayer.pauseCalled, isTrue);
    });

    testWidgets('Test 2: dispose() cancels all stream subscriptions and disposes the player cleanly', (tester) async {
      setupDesktopWindow(tester);

      final fakePlayer = FakePlayer();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            customStudioPlayer: fakePlayer,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic homeState = tester.state(find.byType(HomeScreen));
      final List<StreamSubscription> subscriptions = homeState.studioSubscriptions;

      // 4 stream subscriptions (playing, position, duration, volume) are active
      expect(subscriptions.length, equals(4));

      // Destroy HomeScreen to trigger dispose()
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      // Verify player was paused and disposed
      expect(fakePlayer.pauseCalled, isTrue);
      expect(fakePlayer.disposeCalled, isTrue);

      // Verify subscriptions list was cleared
      expect(subscriptions.isEmpty, isTrue);
    });

    testWidgets('Test 3: switching clips safely resets zoom and position notifier cleanly', (tester) async {
      setupDesktopWindow(tester);

      final fakePlayer = FakePlayer();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            customStudioPlayer: fakePlayer,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Studio Mode
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final dynamic homeState = tester.state(find.byType(HomeScreen));

      // Zoom in on clip 1
      await tester.tap(find.byKey(const ValueKey('studio_zoom_in_button')));
      await tester.pumpAndSettle();
      expect(find.text('130%'), findsOneWidget);
      expect(homeState.studioCurrentZoom, closeTo(1.3, 0.01));

      // Set position on clip 1
      homeState.studioPositionNotifier.value = const Duration(seconds: 45);
      await tester.pumpAndSettle();
      expect(homeState.studioPositionNotifier.value, equals(const Duration(seconds: 45)));

      // Switch to clip 2
      homeState.selectStudioClip(prop2);
      await tester.pumpAndSettle();

      // Zoom must be reset to 100% and position notifier reset to zero
      expect(homeState.selectedStudioClip, equals(prop2));
      expect(homeState.studioCurrentZoom, equals(1.0));
      expect(find.text('100%'), findsOneWidget);
      expect(homeState.studioPositionNotifier.value, equals(Duration.zero));
    });
  });
}
