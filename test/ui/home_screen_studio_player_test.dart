import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:renombrata/src/utils/media_proxy_utils.dart';

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

  void emitError(String err) {
    _errorController.add(err);
  }

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

  Widget createHomeScreen({
    required RenombrataProject project,
    required DryRunReport report,
  }) {
    return MaterialApp(
      home: HomeScreen(
        initialProject: project,
        initialReport: report,
      ),
    );
  }

  group('HomeScreen - Studio Video Player, Magnifier HUD, Transport Bar & SMPTE', () {
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

    testWidgets('Test 1: Video container renders and configures NoVideoControls without native UI collision', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      // Navigate to Renombrador de Medios -> Modo Estudio
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
      }
      await tester.pumpAndSettle();

      // Studio video container is rendered
      final playerContainer = find.byKey(const ValueKey('studio_video_player_container'));
      expect(playerContainer, findsOneWidget);

      // Interactive viewer is wired to the player stack
      expect(find.byType(InteractiveViewer), findsOneWidget);

      // If Video widget is present in tree, verify it uses NoVideoControls
      final videoFinder = find.byType(Video);
      if (videoFinder.evaluate().isNotEmpty) {
        final videoWidget = tester.widget<Video>(videoFinder);
        expect(videoWidget.controls, equals(NoVideoControls));
      }

      // Default media_kit controls theme is NOT present
      expect(find.byType(MaterialVideoControlsTheme), findsNothing);
    });

    testWidgets('Test 2: Magnifier HUD displays 100% zoom and zooming in updates percentage and shows reset button', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
      }
      await tester.pumpAndSettle();

      // HUD overlay is visible at top right
      expect(find.byKey(const ValueKey('studio_magnifier_hud')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_zoom_text')), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      // Reset button is hidden when at 100% zoom
      expect(find.byKey(const ValueKey('studio_zoom_reset_button')), findsNothing);

      // Zoom in
      await tester.tap(find.byKey(const ValueKey('studio_zoom_in_button')));
      await tester.pumpAndSettle();

      // HUD text updates to 130%
      expect(find.text('130%'), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_zoom_reset_button')), findsOneWidget);

      // Tap reset button
      await tester.tap(find.byKey(const ValueKey('studio_zoom_reset_button')));
      await tester.pumpAndSettle();

      // Reset to 100%
      expect(find.text('100%'), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_zoom_reset_button')), findsNothing);

      // Test double tap reset
      await tester.tap(find.byKey(const ValueKey('studio_zoom_in_button')));
      await tester.pumpAndSettle();
      expect(find.text('130%'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('studio_video_gesture_detector')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('studio_video_gesture_detector')));
      await tester.pumpAndSettle();

      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('Test 3: Transport Bar is positioned below the video surface and scrubber & controls function', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
      }
      await tester.pumpAndSettle();

      final videoContainer = find.byKey(const ValueKey('studio_video_player_container'));
      final transportBar = find.byKey(const ValueKey('studio_transport_bar'));

      expect(videoContainer, findsOneWidget);
      expect(transportBar, findsOneWidget);

      // Verify Transport Bar is positioned below the video container
      final videoBottom = tester.getBottomLeft(videoContainer).dy;
      final transportTop = tester.getTopLeft(transportBar).dy;
      expect(transportTop, greaterThanOrEqualTo(videoBottom));

      // Verify controls inside transport bar
      expect(find.byKey(const ValueKey('studio_scrubber_slider')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_play_pause_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_replay_5_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_forward_5_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_duration_text')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_live_smpte_badge')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_volume_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_volume_slider')), findsOneWidget);

      // Verify duration text initial format
      expect(find.text('00:00 / 00:00'), findsOneWidget);

      // Update position and duration through ValueNotifiers
      final dynamic homeState = tester.state(find.byType(HomeScreen));
      homeState.studioDurationNotifier.value = const Duration(minutes: 1, seconds: 30);
      homeState.studioPositionNotifier.value = const Duration(seconds: 45);
      await tester.pumpAndSettle();

      expect(find.text('00:45 / 01:30'), findsOneWidget);

      // Scrubber slider moves without rebuilding full HomeScreen
      final slider = tester.widget<Slider>(find.byKey(const ValueKey('studio_scrubber_slider')));
      expect(slider.value, closeTo(0.5, 0.01));
    });

    testWidgets('Test 4: computeLiveSmpte accurately adds elapsed position frames to base TC In and updates badge', (tester) async {
      setupDesktopWindow(tester);

      // Test computeLiveSmpte static algorithm
      // 24 fps
      expect(
        HomeScreen.computeLiveSmpte(Duration.zero, '01:00:00:00', '24'),
        equals('01:00:00:00'),
      );
      expect(
        HomeScreen.computeLiveSmpte(const Duration(seconds: 1), '01:00:00:00', '24'),
        equals('01:00:01:00'),
      );
      expect(
        HomeScreen.computeLiveSmpte(const Duration(milliseconds: 500), '01:00:00:00', '24'),
        equals('01:00:00:12'),
      );
      expect(
        HomeScreen.computeLiveSmpte(const Duration(milliseconds: 500), '01:00:00:15', '24'),
        equals('01:00:01:03'),
      );
      expect(
        HomeScreen.computeLiveSmpte(const Duration(seconds: 2), '23:59:59:00', '24'),
        equals('00:00:01:00'),
      );

      // 25 fps
      expect(
        HomeScreen.computeLiveSmpte(const Duration(seconds: 1), '10:00:00:00', '25'),
        equals('10:00:01:00'),
      );
      expect(
        HomeScreen.computeLiveSmpte(const Duration(milliseconds: 40), '10:00:00:00', '25'),
        equals('10:00:00:01'),
      );

      // Null or empty base TC In fallback
      expect(
        HomeScreen.computeLiveSmpte(const Duration(seconds: 5), null, '24'),
        equals('00:00:05:00'),
      );

      // Test live badge in UI
      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
      }
      await tester.pumpAndSettle();

      // Initial live SMPTE badge
      expect(find.text('SMPTE: 01:00:00:00'), findsOneWidget);

      // Static TC badge in slate card header
      final staticBadge = find.byKey(const ValueKey('studio_static_tc_badge'));
      expect(staticBadge, findsOneWidget);
      expect(find.text('TC: 01:00:00:00 → 01:02:15:12'), findsOneWidget);

      // Advance video position
      final dynamic homeState = tester.state(find.byType(HomeScreen));
      homeState.studioPositionNotifier.value = const Duration(seconds: 10, milliseconds: 500);
      await tester.pumpAndSettle();

      // 10s 500ms at 24fps = 10s 12 frames
      expect(find.text('SMPTE: 01:00:10:12'), findsOneWidget);
    });
    testWidgets('Test 5: Studio Mode with .MXF video renders InteractiveViewer, magnifier HUD, and transport bar', (tester) async {
      setupDesktopWindow(tester);

      final mxfProp = RenameProposal(
        originalFilePath: '/media/A001C001.MXF',
        proposedFileName: 'PROJ_261028_10_1_T1_A001_D1_U1.MXF',
        fileReel: 'A001',
        fileTcIn: '01:00:00:00',
        fileTcOut: '01:05:00:00',
        status: ProposalStatus.ready,
      );
      final mxfReport = DryRunReport(proposals: [mxfProp]);

      await tester.pumpWidget(createHomeScreen(project: project, report: mxfReport));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
      }
      await tester.pumpAndSettle();

      // Video player container rendered
      expect(find.byKey(const ValueKey('studio_video_player_container')), findsOneWidget);

      // Interactive viewer and magnifier HUD active for MXF video
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_magnifier_hud')), findsOneWidget);

      // Dedicated transport bar rendered below
      expect(find.byKey(const ValueKey('studio_transport_bar')), findsOneWidget);
    });

    testWidgets('Test 6: Studio Mode with .CRM Canon RAW Light renders dedicated Slate HUD with badges, waveform, and status message', (tester) async {
      setupDesktopWindow(tester);

      final crmProp = RenameProposal(
        originalFilePath: '/media/A001C001.CRM',
        proposedFileName: 'PROJ_261028_10_1_T1_A001_D1_U1.CRM',
        fileReel: 'A001',
        fileTcIn: '02:00:00:00',
        fileTcOut: '02:03:00:00',
        status: ProposalStatus.ready,
      );
      final crmReport = DryRunReport(proposals: [crmProp]);

      await tester.pumpWidget(createHomeScreen(project: project, report: crmReport));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
      }
      await tester.pumpAndSettle();

      // Video player container rendered
      expect(find.byKey(const ValueKey('studio_video_player_container')), findsOneWidget);

      // Dedicated Canon Cinema RAW Light HUD is displayed (no proxy present)
      expect(find.byKey(const ValueKey('studio_canon_raw_hud')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_canon_raw_badge')), findsOneWidget);
      expect(find.text('[CANON CINEMA RAW LIGHT]'), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_smpte_live_badge')), findsOneWidget);
      expect(find.text('[AUDIO & TIMECODE SMPTE EN VIVO]'), findsOneWidget);

      // Verified SMPTE Timecode and native format badge
      expect(find.text('Timecode: 02:00:00:00 → 02:03:00:00'), findsOneWidget);
      expect(find.text('Formato nativo: .CRM'), findsOneWidget);

      // Status message
      expect(
        find.text(
          'Reproduciendo audio nativo PCM (24-bit) y código de tiempo SMPTE sincronizado. El formato CRAW de sensor opera en modo claqueta de audio.',
        ),
        findsOneWidget,
      );

      // Active waveform / equalizer container
      expect(find.byKey(const ValueKey('studio_craw_audio_waveform')), findsOneWidget);

      // Dedicated transport bar rendered below
      expect(find.byKey(const ValueKey('studio_transport_bar')), findsOneWidget);
    });

    testWidgets('Test 7: Studio Mode with .WAV audio renders Audio / RAW Studio Monitor HUD, BWF badge, and track meters', (tester) async {
      setupDesktopWindow(tester);

      final wavProp = RenameProposal(
        originalFilePath: '/media/AUDIO_A001C001.WAV',
        proposedFileName: 'PROJ_261028_10_1_T1_A001_D1_U1.WAV',
        fileReel: 'A001',
        fileTcIn: '03:15:00:00',
        fileTcOut: '03:17:30:00',
        status: ProposalStatus.ready,
      );
      final wavReport = DryRunReport(proposals: [wavProp]);

      await tester.pumpWidget(createHomeScreen(project: project, report: wavReport));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
      }
      await tester.pumpAndSettle();

      // Audio / RAW monitor HUD is rendered
      expect(find.byKey(const ValueKey('studio_audio_raw_hud')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_format_badge')), findsOneWidget);
      expect(find.text('BROADCAST WAV · BWF'), findsOneWidget);

      // Audio waveform and multi-track indicators rendered
      expect(find.byKey(const ValueKey('studio_audio_waveform')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_audio_track_indicators')), findsOneWidget);
      expect(find.text('CH 1 [L]'), findsOneWidget);
      expect(find.text('CH 2 [R]'), findsOneWidget);

      // In-HUD volume button
      expect(find.byKey(const ValueKey('studio_hud_volume')), findsOneWidget);

      // Advance audio position and verify in-HUD timecode
      final dynamic homeState = tester.state(find.byType(HomeScreen));
      homeState.studioPositionNotifier.value = const Duration(seconds: 5);
      await tester.pumpAndSettle();

      expect(find.text('SMPTE: 03:15:05:00'), findsAtLeast(1));
    });

    testWidgets('Test 8: stream.error triggers Broadcast Slate Monitor with timecode and format info', (tester) async {
      setupDesktopWindow(tester);

      final fakePlayer = FakePlayer();

      final mxfProp = RenameProposal(
        originalFilePath: '/media/A001C001.MXF',
        proposedFileName: 'PROJ_261028_10_1_T1_A001_D1_U1.MXF',
        fileReel: 'A001',
        fileTcIn: '01:00:00:00',
        fileTcOut: '01:05:00:00',
        status: ProposalStatus.ready,
      );
      final mxfReport = DryRunReport(proposals: [mxfProp]);

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          initialProject: project,
          initialReport: mxfReport,
          customStudioPlayer: fakePlayer,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
      }
      await tester.pumpAndSettle();

      // Initially no error: InteractiveViewer is rendered, slate monitor is not
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_broadcast_slate_monitor')), findsNothing);

      // Simulate stream.error emitting an unsupported/unrecognized container error
      fakePlayer._stream.emitError('Failed to recognize file format.');
      await tester.pumpAndSettle();

      // Broadcast Slate Monitor is now visible
      expect(find.byKey(const ValueKey('studio_broadcast_slate_monitor')), findsOneWidget);
      expect(find.byIcon(Icons.movie_filter_outlined), findsOneWidget);
      expect(find.text('[MONITOR DE METADATOS SMPTE]'), findsOneWidget);
      expect(find.text('[BROADCAST / RAW MONITOR]'), findsOneWidget);
      expect(
        find.text(
          'Metadatos y Timecode SMPTE sincronizados. El códec nativo no requiere decodificación visual para reconciliación y renombrado.',
        ),
        findsOneWidget,
      );
      expect(find.text('Timecode: 01:00:00:00 → 01:05:00:00'), findsOneWidget);
      expect(find.text('Formato nativo: .MXF'), findsOneWidget);
      expect(find.text('Failed to recognize file format.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('studio_broadcast_slate_monitor')),
          matching: find.text('A001C001.MXF'),
        ),
        findsOneWidget,
      );

      // InteractiveViewer is replaced by fallback
      expect(find.byType(InteractiveViewer), findsNothing);

      // Switching clips resets error state and restores standard viewer
      final prop2 = RenameProposal(
        originalFilePath: '/media/A001C002.MP4',
        proposedFileName: 'PROJ_261028_10_2_T1_A001_D1_U1.MP4',
        fileReel: 'A001',
        fileTcIn: '01:05:00:00',
        fileTcOut: '01:10:00:00',
        status: ProposalStatus.ready,
      );
      final dynamic homeState = tester.state(find.byType(HomeScreen));
      homeState.selectStudioClip(prop2);
      await tester.pumpAndSettle();

      expect(homeState.studioPlaybackErrorNotifier.value, isNull);
      expect(find.byKey(const ValueKey('studio_broadcast_slate_monitor')), findsNothing);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('Test 9: Option B: Studio Mode with .CRM and companion poster frame renders visual backdrop', (tester) async {
      setupDesktopWindow(tester);

      final tempDir = Directory.systemTemp.createTempSync('crm_poster_test_');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final dummyImage = File('${tempDir.path}/dummy.jpg')..createSync();
      MediaProxyUtils.testPosterFrames['/media/A001C001.CRM'] = dummyImage;
      addTearDown(MediaProxyUtils.resetTestMocks);

      final crmProp = RenameProposal(
        originalFilePath: '/media/A001C001.CRM',
        proposedFileName: 'PROJ_261028_10_1_T1_A001_D1_U1.CRM',
        fileReel: 'A001',
        fileTcIn: '02:00:00:00',
        fileTcOut: '02:03:00:00',
        status: ProposalStatus.ready,
      );
      final crmReport = DryRunReport(proposals: [crmProp]);

      await tester.pumpWidget(createHomeScreen(project: project, report: crmReport));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
      }
      await tester.pumpAndSettle();

      // Poster frame Image is rendered in backdrop
      expect(find.byType(Image), findsWidgets);
      expect(find.byKey(const ValueKey('studio_canon_raw_hud')), findsOneWidget);
    });

    testWidgets('Test 10: Option C: Camera proxy auto-pairing enables video playback and displays green proxy badge', (tester) async {
      setupDesktopWindow(tester);

      MediaProxyUtils.testLinkedProxies['/media/A001C001.CRM'] = '/media/Proxy/A001C001_Proxy.mp4';
      addTearDown(MediaProxyUtils.resetTestMocks);

      final crmProp = RenameProposal(
        originalFilePath: '/media/A001C001.CRM',
        proposedFileName: 'PROJ_261028_10_1_T1_A001_D1_U1.CRM',
        fileReel: 'A001',
        fileTcIn: '02:00:00:00',
        fileTcOut: '02:03:00:00',
        status: ProposalStatus.ready,
      );
      final crmReport = DryRunReport(proposals: [crmProp]);

      await tester.pumpWidget(createHomeScreen(project: project, report: crmReport));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
      }
      await tester.pumpAndSettle();

      // With paired proxy, InteractiveViewer and video surface are restored
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_proxy_linked_badge')), findsOneWidget);
      expect(find.text('[PROXY VINCULADO: A001C001_Proxy.mp4]'), findsAtLeast(1));

      // Master proposal file path remains untouched strictly bound to .CRM
      final dynamic homeState = tester.state(find.byType(HomeScreen));
      expect(homeState.selectedStudioClip?.originalFilePath, equals('/media/A001C001.CRM'));
    });

    testWidgets('Test 11: Failed to initialize a decoder for codec activates Canon Cinema RAW HUD without red diagnostic pill', (tester) async {
      setupDesktopWindow(tester);

      final fakePlayer = FakePlayer();

      final crmProp = RenameProposal(
        originalFilePath: '/media/A001C001.CRM',
        proposedFileName: 'PROJ_261028_10_1_T1_A001_D1_U1.CRM',
        fileReel: 'A001',
        fileTcIn: '01:00:00:00',
        fileTcOut: '01:05:00:00',
        status: ProposalStatus.ready,
      );
      final crmReport = DryRunReport(proposals: [crmProp]);

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          initialProject: project,
          initialReport: crmReport,
          customStudioPlayer: fakePlayer,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final studioBtn = find.widgetWithText(OutlinedButton, 'Modo Estudio');
      if (studioBtn.evaluate().isNotEmpty) {
        await tester.tap(studioBtn);
      }
      await tester.pumpAndSettle();

      // Emit decoder failure error
      fakePlayer._stream.emitError('Failed to initialize a decoder for codec: rawvideo');
      await tester.pumpAndSettle();

      // Canon Cinema RAW HUD is shown
      expect(find.byKey(const ValueKey('studio_canon_raw_hud')), findsOneWidget);
      expect(find.text('[CANON CINEMA RAW LIGHT]'), findsOneWidget);
      expect(find.text('[AUDIO & TIMECODE SMPTE EN VIVO]'), findsOneWidget);

      // Red diagnostic pill / error box is NOT displayed
      expect(find.text('Failed to initialize a decoder for codec: rawvideo'), findsNothing);
    });
  });
}
