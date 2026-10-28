import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';

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

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
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

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
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

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
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

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
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
  });
}
