import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/ui/quick_paste_convention_dialog.dart';

void main() {
  Widget buildTestDialog({
    List<String>? loadedClips,
    List<RenameProposal>? loadedProposals,
    void Function(Map<String, String>?)? onClosed,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showDialog<Map<String, String>>(
                context: context,
                builder: (ctx) => QuickPasteConventionDialog(
                  loadedClipNames: loadedClips,
                  loadedProposals: loadedProposals,
                ),
              );
              onClosed?.call(result);
            },
            child: const Text('Open Modal'),
          ),
        ),
      ),
    );
  }

  void setupDesktopWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('QuickPasteConventionDialog Tests', () {
    testWidgets('renders dialog title, input field, and action buttons',
        (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(
          buildTestDialog(loadedClips: ['A001C001.MP4', 'A001C002.MP4']));
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Pegar Nombres de Convención'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Aplicar a Renombrador'), findsOneWidget);
      expect(find.text('Líneas detectadas: 0 | Clips cargados: 2'),
          findsOneWidget);
    });

    testWidgets('displays exact match badge when line count equals clip count',
        (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(
          buildTestDialog(loadedClips: ['A001C001.MP4', 'A001C002.MP4']));
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      final input = find.byType(TextField);
      await tester.enterText(input, 'NAME_1\nNAME_2');
      await tester.pump();

      expect(find.text('Líneas detectadas: 2 | Clips cargados: 2'),
          findsOneWidget);
      expect(find.text('Coincidencia exacta'), findsOneWidget);
      expect(find.text('NAME_1'), findsOneWidget);
      expect(find.text('NAME_2'), findsOneWidget);
    });

    testWidgets('displays line difference warning badge when counts differ',
        (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(
          buildTestDialog(loadedClips: ['A001C001.MP4', 'A001C002.MP4']));
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      final input = find.byType(TextField);
      // Only 1 line pasted for 2 clips -> diff = -1
      await tester.enterText(input, 'NAME_1');
      await tester.pump();

      expect(find.text('Líneas detectadas: 1 | Clips cargados: 2'),
          findsOneWidget);
      expect(find.text('Diferencia de líneas (-1)'), findsOneWidget);

      // Now 3 lines for 2 clips -> diff = +1
      await tester.enterText(input, 'NAME_1\nNAME_2\nNAME_3');
      await tester.pump();

      expect(find.text('Líneas detectadas: 3 | Clips cargados: 2'),
          findsOneWidget);
      expect(find.text('Diferencia de líneas (+1)'), findsOneWidget);
    });

    testWidgets('cancels dialog and returns null when Cancelar is tapped',
        (tester) async {
      setupDesktopWindow(tester);

      Map<String, String>? returnedResult = {'initial': 'val'};
      await tester.pumpWidget(buildTestDialog(
        loadedClips: ['A001C001.MP4'],
        onClosed: (res) => returnedResult = res,
      ));

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(returnedResult, isNull);
    });

    testWidgets('applies convention names with sequential fallback and returns mapping',
        (tester) async {
      setupDesktopWindow(tester);

      Map<String, String>? returnedResult;
      await tester.pumpWidget(buildTestDialog(
        loadedClips: ['A001C001.MP4', 'A001C002.MP4'],
        onClosed: (res) => returnedResult = res,
      ));

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Enter text with leading/trailing whitespaces and empty line
      await tester.enterText(
          find.byType(TextField), '  PROD_01_01_T1  \n\n  PROD_01_02_T1  ');
      await tester.pump();

      await tester.tap(find.text('Aplicar a Renombrador'));
      await tester.pumpAndSettle();

      expect(
        returnedResult,
        equals({
          'A001C001.MP4': 'PROD_01_01_T1',
          'A001C002.MP4': 'PROD_01_02_T1',
        }),
      );
    });

    testWidgets('intelligently matches clips by clip index even when clips are missing/skipped',
        (tester) async {
      setupDesktopWindow(tester);

      Map<String, String>? returnedResult;
      await tester.pumpWidget(buildTestDialog(
        loadedClips: ['A007C001.MP4', 'A007C002.MP4', 'A007C004.MP4'],
        onClosed: (res) => returnedResult = res,
      ));

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Paste lines for Clip 1 and Clip 4 (Clip 2 missing, Clip 3 skipped)
      const pasted = 'TODTA_2_13_P1_T1_A007_D01_01_U1\nTODTA_2_13_P1_T1_A007_D01_04_U1';
      await tester.enterText(find.byType(TextField), pasted);
      await tester.pump();

      // Verify Clip 1 row has "Coincide" and matches Line 1
      expect(find.text('TODTA_2_13_P1_T1_A007_D01_01_U1'), findsOneWidget);
      // Verify Clip 2 row has "Sin texto"
      expect(find.text('— Sin coincidencia en texto —'), findsOneWidget);
      // Verify Clip 4 row has "Coincide" and matches Line 2
      expect(find.text('TODTA_2_13_P1_T1_A007_D01_04_U1'), findsOneWidget);

      expect(find.text('Coincide'), findsNWidgets(2));
      expect(find.text('Sin texto'), findsOneWidget);

      // Apply to renamer
      await tester.tap(find.text('Aplicar a Renombrador'));
      await tester.pumpAndSettle();

      expect(
        returnedResult,
        equals({
          'A007C001.MP4': 'TODTA_2_13_P1_T1_A007_D01_01_U1',
          'A007C004.MP4': 'TODTA_2_13_P1_T1_A007_D01_04_U1',
        }),
      );
    });

    testWidgets('detects duplicate clip index in pasted text, blocks apply button, and shows conflict error',
        (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(buildTestDialog(
        loadedClips: ['A007C001.MP4', 'A007C002.MP4'],
      ));

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Paste 3 lines where Clip 2 is duplicated in line 2 and line 3
      const pasted =
          'PROD_01_01_T1_A007_01_D01_U1\nPROD_01_02_T1_A007_02_D01_U1\nPROD_01_03_T1_A007_02_D01_U1';
      await tester.enterText(find.byType(TextField), pasted);
      await tester.pump();

      // Red status banner should display duplicate clip conflict
      expect(
        find.textContaining('Conflicto: Clip #02 duplicado en las líneas 2, 3'),
        findsOneWidget,
      );

      // Table should flag Conflicto
      expect(find.text('Conflicto'), findsWidgets);

      // "Aplicar a Renombrador" button should be disabled
      final applyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Aplicar a Renombrador'),
      );
      expect(applyButton.onPressed, isNull);
    });

    testWidgets('flags conflict when duplicate files exist on disk for the same clip and blocks apply',
        (tester) async {
      setupDesktopWindow(tester);

      // A007C001.MP4 and A007C001_ALT.MP4 both map to Reel A007, Clip 1
      await tester.pumpWidget(buildTestDialog(
        loadedClips: ['A007C001.MP4', 'A007C001_ALT.MP4', 'A007C002.MP4'],
      ));

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'PROD_01_01_T1_A007_01_D01_U1');
      await tester.pump();

      // Conflicto banner for disk duplicate
      expect(
        find.textContaining('Conflicto en disco: Múltiples archivos para Reel A007 - Clip #01'),
        findsOneWidget,
      );

      // Both duplicate disk rows should show Conflicto
      expect(find.text('Conflicto'), findsWidgets);

      // Apply button should be disabled
      final applyButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Aplicar a Renombrador'),
      );
      expect(applyButton.onPressed, isNull);
    });

    testWidgets('matches alternate file correctly when it is the unique clip for that clip index',
        (tester) async {
      setupDesktopWindow(tester);

      Map<String, String>? returnedResult;
      await tester.pumpWidget(buildTestDialog(
        loadedClips: ['A007C001_ALT.MP4'],
        onClosed: (res) => returnedResult = res,
      ));

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'PROD_01_01_T1_A007_01_D01_U1');
      await tester.pump();

      // Should detect Reel A007 - Clip #01 and show Coincide
      expect(find.text('Reel A007 - Clip #01'), findsOneWidget);
      expect(find.text('Coincide'), findsOneWidget);

      await tester.tap(find.text('Aplicar a Renombrador'));
      await tester.pumpAndSettle();

      expect(
        returnedResult,
        equals({'A007C001_ALT.MP4': 'PROD_01_01_T1_A007_01_D01_U1'}),
      );
    });

    testWidgets('displays unassigned entries section when pasted lines have no matching file on disk',
        (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(buildTestDialog(
        loadedClips: ['A007C001.MP4'],
      ));

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Paste line for Clip 1 (matches) and Line for Clip 4 (no file on disk)
      await tester.enterText(
        find.byType(TextField),
        'PROD_01_01_T1_A007_01_D01_U1\nPROD_01_04_T1_A007_04_D01_U1',
      );
      await tester.pump();

      expect(find.textContaining('Entradas no asignadas (1)'), findsOneWidget);
      expect(
        find.textContaining('Línea 2 (Clip 04) no tiene archivo correspondiente en disco'),
        findsOneWidget,
      );
    });
  });
}
