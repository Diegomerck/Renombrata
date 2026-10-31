import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/bitacora_editor_tab.dart';

void main() {
  void setupDesktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('BitacoraEditorTab Timecode Input & Focus Stability Tests', () {
    testWidgets('TC In typing maintains focus on keystrokes and autocompletes :00 frames on unfocus', (tester) async {
      setupDesktop(tester);

      final record = ShotRecord(
        id: 'rec-test-1',
        chapter: '1',
        scene: '10',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
        reel: 'A001',
        tcIn: '',
        tcOut: '',
      );

      RenombrataProject currentProject = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(frameRate: '24'),
          records: [record],
        ),
        defaultReel: 'A001',
        activeCamera: 'A',
        showTcOut: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return BitacoraEditorTab(
                  project: currentProject,
                  onProjectChanged: (newProj) {
                    setState(() {
                      currentProject = newProj;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tcInFinder = find.byKey(ValueKey('${record.id}_tcIn'));
      expect(tcInFinder, findsOneWidget);

      // Tap TC In field to focus
      await tester.tap(tcInFinder);
      await tester.pumpAndSettle();

      expect(Focus.of(tester.element(tcInFinder)).hasFocus, isTrue);

      // Type '100033' sequentially and ensure focus is NOT lost after any keystroke
      String buffer = '';
      for (final char in '100033'.split('')) {
        buffer += char;
        await tester.enterText(tcInFinder, buffer);
        await tester.pump();
        expect(
          Focus.of(tester.element(tcInFinder)).hasFocus,
          isTrue,
          reason: 'Focus was lost after typing $buffer',
        );
      }

      // Unfocus by tapping outside
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // Verify that ':00' frames was appended and formatted
      expect(currentProject.log.records.first.tcIn, equals('10:00:33:00'));
      expect(
        find.descendant(of: tcInFinder, matching: find.text('10:00:33:00')),
        findsOneWidget,
      );
    });

    testWidgets('TC In normalizes and appends :00 frames on pressing Enter / submit', (tester) async {
      setupDesktop(tester);

      final record = ShotRecord(
        id: 'rec-test-2',
        chapter: '1',
        scene: '10',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
        reel: 'A001',
        tcIn: '',
        tcOut: '',
      );

      RenombrataProject currentProject = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(frameRate: '24'),
          records: [record],
        ),
        defaultReel: 'A001',
        activeCamera: 'A',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return BitacoraEditorTab(
                  project: currentProject,
                  onProjectChanged: (newProj) {
                    setState(() {
                      currentProject = newProj;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tcInFinder = find.byKey(ValueKey('${record.id}_tcIn'));

      // Tap and enter 4 digits '1000'
      await tester.tap(tcInFinder);
      await tester.pumpAndSettle();
      await tester.enterText(tcInFinder, '1000');
      await tester.pump();

      // Submit via Done/Enter action
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Verify normalized to 10:00:00:00
      expect(currentProject.log.records.first.tcIn, equals('10:00:00:00'));
      expect(
        find.descendant(of: tcInFinder, matching: find.text('10:00:00:00')),
        findsOneWidget,
      );
    });

    testWidgets('TC Out maintains focus and autocompletes :00 frames on unfocus', (tester) async {
      setupDesktop(tester);

      final record = ShotRecord(
        id: 'rec-test-3',
        chapter: '1',
        scene: '10',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
        reel: 'A001',
        tcIn: '10:00:00:00',
        tcOut: '',
      );

      RenombrataProject currentProject = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(frameRate: '24'),
          records: [record],
        ),
        defaultReel: 'A001',
        activeCamera: 'A',
        showTcOut: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return BitacoraEditorTab(
                  project: currentProject,
                  onProjectChanged: (newProj) {
                    setState(() {
                      currentProject = newProj;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tcOutFinder = find.byKey(ValueKey('${record.id}_tcOut'));
      expect(tcOutFinder, findsOneWidget);

      await tester.tap(tcOutFinder);
      await tester.pumpAndSettle();

      expect(Focus.of(tester.element(tcOutFinder)).hasFocus, isTrue);

      // Type '100033' into TC Out
      String buffer = '';
      for (final char in '100033'.split('')) {
        buffer += char;
        await tester.enterText(tcOutFinder, buffer);
        await tester.pump();
        expect(
          Focus.of(tester.element(tcOutFinder)).hasFocus,
          isTrue,
          reason: 'Focus was lost after typing $buffer in TC Out',
        );
      }

      // Unfocus
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(currentProject.log.records.first.tcOut, equals('10:00:33:00'));
      expect(
        find.descendant(of: tcOutFinder, matching: find.text('10:00:33:00')),
        findsOneWidget,
      );
    });
  });
}
