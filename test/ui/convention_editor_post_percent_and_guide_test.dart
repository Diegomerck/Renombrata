import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:renombrata/src/ui/widgets/convention_sequence_guide.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void setupDesktopWindow(WidgetTester tester, {double width = 1400, double height = 900}) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('Convention Editor Post-% Suffix & Guide Tests', () {
    testWidgets('ConventionSequenceGuide renders in Studio Convention Editor', (tester) async {
      setupDesktopWindow(tester);
      SharedPreferences.setMockInitialValues({});

      final project = RenombrataProject(
        showChapter: true,
        showPlane: true,
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(
            production: 'MNBOENC',
            nomenclature: 'MNBOENC',
            date: '080626',
            day: '1',
            unit: '3',
          ),
          records: [],
        ),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001_260608AB.MP4',
        proposedFileName: 'A001C001_260608AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1]);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            initialStudioMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Ensure ConventionSequenceGuide is present in convention pane
      expect(find.byType(ConventionSequenceGuide), findsOneWidget);
      expect(find.byKey(const ValueKey('guide_token_PROD')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide_token_ESC')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide_token_TOMA')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide_token_% METADATOS')), findsOneWidget);
    });

    testWidgets('Live line status displays camera badge and dimmed % sub-convention', (tester) async {
      setupDesktopWindow(tester);
      SharedPreferences.setMockInitialValues({});

      final project = RenombrataProject(
        showChapter: true,
        showPlane: true,
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(
            production: 'MNBOENC',
            nomenclature: 'MNBOENC',
            date: '080626',
            day: '1',
            unit: '3',
          ),
          records: [],
        ),
        defaultReel: 'A001',
        activeCamera: 'ALL',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001_260608AB.MP4',
        proposedFileName: 'A001C001_260608AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final prop2 = RenameProposal(
        originalFilePath: '/media/B001C002_260608AB.MP4',
        proposedFileName: 'B001C002_260608AB.MP4',
        fileReel: 'B001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1, prop2]);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            initialStudioMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Enter text via tester.enterText on convention editor field
      final editorField = find.byKey(const ValueKey('studio_convention_editor_field'));
      expect(editorField, findsOneWidget);

      await tester.enterText(
        editorField,
        'MNBOENC_080626_17_11_T1_A001_1_D1_U3\nMNBOENC_080626_17_11_T2_B001_2_D1_U3',
      );
      await tester.pumpAndSettle();

      // Find Camera Badges in live line statuses
      expect(find.text('CAM A'), findsWidgets);
      expect(find.text('CAM B'), findsWidgets);

      // Verify that sub-conventions with % are populated in line statuses
      expect(find.textContaining('%A001_001_080626_U1'), findsOneWidget);
      expect(find.textContaining('%B001_002_080626_U1'), findsOneWidget);
    });

    testWidgets('debounced auto-save preserves % sub-convention in convention editor', (tester) async {
      setupDesktopWindow(tester);
      SharedPreferences.setMockInitialValues({});

      final project = RenombrataProject(
        showChapter: true,
        showPlane: true,
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(
            production: 'MNBOENC',
            nomenclature: 'MNBOENC',
            date: '080626',
            day: '1',
            unit: '3',
          ),
          records: [],
        ),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001_260608AB.MP4',
        proposedFileName: 'A001C001_260608AB.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1]);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialReport: report,
            initialStudioMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final controller = homeState.conventionEditorController as TextEditingController;

      // Populate convention editor with a line containing % metadata
      await tester.enterText(
        find.byKey(const ValueKey('studio_convention_editor_field')),
        'MNBOENC_080626_17_11_T1_A001_1_D1_U3%A001_001_080626_U1',
      );
      await tester.pumpAndSettle();

      expect(controller.text, contains('%A001_001_080626_U1'));

      // Edit take field in the slate editor
      final takeField = find.byKey(const ValueKey('studio_slate_take_field'));
      expect(takeField, findsOneWidget);
      await tester.enterText(takeField, '2');
      await tester.pump();

      // Verify that immediately upon field edit, % suffix is maintained
      expect(controller.text, contains('T2'));
      expect(controller.text, contains('%A001_001_080626_U1'));

      // Wait 350ms for debounce timer to fire _saveStudioSlate(isAutoSave: true)
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Verify that after auto-save completes, % metadata suffix is STILL preserved!
      expect(controller.text, contains('T2'));
      expect(controller.text, contains('%A001_001_080626_U1'));
    });

    testWidgets('Splitter calculation guarantees minimum center width >= 420px', (tester) async {
      setupDesktopWindow(tester, width: 1100, height: 720);
      SharedPreferences.setMockInitialValues({});

      final project = RenombrataProject(
        defaultReel: 'A001',
        activeCamera: 'A',
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            initialProject: project,
            initialStudioMode: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final homeState = tester.state(find.byType(HomeScreen)) as dynamic;
      final widths = homeState.calculateStudioPaneWidths(1100.0) as ({double mediaWidth, double conventionWidth});

      // Total width is 1100. Center should have at least 420px.
      final centerWidth = 1100.0 - widths.mediaWidth - widths.conventionWidth - 24.0;
      expect(centerWidth, greaterThanOrEqualTo(420.0));
    });
  });
}
