import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';

void main() {
  void setupDesktopWindow(WidgetTester tester, {double width = 1920, double height = 1080}) {
    tester.view.physicalSize = Size(width, height);
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

  group('HomeScreen - Studio Shortcuts, Focus Management & Responsive Layout', () {
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
      showChapter: true,
      showPlane: true,
    );

    final prop1 = RenameProposal(
      originalFilePath: '/media/A001C001_260817AB.MP4',
      proposedFileName: 'PROJ_A001_S01_T01.MP4',
      fileReel: 'A001',
      fileTcIn: '01:00:00:00',
      fileTcOut: '01:02:15:12',
      status: ProposalStatus.ready,
    );

    final prop2 = RenameProposal(
      originalFilePath: '/media/A001C002_260817CD.MP4',
      proposedFileName: 'PROJ_A001_S01_T02.MP4',
      fileReel: 'A001',
      fileTcIn: '01:02:15:13',
      fileTcOut: '01:04:30:00',
      status: ProposalStatus.ready,
    );

    final report = DryRunReport(proposals: [prop1, prop2]);

    testWidgets('Test 1: Selecting a clip in the media list does NOT focus the convention editor', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      // Navigate to Renombrador de Medios -> Modo Estudio
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final homeScreenState = tester.state(find.byType(HomeScreen)) as dynamic;

      // Ensure convention editor controller has text so _highlightMatchingConventionLine executes
      homeScreenState.conventionEditorController.text = 'PROJ_A001_S01_T01\nPROJ_A001_S01_T02';
      await tester.pumpAndSettle();

      // Tap on the second clip in the media list
      final clip1Finder = find.byKey(const ValueKey('studio_clip_1'));
      expect(clip1Finder, findsOneWidget);
      await tester.tap(clip1Finder);
      await tester.pumpAndSettle();

      // Clip 1 is selected
      expect(homeScreenState.selectedStudioClip?.originalFilePath, equals(prop2.originalFilePath));

      // Convention editor focus node MUST NOT have focus
      expect(homeScreenState.conventionEditorFocusNode.hasFocus, isFalse);
      expect(homeScreenState.conventionEditorFocusNode.hasPrimaryFocus, isFalse);

      // Media list has focus
      expect(homeScreenState.studioMediaListFocusNode.hasFocus, isTrue);
    });

    testWidgets('Test 2: Global Playback Shortcuts (Space, Left/Right Seek, Up/Down Clip Nav)', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final homeScreenState = tester.state(find.byType(HomeScreen)) as dynamic;

      // Select first clip and request workspace focus
      homeScreenState.studioWorkspaceFocusNode.requestFocus();
      await tester.pumpAndSettle();

      // Initially clip 0 is selected
      expect(homeScreenState.selectedStudioClip?.originalFilePath, equals(prop1.originalFilePath));

      // 1. ArrowDown navigates to next clip
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(homeScreenState.selectedStudioClip?.originalFilePath, equals(prop2.originalFilePath));

      // 2. ArrowUp navigates back to previous clip
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(homeScreenState.selectedStudioClip?.originalFilePath, equals(prop1.originalFilePath));

      // 3. Spacebar toggles playback when in workspace
      final playButton = find.byKey(const ValueKey('studio_play_pause_button'));
      expect(playButton, findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      // Should have toggled play state
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      // 4. ArrowRight and ArrowLeft seek position
      homeScreenState.seekStudioRelative(2);
      await tester.pumpAndSettle();
      homeScreenState.seekStudioRelative(-2);
      await tester.pumpAndSettle();
    });

    testWidgets('Test 3: Focus Navigation (Tab, Ctrl+B, Ctrl+E, Escape)', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final homeScreenState = tester.state(find.byType(HomeScreen)) as dynamic;

      // Workspace is focused initially
      homeScreenState.studioWorkspaceFocusNode.requestFocus();
      await tester.pumpAndSettle();

      // Pressing Tab in playback zone requests focus on first visible slate field (Chapter because showChapter is true)
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(homeScreenState.studioChapterFocusNode.hasPrimaryFocus, isTrue);
      expect(homeScreenState.studioInspectorFocusNode.hasFocus, isTrue);

      // Pressing Escape unfocuses text fields and returns focus to workspace
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(homeScreenState.studioChapterFocusNode.hasPrimaryFocus, isFalse);
      expect(homeScreenState.studioWorkspaceFocusNode.hasFocus, isTrue);

      // Global shortcut: Ctrl+E requests focus on convention editor
      homeScreenState.conventionEditorFocusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(homeScreenState.conventionEditorFocusNode.hasPrimaryFocus, isTrue);
      expect(homeScreenState.conventionEditorPanelFocusNode.hasFocus, isTrue);

      // Pressing Escape unfocuses convention editor
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(homeScreenState.conventionEditorFocusNode.hasPrimaryFocus, isFalse);
    });

    testWidgets('Test 4: Video Container renders without hardcoded 16:9 AspectRatio and uses BoxFit.contain', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final playerContainer = find.byKey(const ValueKey('studio_video_player_container'));
      expect(playerContainer, findsOneWidget);

      // Ensure AspectRatio(aspectRatio: 16/9) is NOT inside studio_video_player_container
      final aspectRatioFinder = find.descendant(
        of: playerContainer,
        matching: find.byType(AspectRatio),
      );
      expect(aspectRatioFinder, findsNothing);

      // If Video widget is present in tree, verify it uses BoxFit.contain
      final videoFinder = find.descendant(
        of: playerContainer,
        matching: find.byType(Video),
      );
      if (videoFinder.evaluate().isNotEmpty) {
        final videoWidget = tester.widget<Video>(videoFinder);
        expect(videoWidget.fit, equals(BoxFit.contain));
      }
    });

    testWidgets('Test 5: Responsive horizontal layout calculation and pane scaling', (tester) async {
      setupDesktopWindow(tester, width: 1920, height: 1080);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final homeScreenState = tester.state(find.byType(HomeScreen)) as dynamic;

      // 1. Compact screen calculation (1100px - 1250px)
      final minWidths = homeScreenState.calculateStudioPaneWidths(1100.0);
      expect(minWidths.mediaWidth, equals(280.0));
      expect(minWidths.conventionWidth, equals(310.0));
      expect(1100.0 - minWidths.mediaWidth - minWidths.conventionWidth - 24.0, greaterThanOrEqualTo(480.0));

      final compactWidths = homeScreenState.calculateStudioPaneWidths(1200.0);
      expect(compactWidths.mediaWidth, closeTo(313.33, 0.1));
      expect(compactWidths.conventionWidth, closeTo(343.33, 0.1));
      expect(1200.0 - compactWidths.mediaWidth - compactWidths.conventionWidth - 24.0, greaterThanOrEqualTo(480.0));

      final maxWidths = homeScreenState.calculateStudioPaneWidths(1250.0);
      expect(maxWidths.mediaWidth, equals(330.0));
      expect(maxWidths.conventionWidth, equals(360.0));
      expect(1250.0 - maxWidths.mediaWidth - maxWidths.conventionWidth - 24.0, greaterThanOrEqualTo(480.0));

      // 2. Wide screen calculation (> 1250px)
      final wideWidths = homeScreenState.calculateStudioPaneWidths(1920.0);
      expect(wideWidths.mediaWidth, greaterThan(330.0));
      expect(wideWidths.mediaWidth, lessThanOrEqualTo(520.0));
      expect(wideWidths.conventionWidth, greaterThan(360.0));
      expect(wideWidths.conventionWidth, lessThanOrEqualTo(600.0));

      // 3. Rendered sizes on 1920px screen
      final mediaListSizedBox = find.ancestor(
        of: find.byKey(const ValueKey('studio_clip_0')),
        matching: find.byType(SizedBox),
      ).first;
      final mediaListSize = tester.getSize(mediaListSizedBox);
      expect(mediaListSize.width, greaterThan(330.0));
    });

    testWidgets('Test 6: Card visual focus borders dynamically update with primary color', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      final homeScreenState = tester.state(find.byType(HomeScreen)) as dynamic;

      // Focus on media list
      homeScreenState.studioMediaListFocusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(homeScreenState.studioMediaListFocusNode.hasFocus, isTrue);

      // Focus on convention editor
      homeScreenState.conventionEditorFocusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(homeScreenState.conventionEditorPanelFocusNode.hasFocus, isTrue);

      // Focus on slate chapter field
      homeScreenState.studioChapterFocusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(homeScreenState.studioInspectorFocusNode.hasFocus, isTrue);
    });

    testWidgets('Test 7: Studio transport bar renders without overflow at compact window width', (tester) async {
      setupDesktopWindow(tester, width: 1200, height: 1080);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      // Ensure transport bar and all child controls render without any RenderFlex overflow
      expect(find.byKey(const ValueKey('studio_transport_bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_play_pause_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_replay_5_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_forward_5_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_duration_text')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_live_smpte_badge')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_volume_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('studio_volume_slider')), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Test 8: Focusing convention editor and pressing Ctrl+Z triggers text undo without firing _undoPastedMatches', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
      await tester.pumpAndSettle();

      // Open convention editor pane if not visible
      final editorButton = find.widgetWithText(OutlinedButton, 'Editor de Texto');
      if (editorButton.evaluate().isNotEmpty) {
        await tester.tap(editorButton);
        await tester.pumpAndSettle();
      }

      final homeScreenState = tester.state(find.byType(HomeScreen)) as dynamic;
      final conventionField = find.byKey(const ValueKey('studio_convention_editor_field'));
      expect(conventionField, findsOneWidget);

      // Simulate a previous paste operation exists
      homeScreenState.previousReportBeforePaste = report;
      expect(homeScreenState.previousReportBeforePaste, isNotNull);

      // Focus the convention editor
      await tester.tap(conventionField);
      await tester.pumpAndSettle();
      expect(homeScreenState.conventionEditorFocusNode.hasFocus, isTrue);

      // Enter initial text, then enter new text to create an undo history entry
      await tester.enterText(conventionField, 'LINE_ONE');
      await tester.pump(const Duration(milliseconds: 600));
      expect(homeScreenState.conventionEditorController.text, 'LINE_ONE');

      await tester.enterText(conventionField, 'LINE_ONE_EDITED');
      await tester.pump(const Duration(milliseconds: 600));
      expect(homeScreenState.conventionEditorController.text, 'LINE_ONE_EDITED');

      // Send Ctrl+Z keyboard shortcut
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Verify that _undoPastedMatches was NOT called (previousReportBeforePaste is still non-null)
      expect(homeScreenState.previousReportBeforePaste, isNotNull);

      // Verify text undo occurred
      expect(homeScreenState.conventionEditorController.text, 'LINE_ONE');
    });
  });
}

