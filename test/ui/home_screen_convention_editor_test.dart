import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/conflict_resolver_dialog.dart';
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

  group('HomeScreen - In-Tab Convention Editor & Interactive Conflict Resolution', () {
    testWidgets('toggles convention editor pane on and off via toolbar button', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop = RenameProposal(
        originalFilePath: '/media/A001C001.MP4',
        proposedFileName: 'A001C001.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      // Switch to Renombrador de Medios tab
      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Editor pane is initially hidden
      expect(find.text('Convención de Texto'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Editor de Texto'), findsOneWidget);

      // Tap toggle button to show editor pane
      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      // Editor pane is now visible and button updates to "Ocultar Editor"
      expect(find.text('Convención de Texto'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Ocultar Editor'), findsOneWidget);

      // Tap toggle button again to hide editor pane
      await tester.tap(find.widgetWithText(OutlinedButton, 'Ocultar Editor'));
      await tester.pumpAndSettle();

      // Editor pane is hidden again
      expect(find.text('Convención de Texto'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Editor de Texto'), findsOneWidget);
    });

    testWidgets('typing convention text updates DataTable proposed names in real time', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001.MP4',
        proposedFileName: 'OLD_01.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final prop2 = RenameProposal(
        originalFilePath: '/media/A001C002.MP4',
        proposedFileName: 'OLD_02.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1, prop2]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Initially shows unmatched clip status
      expect(find.text('Clip no registrado'), findsNWidgets(2));

      // Open convention editor
      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      // Type convention lines in editor
      final textFields = find.byType(TextField);
      await tester.enterText(
        textFields.last,
        'PROD_01_01_T1_A001_D01_001_U1\nPROD_01_01_T2_A001_D01_002_U1',
      );
      await tester.pump();

      // Real-time update in DataTable
      expect(find.text('PROD_01_01_T1_A001_D01_001_U1.MP4'), findsOneWidget);
      expect(find.text('PROD_01_01_T2_A001_D01_002_U1.MP4'), findsOneWidget);
      expect(find.text('✓ Texto (Línea 1)'), findsOneWidget);
      expect(find.text('✓ Texto (Línea 2)'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
      expect(find.text('Líneas: 2 | Clips coincidentes: 2/2'), findsOneWidget);
    });

    testWidgets('detects duplicate clip conflict on disk and resolves it via interactive dialog', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A007',
        activeCamera: 'A',
      );

      // Two files on disk for Reel A007 Clip 001
      final prop1 = RenameProposal(
        originalFilePath: '/media/A007C001_240810_1234.MP4',
        proposedFileName: 'A007C001_240810_1234.MP4',
        fileReel: 'A007',
        status: ProposalStatus.unmatchedClip,
      );

      final prop1Alt = RenameProposal(
        originalFilePath: '/media/A007C001_ALT.MP4',
        proposedFileName: 'A007C001_ALT.MP4',
        fileReel: 'A007',
        status: ProposalStatus.unmatchedClip,
      );

      // One unique file for Clip 002
      final prop2 = RenameProposal(
        originalFilePath: '/media/A007C002.MP4',
        proposedFileName: 'A007C002.MP4',
        fileReel: 'A007',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1, prop1Alt, prop2]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Open editor
      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      // Enter convention lines for Clip 1 and Clip 2
      final textFields = find.byType(TextField);
      await tester.enterText(
        textFields.last,
        'PROD_01_01_T1_A007_D01_001_U1\nPROD_01_01_T2_A007_D01_002_U1',
      );
      await tester.pump();

      // Duplicate files on disk for Clip #01 are flagged with conflict badges
      expect(find.text('Conflicto: Clip #01 duplicado'), findsNWidgets(2));
      // Clip 2 has a clean match
      expect(find.text('PROD_01_01_T2_A007_D01_002_U1.MP4'), findsOneWidget);

      // Tap on conflict badge to open master resolver dialog
      await tester.ensureVisible(find.text('Conflicto: Clip #01 duplicado').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conflicto: Clip #01 duplicado').first);
      await tester.pumpAndSettle();

      // Verify ConflictResolverDialog is open
      expect(find.byType(ConflictResolverDialog), findsOneWidget);
      expect(find.text('Resolución de Conflictos de Medios'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(ConflictResolverDialog), matching: find.text('A007C001_240810_1234.MP4')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(ConflictResolverDialog), matching: find.text('A007C001_ALT.MP4')),
        findsOneWidget,
      );

      // In ConflictResolverDialog, first candidate is already winner by default and second is alternate.
      // Confirm changes by tapping 'Guardar cambios'
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar cambios'));
      await tester.pumpAndSettle();

      // Dialog closed, conflict resolved
      expect(find.text('Conflicto: Clip #01 duplicado'), findsNothing);
      expect(find.text('Conflicto resuelto correctamente'), findsOneWidget);

      // A007C001_240810_1234.MP4 receives the convention name
      expect(find.text('PROD_01_01_T1_A007_D01_001_U1.MP4'), findsOneWidget);
      // A007C001_ALT.MP4 receives the _ALT suffix
      expect(find.text('PROD_01_01_T1_A007_D01_001_U1_ALT.MP4'), findsOneWidget);
    });

    testWidgets('non-blocking apply assigns valid matches while preserving unresolved conflicts', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A007',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A007C001_240810_1234.MP4',
        proposedFileName: 'A007C001_240810_1234.MP4',
        fileReel: 'A007',
        status: ProposalStatus.unmatchedClip,
      );

      final prop1Alt = RenameProposal(
        originalFilePath: '/media/A007C001_ALT.MP4',
        proposedFileName: 'A007C001_ALT.MP4',
        fileReel: 'A007',
        status: ProposalStatus.unmatchedClip,
      );

      final prop2 = RenameProposal(
        originalFilePath: '/media/A007C002.MP4',
        proposedFileName: 'A007C002.MP4',
        fileReel: 'A007',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1, prop1Alt, prop2]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      // Open editor
      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      // Enter text
      final textFields = find.byType(TextField);
      await tester.enterText(
        textFields.last,
        'PROD_01_01_T1_A007_D01_001_U1\nPROD_01_01_T2_A007_D01_002_U1',
      );
      await tester.pump();

      // Button shows "Aplicar Coincidencias (1)" because only Clip 2 is clean
      final applyButton = find.widgetWithText(FilledButton, 'Aplicar Coincidencias (1)');
      expect(applyButton, findsOneWidget);

      await tester.tap(applyButton);
      await tester.pumpAndSettle();

      // SnackBar informs non-blocking apply result with unresolved count
      expect(
        find.text('1 nombres aplicados (2 pendientes de resolver)'),
        findsOneWidget,
      );

      // Conflicts are preserved
      expect(find.text('Conflicto: Clip #01 duplicado'), findsNWidgets(2));
      // Clean match is committed
      expect(find.text('PROD_01_01_T2_A007_D01_002_U1.MP4'), findsOneWidget);
    });

    testWidgets('clearing editor text resets real-time overrides and status', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop = RenameProposal(
        originalFilePath: '/media/A001C001.MP4',
        proposedFileName: 'ORIG_01.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.last, 'NEW_CONV_01');
      await tester.pump();

      expect(find.text('NEW_CONV_01.MP4'), findsOneWidget);

      // Tap Limpiar button (IconButton with clear_all_rounded)
      final clearButton = find.byIcon(Icons.clear_all_rounded);
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pump();

      // DataTable reverts back to original
      expect(find.text('NEW_CONV_01.MP4'), findsNothing);
      expect(find.text('Clip no registrado'), findsOneWidget);
    });

    testWidgets('renders live line-by-line inspection with all status types (match, duplicate conflict, missing, unrecognized)', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      // Clip 1: Single file on disk
      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001.MP4',
        proposedFileName: 'A001C001.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      // Clip 2: Duplicate files on disk
      final prop2a = RenameProposal(
        originalFilePath: '/media/A001C002.MP4',
        proposedFileName: 'A001C002.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );
      final prop2b = RenameProposal(
        originalFilePath: '/media/A001C002_ALT.MP4',
        proposedFileName: 'A001C002_ALT.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1, prop2a, prop2b]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      // Enter 4 distinct lines:
      // Line 1: Clip 001 -> match
      // Line 2: Clip 002 -> duplicate conflict on disk
      // Line 3: Clip 003 -> missing on disk
      // Line 4: Invalid -> unrecognized
      final textFields = find.byType(TextField);
      await tester.enterText(
        textFields.last,
        'PROD_01_01_T1_A001_D01_001_U1\n'
        'PROD_01_01_T1_A001_D01_002_U1\n'
        'PROD_01_01_T1_A001_D01_003_U1\n'
        'INVALID_CONVENTION_LINE_SAMPLE',
      );
      await tester.pump();

      // Check section header
      expect(find.text('Estado de Líneas en Vivo'), findsOneWidget);
      expect(find.text('4 líneas'), findsOneWidget);

      // Line 1: Match
      expect(find.text('Línea 1: A001C001.MP4'), findsOneWidget);

      // Line 2: Duplicate conflict on disk
      expect(find.text('Línea 2: Conflicto en disco (Clip #02 duplicado)'), findsOneWidget);

      // Line 3: Missing on disk
      expect(find.text('Línea 3: Sin archivo en disco (Clip #03)'), findsOneWidget);

      // Line 4: Unrecognized format
      expect(find.text('Línea 4: Formato de convención no reconocido'), findsOneWidget);

      // Tapping on Line 1 focuses/scrolls to that clip without error
      await tester.tap(find.text('Línea 1: A001C001.MP4'));
      await tester.pumpAndSettle();
    });

    testWidgets('highlights matched rows with green background tint and custom badge', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001.MP4',
        proposedFileName: 'A001C001.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );
      final prop2 = RenameProposal(
        originalFilePath: '/media/A001C002.MP4',
        proposedFileName: 'A001C002.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1, prop2]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      // Enter convention line for Clip 1 only
      final textFields = find.byType(TextField);
      await tester.enterText(
        textFields.last,
        'PROD_01_01_T1_A001_D01_001_U1',
      );
      await tester.pump();

      // Matched clip badge: ✓ Texto (Línea 1)
      expect(find.text('✓ Texto (Línea 1)'), findsOneWidget);
      // Unmatched clip badge remains
      expect(find.text('Clip no registrado'), findsOneWidget);

      // Checkmark icon prefix in Proposed Name cell
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      // Inspect DataRow colors
      final table = tester.widget<DataTable>(find.byType(DataTable));
      expect(table.rows.length, 2);

      final row1Color = table.rows[0].color?.resolve({});
      final row2Color = table.rows[1].color?.resolve({});

      expect(row1Color, Colors.green.withValues(alpha: 0.12));
      expect(row2Color, isNull);
    });

    testWidgets('toggling "Solo coincidentes" filter chip displays only the matched rows', (tester) async {
      setupDesktopWindow(tester);

      final project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      final prop1 = RenameProposal(
        originalFilePath: '/media/A001C001.MP4',
        proposedFileName: 'A001C001.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );
      final prop2 = RenameProposal(
        originalFilePath: '/media/A001C002.MP4',
        proposedFileName: 'A001C002.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );
      final prop3 = RenameProposal(
        originalFilePath: '/media/A001C003.MP4',
        proposedFileName: 'A001C003.MP4',
        fileReel: 'A001',
        status: ProposalStatus.unmatchedClip,
      );

      final report = DryRunReport(proposals: [prop1, prop2, prop3]);

      await tester.pumpWidget(createHomeScreen(project: project, report: report));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Renombrador de Medios'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Editor de Texto'));
      await tester.pumpAndSettle();

      // Enter convention line for Clip 1 only
      final textFields = find.byType(TextField);
      await tester.enterText(
        textFields.last,
        'PROD_01_01_T1_A001_D01_001_U1',
      );
      await tester.pump();

      // FilterChip "Solo coincidentes (1)" is visible
      final filterChip = find.widgetWithText(FilterChip, 'Solo coincidentes (1)');
      expect(filterChip, findsOneWidget);

      // Initially all 3 rows are rendered
      expect(find.text('A001C001.MP4'), findsOneWidget);
      expect(find.text('A001C002.MP4'), findsOneWidget);
      expect(find.text('A001C003.MP4'), findsOneWidget);

      // Tap filter chip to show only convention matches
      await tester.tap(filterChip);
      await tester.pumpAndSettle();

      // Now only A001C001.MP4 is displayed in the DataTable
      expect(find.text('A001C001.MP4'), findsOneWidget);
      expect(find.text('A001C002.MP4'), findsNothing);
      expect(find.text('A001C003.MP4'), findsNothing);

      // Tap filter chip again to deselect
      await tester.tap(filterChip);
      await tester.pumpAndSettle();

      // All 3 rows return to the DataTable
      expect(find.text('A001C001.MP4'), findsOneWidget);
      expect(find.text('A001C002.MP4'), findsOneWidget);
      expect(find.text('A001C003.MP4'), findsOneWidget);
    });
  });
}
