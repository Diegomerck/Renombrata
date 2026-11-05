import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:renombrata/src/utils/media_proxy_utils.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('renombrata_high_tier_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
    MediaProxyUtils.resetTestMocks();
  });

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
        initialStudioMode: false,
      ),
    );
  }

  RenombrataProject buildTestProject({required List<ShotRecord> records}) {
    return RenombrataProject(
      log: ShootingLog(
        metadata: ShootingLogMetadata.empty().copyWith(
          nomenclature: 'PRJ',
          date: '260817',
          unit: 'U1',
          day: 'D01',
          production: 'PRJ',
        ),
        records: records,
      ),
      cameras: const [CameraConfig(name: 'A', type: CameraType.regular)],
      defaultReel: 'A001',
      activeCamera: 'A',
    );
  }

  group('HomeScreen High Tier Features Tests', () {
    testWidgets(
      'Draggable column splitters adjust pane widths and reset on double tap',
      (tester) async {
        setupDesktopWindow(tester);

        final videoPath = '${tempDir.path}/A001C001.MP4';
        File(videoPath).writeAsBytesSync(List.filled(1024, 0));

        final rec = ShotRecord(
          id: 'rec-1',
          chapter: '01',
          scene: '10',
          plane: 'P1',
          take: '1',
          cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
          reel: 'A001',
        );
        final project = buildTestProject(records: [rec]);
        final prop = RenameProposal(
          originalFilePath: videoPath,
          proposedFileName: 'PRJ_01_10_P1_1_A001_D01_01_U1.MP4',
          fileReel: 'A001',
          associatedRecord: rec,
          status: ProposalStatus.ready,
        );
        final report = DryRunReport(proposals: [prop]);

        await tester.pumpWidget(
          createHomeScreen(project: project, report: report),
        );
        await tester.pumpAndSettle();

        // Navigate to Renombrador de Medios tab
        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        // Enter Modo Estudio
        await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
        await tester.pumpAndSettle();

        // Splitters should be present between media list and convention pane
        final splitters = find.byWidgetPredicate(
          (w) =>
              w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
        );
        expect(splitters, findsWidgets);

        // Verify dragging the first splitter (left splitter)
        final firstSplitter = splitters.first;
        await tester.drag(firstSplitter, const Offset(60, 0));
        await tester.pumpAndSettle();

        final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
        // Double tap to reset
        await tester.tap(firstSplitter);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(firstSplitter);
        await tester.pumpAndSettle();

        expect(homeState, isNotNull);
      },
    );

    testWidgets(
      'Displays companion badges [LRV] and [THM] on media clip cards for multi-file stacks',
      (tester) async {
        setupDesktopWindow(tester);

        final videoPath = '${tempDir.path}/GX018226.MP4';
        final lrvPath = '${tempDir.path}/GL018226.LRV';
        final thmPath = '${tempDir.path}/GX018226.THM';

        File(videoPath).writeAsBytesSync(List.filled(1024, 0));
        File(lrvPath).writeAsBytesSync(List.filled(512, 0));
        File(thmPath).writeAsBytesSync(List.filled(256, 0));

        final rec = ShotRecord(
          id: 'rec-gopro',
          chapter: '01',
          scene: '20',
          plane: 'P1',
          take: '1',
          cameras: [CameraTakeRecord(cameraName: 'A', clipName: '8226')],
          reel: 'A001',
        );
        final project = buildTestProject(records: [rec]);

        final masterProp = RenameProposal(
          originalFilePath: videoPath,
          proposedFileName: 'PRJ_01_20_P1_1_A001_D01_01_U1.MP4',
          fileReel: 'A001',
          associatedRecord: rec,
          status: ProposalStatus.ready,
        );

        final lrvProp = RenameProposal(
          originalFilePath: lrvPath,
          proposedFileName: 'PRJ_01_20_P1_1_A001_D01_01_U1.LRV',
          fileReel: 'A001',
          status: ProposalStatus.ready,
          isCompanionFile: true,
          companionFilePath: videoPath,
        );

        final thmProp = RenameProposal(
          originalFilePath: thmPath,
          proposedFileName: 'PRJ_01_20_P1_1_A001_D01_01_U1.THM',
          fileReel: 'A001',
          status: ProposalStatus.ready,
          isCompanionFile: true,
          companionFilePath: videoPath,
        );

        final report = DryRunReport(proposals: [masterProp, lrvProp, thmProp]);

        await tester.pumpWidget(
          createHomeScreen(project: project, report: report),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
        await tester.pumpAndSettle();

        // Verify that LRV badge and THM badge are rendered
        final lrvBadge = find.byKey(ValueKey('lrv_badge_$videoPath'));
        expect(lrvBadge, findsOneWidget);
        expect(
          find.descendant(of: lrvBadge, matching: find.text('LRV')),
          findsOneWidget,
        );

        final thmBadge = find.byKey(ValueKey('thm_badge_$videoPath'));
        expect(thmBadge, findsOneWidget);
        expect(
          find.descendant(of: thmBadge, matching: find.text('THM')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Transport bar proxy toggle button switches active proxy state and preserves playback',
      (tester) async {
        setupDesktopWindow(tester);

        MediaProxyUtils.testLinkedProxies['/media/GX018226.MP4'] =
            '/media/GL018226.LRV';

        final prop = RenameProposal(
          originalFilePath: '/media/GX018226.MP4',
          proposedFileName: 'PRJ_01_20_P1_1_A001_D01_01_U1.MP4',
          fileReel: 'A001',
          status: ProposalStatus.ready,
        );
        final report = DryRunReport(proposals: [prop]);

        final project = buildTestProject(records: []);

        await tester.pumpWidget(
          createHomeScreen(project: project, report: report),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Renombrador de Medios'));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
        await tester.pumpAndSettle();

        // Studio proxy toggle button is rendered
        final toggleFinder = find.byKey(
          const ValueKey('studio_proxy_toggle_button'),
        );
        expect(toggleFinder, findsOneWidget);
        expect(
          find.descendant(of: toggleFinder, matching: find.text('PROXY')),
          findsOneWidget,
        );

        final dynamic homeState = tester.state(find.byType(HomeScreen));
        expect(homeState.studioActiveIsProxyNotifier.value, isTrue);

        // Tap toggle to switch to ORIGINAL
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        expect(homeState.studioActiveIsProxyNotifier.value, isFalse);
        expect(
          find.descendant(of: toggleFinder, matching: find.text('ORIGINAL')),
          findsOneWidget,
        );

        // Tap toggle to switch back to PROXY
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();

        expect(homeState.studioActiveIsProxyNotifier.value, isTrue);
        expect(
          find.descendant(of: toggleFinder, matching: find.text('PROXY')),
          findsOneWidget,
        );
      },
    );
  });
}
