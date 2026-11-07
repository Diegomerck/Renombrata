import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:renombrata/src/utils/frame_step_utils.dart';

class _FakeStream extends Fake implements PlayerStream {
  final _playing = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _volume = StreamController<double>.broadcast();
  final _log = StreamController<PlayerLog>.broadcast();
  final _error = StreamController<String>.broadcast();

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

  void emitDuration(Duration d) => _duration.add(d);

  void close() {
    _playing.close();
    _position.close();
    _duration.close();
    _volume.close();
    _log.close();
    _error.close();
  }
}

/// Fake player without a native platform: stepping must use the seek fallback.
class _SeekFakePlayer extends Fake implements Player {
  final _FakeStream _stream = _FakeStream();
  final List<String> calls = [];
  final List<Duration> seeks = [];

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seek(Duration duration) async {
    calls.add('seek');
    seeks.add(duration);
  }

  @override
  Future<void> dispose({int? code}) async => _stream.close();

  @override
  Future<void> open(Playable playable, {bool? play}) async {}
}

class _FakeNative extends Fake implements PlatformPlayer {
  final List<List<String>> commands;
  _FakeNative(this.commands);

  // Invoked dynamically by FrameStepUtils.
  Future<void> command(List<String> args) async => commands.add(args);
}

class _NativeFakePlayer extends _SeekFakePlayer {
  final List<List<String>> commands = [];
  late final _FakeNative _native = _FakeNative(commands);

  @override
  PlatformPlayer? get platform => _native;
}

void main() {
  void setupWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
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
    frameRate: '25',
    videoCodec: '',
    responsibleEngineer: '',
    ingestor: '',
  );
  final project = RenombrataProject(
    log: ShootingLog(metadata: metadata, records: []),
    defaultReel: 'A001',
    activeCamera: 'A',
  );

  RenameProposal proposal(String path) => RenameProposal(
    originalFilePath: path,
    proposedFileName: path.split('/').last,
    fileReel: 'A001',
    fileTcIn: '01:00:00:00',
    fileTcOut: '01:02:15:12',
    status: ProposalStatus.ready,
  );

  Future<void> openStudio(
    WidgetTester tester,
    Player player,
    String path,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          initialProject: project,
          initialReport: DryRunReport(proposals: [proposal(path)]),
          customStudioPlayer: player,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renombrador de Medios'));
    await tester.pumpAndSettle();
    final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
    if (studioBtn.evaluate().isNotEmpty) {
      await tester.tap(studioBtn);
    }
    await tester.pumpAndSettle();
  }

  group('FrameStepUtils', () {
    test('fpsFromFrameRate maps known rates and defaults to 23.976', () {
      expect(FrameStepUtils.fpsFromFrameRate('23.98'), closeTo(23.976, 0.001));
      expect(FrameStepUtils.fpsFromFrameRate('24'), 24);
      expect(FrameStepUtils.fpsFromFrameRate('25'), 25);
      expect(FrameStepUtils.fpsFromFrameRate('29.97'), closeTo(29.97, 0.001));
      expect(FrameStepUtils.fpsFromFrameRate(''), FrameStepUtils.defaultFps);
      expect(FrameStepUtils.fpsFromFrameRate(null), FrameStepUtils.defaultFps);
      expect(FrameStepUtils.fpsFromFrameRate('abc'), FrameStepUtils.defaultFps);
    });

    test('targetPosition steps one frame and clamps to [0, duration]', () {
      const duration = Duration(seconds: 10);
      expect(
        FrameStepUtils.targetPosition(
          position: const Duration(seconds: 1),
          duration: duration,
          forward: true,
          fps: 25,
        ),
        const Duration(seconds: 1, milliseconds: 40),
      );
      expect(
        FrameStepUtils.targetPosition(
          position: Duration.zero,
          duration: duration,
          forward: false,
          fps: 25,
        ),
        Duration.zero,
      );
      expect(
        FrameStepUtils.targetPosition(
          position: duration,
          duration: duration,
          forward: true,
          fps: 25,
        ),
        duration,
      );
    });

    test('step uses native mpv commands when available', () async {
      final player = _NativeFakePlayer();
      final fwd = await FrameStepUtils.step(
        player,
        forward: true,
        position: Duration.zero,
        duration: const Duration(seconds: 5),
        fps: 25,
      );
      final back = await FrameStepUtils.step(
        player,
        forward: false,
        position: const Duration(seconds: 1),
        duration: const Duration(seconds: 5),
        fps: 25,
      );
      expect(fwd, isNull);
      expect(back, isNull);
      expect(player.commands, [
        ['frame-step'],
        ['frame-back-step'],
      ]);
      expect(player.calls, ['pause', 'pause']);
      expect(player.seeks, isEmpty);
    });

    test('step falls back to pause + seek without a native platform', () async {
      final player = _SeekFakePlayer();
      final target = await FrameStepUtils.step(
        player,
        forward: true,
        position: const Duration(seconds: 2),
        duration: const Duration(seconds: 5),
        fps: 25,
      );
      expect(target, const Duration(seconds: 2, milliseconds: 40));
      expect(player.calls, ['pause', 'seek']);
      expect(player.seeks.single, target);
    });
  });

  group('HomeScreen Studio frame stepping', () {
    testWidgets('frame buttons pause then seek by one frame (fallback)', (
      tester,
    ) async {
      setupWindow(tester, const Size(1920, 1080));
      final player = _SeekFakePlayer();
      await openStudio(tester, player, '/media/A001C001_260817AB.MP4');

      final back = find.byKey(const ValueKey('studio_frame_back_button'));
      final fwd = find.byKey(const ValueKey('studio_frame_forward_button'));
      expect(back, findsOneWidget);
      expect(fwd, findsOneWidget);
      expect(
        tester.widget<IconButton>(fwd).tooltip,
        'Fotograma siguiente (.)',
      );
      expect(
        tester.widget<IconButton>(back).tooltip,
        'Fotograma anterior (,)',
      );

      final dynamic state = tester.state(find.byType(HomeScreen));
      player._stream.emitDuration(const Duration(seconds: 10));
      await tester.pump();
      state.studioPositionNotifier.value = const Duration(seconds: 1);

      await tester.tap(fwd);
      await tester.pump();
      expect(player.calls, ['pause', 'seek']);
      // Project frame rate is 25 fps -> 40 ms per frame.
      expect(player.seeks.last, const Duration(seconds: 1, milliseconds: 40));

      await tester.tap(back);
      await tester.pump();
      expect(player.seeks.last, const Duration(seconds: 1));
      expect(player.calls.where((c) => c == 'pause').length, 2);
    });

    testWidgets('comma / period shortcuts step frames', (tester) async {
      setupWindow(tester, const Size(1920, 1080));
      final player = _SeekFakePlayer();
      await openStudio(tester, player, '/media/A001C001_260817AB.MP4');

      final dynamic state = tester.state(find.byType(HomeScreen));
      (state.studioWorkspaceFocusNode as FocusNode).requestFocus();
      await tester.pump();
      player._stream.emitDuration(const Duration(seconds: 10));
      await tester.pump();
      state.studioPositionNotifier.value = const Duration(seconds: 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.pump();
      expect(player.seeks, [const Duration(seconds: 2, milliseconds: 40)]);

      await tester.sendKeyEvent(LogicalKeyboardKey.comma);
      await tester.pump();
      expect(player.seeks.length, 2);
    });

    testWidgets('frame buttons are disabled for raw (CRM) clips', (
      tester,
    ) async {
      setupWindow(tester, const Size(1920, 1080));
      final player = _SeekFakePlayer();
      await openStudio(tester, player, '/media/A001C001.CRM');

      final back = find.byKey(const ValueKey('studio_frame_back_button'));
      final fwd = find.byKey(const ValueKey('studio_frame_forward_button'));
      expect(back, findsOneWidget);
      expect(tester.widget<IconButton>(back).onPressed, isNull);
      expect(tester.widget<IconButton>(fwd).onPressed, isNull);
    });

    testWidgets('transport bar fits at the 1100px minimum width', (
      tester,
    ) async {
      setupWindow(tester, const Size(1100, 1600));
      final player = _SeekFakePlayer();
      await openStudio(tester, player, '/media/A001C001_260817AB.MP4');

      expect(
        find.byKey(const ValueKey('studio_frame_back_button')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
