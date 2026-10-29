import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/dialogs/take_linker_dialog.dart';

void main() {
  void setupDesktopWindow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildTestDialog({
    required RenameProposal clip,
    required List<ShotRecord> records,
    required String activeCamera,
    ShotRecord? currentlyLinkedRecord,
    void Function(TakeLinkerResult?)? onClosed,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await TakeLinkerDialog.show(
                context,
                clip: clip,
                records: records,
                activeCamera: activeCamera,
                currentlyLinkedRecord: currentlyLinkedRecord,
              );
              onClosed?.call(result);
            },
            child: const Text('Open Modal'),
          ),
        ),
      ),
    );
  }

  final sampleClip = RenameProposal(
    originalFilePath: '/media/A001C001_260817AB.MP4',
    proposedFileName: 'A001C001_260817AB.MP4',
    fileReel: 'A001',
    fileTcIn: '10:00:00:00',
    fileTcOut: '10:01:30:00',
    status: ProposalStatus.ready,
  );

  final rec1 = ShotRecord(
    id: '1',
    scene: '12',
    take: '1',
    chapter: '101',
    plane: 'A',
    reel: 'A001',
    tcIn: '10:00:00:00',
    tcOut: '10:01:30:00',
    observations: 'Toma buena, plano general',
    cameras: [
      CameraTakeRecord(cameraName: 'A', clipName: 'A001C001'),
    ],
  );

  final rec2 = ShotRecord(
    id: '2',
    scene: '12',
    take: '2',
    chapter: '101',
    plane: 'A',
    reel: 'A001',
    tcIn: '11:15:00:00',
    tcOut: '11:16:00:00',
    observations: 'Falsa salida',
    cameras: [
      CameraTakeRecord(cameraName: 'A', clipName: 'A001C002'),
    ],
  );

  final rec3 = ShotRecord(
    id: '3',
    scene: '14B',
    take: '1',
    chapter: '102',
    reel: 'A002',
    tcIn: '12:00:00:00',
    tcOut: '12:02:00:00',
    observations: 'Primer plano actor',
    cameras: [],
  );

  group('TakeLinkerDialog Widget Tests', () {
    testWidgets('renders dialog header with clip info and timecode', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(
        buildTestDialog(
          clip: sampleClip,
          records: [rec1, rec2],
          activeCamera: 'A',
        ),
      );
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Vincular Toma a Clip'), findsOneWidget);
      expect(
        find.textContaining('A001C001_260817AB.MP4'),
        findsOneWidget,
      );
      expect(find.textContaining('10:00:00:00 ➔ 10:01:30:00'), findsOneWidget);
      expect(find.byKey(const ValueKey('take_linker_search_field')), findsOneWidget);
    });

    testWidgets('displays timecode suggestions banner when a record matches clip timecode', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(
        buildTestDialog(
          clip: sampleClip,
          records: [rec1, rec2],
          activeCamera: 'A',
        ),
      );
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Sugerencias por Código de Tiempo'), findsOneWidget);
      // rec1 matches timecode
      expect(find.byKey(const ValueKey('take_item_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('take_item_2')), findsOneWidget);
    });

    testWidgets('filters records using search field by scene, take, or notes', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(
        buildTestDialog(
          clip: sampleClip,
          records: [rec1, rec2, rec3],
          activeCamera: 'A',
        ),
      );
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('take_item_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('take_item_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('take_item_3')), findsOneWidget);

      // Search for '14B'
      await tester.enterText(
        find.byKey(const ValueKey('take_linker_search_field')),
        '14B',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('take_item_1')), findsNothing);
      expect(find.byKey(const ValueKey('take_item_2')), findsNothing);
      expect(find.byKey(const ValueKey('take_item_3')), findsOneWidget);

      // Search for notes 'Falsa salida'
      await tester.enterText(
        find.byKey(const ValueKey('take_linker_search_field')),
        'Falsa',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('take_item_1')), findsNothing);
      expect(find.byKey(const ValueKey('take_item_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('take_item_3')), findsNothing);
    });

    testWidgets('selecting a take and tapping "Vincular" pops TakeLinkerResult.link', (tester) async {
      setupDesktopWindow(tester);

      TakeLinkerResult? result;
      await tester.pumpWidget(
        buildTestDialog(
          clip: sampleClip,
          records: [rec1, rec2],
          activeCamera: 'A',
          onClosed: (res) => result = res,
        ),
      );
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Before selecting, confirm button should be disabled
      final confirmBtn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('take_linker_confirm_button')),
      );
      expect(confirmBtn.onPressed, isNull);

      // Tap rec2 and advance past double-tap timeout
      await tester.tap(find.byKey(const ValueKey('take_item_2')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Now confirm button should be enabled
      final enabledConfirmBtn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('take_linker_confirm_button')),
      );
      expect(enabledConfirmBtn.onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('take_linker_confirm_button')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.action, equals(TakeLinkerAction.link));
      expect(result!.record?.id, equals('2'));
      expect(find.byType(TakeLinkerDialog), findsNothing);
    });

    testWidgets('double-tapping a take directly links it', (tester) async {
      setupDesktopWindow(tester);

      TakeLinkerResult? result;
      await tester.pumpWidget(
        buildTestDialog(
          clip: sampleClip,
          records: [rec1, rec2],
          activeCamera: 'A',
          onClosed: (res) => result = res,
        ),
      );
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Double-tap rec1
      await tester.tap(find.byKey(const ValueKey('take_item_1')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('take_item_1')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.action, equals(TakeLinkerAction.link));
      expect(result!.record?.id, equals('1'));
      expect(find.byType(TakeLinkerDialog), findsNothing);
    });

    testWidgets('shows "Desvincular Toma" when currentlyLinkedRecord is provided and pops unlink', (tester) async {
      setupDesktopWindow(tester);

      TakeLinkerResult? result;
      await tester.pumpWidget(
        buildTestDialog(
          clip: sampleClip,
          records: [rec1, rec2],
          activeCamera: 'A',
          currentlyLinkedRecord: rec1,
          onClosed: (res) => result = res,
        ),
      );
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // 'Desvincular Toma' button should be visible
      final unlinkFinder = find.byKey(const ValueKey('take_linker_unlink_button'));
      expect(unlinkFinder, findsOneWidget);

      await tester.tap(unlinkFinder);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.action, equals(TakeLinkerAction.unlink));
      expect(result!.record, isNull);
      expect(find.byType(TakeLinkerDialog), findsNothing);
    });

    testWidgets('tapping "Cancelar" pops null', (tester) async {
      setupDesktopWindow(tester);

      TakeLinkerResult? result = const TakeLinkerResult.unlink(); // sentinel
      await tester.pumpWidget(
        buildTestDialog(
          clip: sampleClip,
          records: [rec1, rec2],
          activeCamera: 'A',
          onClosed: (res) => result = res,
        ),
      );
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('take_linker_cancel_button')));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.byType(TakeLinkerDialog), findsNothing);
    });
  });
}
