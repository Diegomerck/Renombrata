import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:renombrata/src/models/app_settings.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:renombrata/src/ui/settings_dialog.dart';

class FakePlayerStream extends Fake implements PlayerStream {
  final StreamController<bool> _playingController = StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController = StreamController<Duration>.broadcast();
  final StreamController<double> _volumeController = StreamController<double>.broadcast();
  final StreamController<PlayerLog> _logController = StreamController<PlayerLog>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();

  @override
  Stream<bool> get playing => _playingController.stream;

  @override
  Stream<Duration> get position => _positionController.stream;

  @override
  Stream<Duration> get duration => _durationController.stream;

  @override
  Stream<double> get volume => _volumeController.stream;

  @override
  Stream<PlayerLog> get log => _logController.stream;

  @override
  Stream<String> get error => _errorController.stream;

  void close() {
    _playingController.close();
    _positionController.close();
    _durationController.close();
    _volumeController.close();
    _logController.close();
    _errorController.close();
  }
}

class FakePlayer extends Fake implements Player {
  bool pauseCalled = false;
  int pauseCallCount = 0;
  bool disposeCalled = false;
  final FakePlayerStream _stream = FakePlayerStream();

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> pause() async {
    pauseCalled = true;
    pauseCallCount++;
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

  final report = DryRunReport(proposals: [prop1]);

  group('Video Player Settings & Tab-Switching Tests', () {
    testWidgets('SettingsDialog renders "Reproductor de Video" tab and controls', (tester) async {
      setupDesktopWindow(tester);

      AppSettings current = AppSettings.defaults();
      AppSettings? updated;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsDialog(
              currentSettings: current,
              onSettingsChanged: (s) => updated = s,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check tab label
      final tabFinder = find.text('Reproductor de Video');
      expect(tabFinder, findsOneWidget);

      // Navigate to the Video Player tab
      await tester.tap(tabFinder);
      await tester.pumpAndSettle();

      // Verify section header and switch tile
      expect(find.text('Comportamiento de Reproducción'), findsOneWidget);
      expect(find.text('Pausar automáticamente al cambiar de pestaña'), findsOneWidget);
      expect(
        find.text(
          'Pausa la reproducción al cambiar a la Bitácora Digital y conserva la posición exacta al regresar. Si se desactiva, continúa reproduciéndose en segundo plano.',
        ),
        findsOneWidget,
      );

      final switchFinder = find.byKey(const ValueKey('settings_pause_video_on_tab_switch_tile'));
      expect(switchFinder, findsOneWidget);

      final switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isTrue);

      // Toggle switch to false
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(updated, isNotNull);
      expect(updated!.pauseVideoOnTabSwitch, isFalse);
    });

    testWidgets('Switching to Bitácora tab pauses player when pauseVideoOnTabSwitch is true, without disposing player or resetting position', (tester) async {
      setupDesktopWindow(tester);

      final fakePlayer = FakePlayer();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            customStudioPlayer: fakePlayer,
            initialStudioMode: true,
            initialSettings: const AppSettings(pauseVideoOnTabSwitch: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic homeState = tester.state(find.byType(HomeScreen));

      // Switch to Renombrador de Medios tab (index 1)
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Set playback position to 35 seconds
      homeState.studioPositionNotifier.value = const Duration(seconds: 35);
      await tester.pumpAndSettle();

      // Reset pause call flags
      fakePlayer.pauseCalled = false;
      fakePlayer.pauseCallCount = 0;

      // Switch to Bitácora Digital tab (index 0)
      await tester.tap(find.text('Bitácora Digital'));
      await tester.pumpAndSettle();

      // Verify pause() was called, but player was NOT disposed
      expect(fakePlayer.pauseCalled, isTrue);
      expect(fakePlayer.disposeCalled, isFalse);
      expect(homeState.studioPlayer, isNotNull);

      // Switch back to Renombrador de Medios (index 1)
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Verify the player is still intact and position preserved
      expect(homeState.studioPlayer, equals(fakePlayer));
      expect(fakePlayer.disposeCalled, isFalse);
      expect(homeState.studioPositionNotifier.value, equals(const Duration(seconds: 35)));
    });

    testWidgets('Switching to Bitácora tab does NOT pause player when pauseVideoOnTabSwitch is false', (tester) async {
      setupDesktopWindow(tester);

      final fakePlayer = FakePlayer();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            customStudioPlayer: fakePlayer,
            initialStudioMode: true,
            initialSettings: const AppSettings(pauseVideoOnTabSwitch: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic homeState = tester.state(find.byType(HomeScreen));

      // Switch to Renombrador de Medios tab (index 1)
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Reset pause call flags
      fakePlayer.pauseCalled = false;
      fakePlayer.pauseCallCount = 0;

      // Switch to Bitácora Digital tab (index 0)
      await tester.tap(find.text('Bitácora Digital'));
      await tester.pumpAndSettle();

      // Verify pause() was NOT called and player was NOT disposed
      expect(fakePlayer.pauseCalled, isFalse);
      expect(fakePlayer.disposeCalled, isFalse);
      expect(homeState.studioPlayer, isNotNull);
    });
  });
}
