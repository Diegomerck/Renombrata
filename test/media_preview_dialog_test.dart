import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/media_preview_dialog.dart';

void main() {
  group('MediaPreviewDialog Quick-Tagger & Playlist Tests', () {
    final testMetadata = ShootingLogMetadata(
      nomenclature: 'PROJ',
      date: '261019',
      unit: 'U1',
      day: 'D1',
      producer: '',
      production: '',
      location: '',
      audioFormat: '',
      frameRate: '23.98',
      videoCodec: '',
      responsibleEngineer: '',
      ingestor: '',
    );

    final proposal1 = RenameProposal(
      originalFilePath: '/path/to/A001C001_260608ZY.MP4',
      proposedFileName: 'PROJ_261019_10_A_T1_A001_D1_U1.MP4',
      fileTcIn: '09:04:22:00',
      fileTcOut: '09:07:29:23',
      fileReel: 'A001',
      status: ProposalStatus.ready,
      associatedRecord: ShotRecord(
        chapter: '3',
        scene: '10',
        plane: 'A',
        take: '1',
        cameras: [CameraTakeRecord(cameraName: 'A', clipName: '001')],
        reel: 'A001',
        isMos: false,
        observations: 'Initial take notes',
      ),
    );

    final proposal2 = RenameProposal(
      originalFilePath: '/path/to/A001C002_260608ZY.MP4',
      proposedFileName: 'A001C002_260608ZY.MP4',
      fileTcIn: '09:10:00:00',
      fileTcOut: '09:12:00:00',
      fileReel: 'A001',
      status: ProposalStatus.unmatchedClip,
      associatedRecord: null,
    );

    testWidgets('renders dialog UI structure with playlist, live convention preview, and tagger form', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      // Top bar items
      expect(find.text('Clip 1 de 2'), findsOneWidget);
      expect(find.text('A001C001_260608ZY.MP4'), findsOneWidget);
      expect(find.text('TC: 09:04:22:00 → 09:07:29:23'), findsWidgets);
      expect(find.byIcon(Icons.close), findsOneWidget);

      // Tagger panel items
      expect(find.text('CONVENCIÓN EN TIEMPO REAL'), findsOneWidget);
      expect(find.text('PROJ_261019_10_A_T1_A001_D1_U1.MP4'), findsWidgets);
      expect(find.text('Cap'), findsOneWidget);
      expect(find.text('Escena'), findsOneWidget);
      expect(find.text('Plano'), findsOneWidget);
      expect(find.text('Toma'), findsOneWidget);
      expect(find.text('MOS (Mudo)'), findsOneWidget);
      expect(find.text('Notas'), findsOneWidget);

      // Read populated fields from proposal 1
      expect(find.widgetWithText(TextField, '3'), findsOneWidget);
      expect(find.widgetWithText(TextField, '10'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'A'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Initial take notes'), findsOneWidget);

      // Close dialog
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(MediaPreviewDialog), findsNothing);
    });

    testWidgets('responds to Next/Previous navigation and auto-increments take for unassociated clip', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      expect(find.text('Clip 1 de 2'), findsOneWidget);

      // Navigate to Next clip
      await tester.tap(find.widgetWithText(OutlinedButton, 'Siguiente'));
      await tester.pumpAndSettle();

      // Now at Clip 2 de 2
      expect(find.text('Clip 2 de 2'), findsOneWidget);
      expect(find.text('A001C002_260608ZY.MP4'), findsOneWidget);

      // Cap, scene and plane retained from previous ('3', '10', 'A'), take auto-incremented ('1' -> '2')
      expect(find.widgetWithText(TextField, '3'), findsOneWidget);
      expect(find.widgetWithText(TextField, '10'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'A'), findsOneWidget);
      expect(find.widgetWithText(TextField, '2'), findsOneWidget);

      // Live convention name updated with take 2
      expect(find.text('PROJ_261019_10_A_T2_A001_D1_U1.MP4'), findsWidgets);

      // Navigate back to Previous clip
      await tester.tap(find.widgetWithText(OutlinedButton, 'Anterior'));
      await tester.pumpAndSettle();

      expect(find.text('Clip 1 de 2'), findsOneWidget);
      expect(find.widgetWithText(TextField, '3'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1'), findsOneWidget);
    });

    testWidgets('navigating from clip 0 to clip 1 and back to clip 0 preserves cached state without incrementing', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      // Modify take on clip 0 to '5'
      final takeFinder = find.widgetWithText(TextField, '1');
      await tester.enterText(takeFinder, '5');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '5'), findsOneWidget);

      // Navigate to clip 1 (unvisited, unassociated) -> should auto-increment to '6'
      await tester.tap(find.widgetWithText(OutlinedButton, 'Siguiente'));
      await tester.pumpAndSettle();

      expect(find.text('Clip 2 de 2'), findsOneWidget);
      expect(find.widgetWithText(TextField, '3'), findsOneWidget);
      expect(find.widgetWithText(TextField, '6'), findsOneWidget);

      // Navigate back to clip 0 -> must restore cached '5', NOT increment to '7'
      await tester.tap(find.widgetWithText(OutlinedButton, 'Anterior'));
      await tester.pumpAndSettle();

      expect(find.text('Clip 1 de 2'), findsOneWidget);
      expect(find.widgetWithText(TextField, '3'), findsOneWidget);
      expect(find.widgetWithText(TextField, '5'), findsOneWidget);
      expect(find.text('PROJ_261019_10_A_T5_A001_D1_U1.MP4'), findsWidgets);
    });

    testWidgets('stepper +1 and -1 adjusts take number', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '1'), findsOneWidget);

      // Tap +1 stepper
      await tester.tap(find.byTooltip('Toma +1'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '2'), findsOneWidget);

      // Tap -1 stepper
      await tester.tap(find.byTooltip('Toma -1'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '1'), findsOneWidget);
    });

    testWidgets('triggers onSaveTake callback when Guardar y Siguiente is clicked', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      RenameProposal? savedProposal;
      String? savedChapter;
      String? savedScene;
      String? savedTake;
      bool? savedMos;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {
                          savedProposal = prop;
                          savedChapter = chapter;
                          savedScene = scene;
                          savedTake = take;
                          savedMos = isMos;
                        },
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      // Click Guardar y Siguiente
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(savedProposal, equals(proposal1));
      expect(savedChapter, '3');
      expect(savedScene, '10');
      expect(savedTake, '1');
      expect(savedMos, isFalse);

      // Should automatically advance to clip 2
      expect(find.text('Clip 2 de 2'), findsOneWidget);
    });

    testWidgets('submitting via onSubmitted in TextField triggers onSaveTake', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      RenameProposal? savedProposal;
      String? savedTake;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {
                          savedProposal = prop;
                          savedTake = take;
                        },
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      // Submit via TextField onSubmitted (e.g. on Toma input)
      final takeFinder = find.widgetWithText(TextField, '1');
      await tester.showKeyboard(takeFinder);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(savedProposal, equals(proposal1));
      expect(savedTake, '1');
      expect(find.text('Clip 2 de 2'), findsOneWidget);
    });

    testWidgets('PageDown and PageUp keys navigate clips even when TextField is focused', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      // Focus Escena text field
      final sceneFinder = find.widgetWithText(TextField, '10');
      await tester.tap(sceneFinder);
      await tester.pumpAndSettle();

      // Press PageDown
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();

      // Must have navigated to clip 2
      expect(find.text('Clip 2 de 2'), findsOneWidget);

      // Press PageUp
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();

      // Must have navigated back to clip 1
      expect(find.text('Clip 1 de 2'), findsOneWidget);
    });

    testWidgets('zoom HUD renders with default 100% badge and zoom buttons', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      // Zoom HUD elements
      expect(find.text('100%'), findsOneWidget);
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
      expect(find.byIcon(Icons.zoom_out), findsOneWidget);
      // Reset button not visible at 100%
      expect(find.byIcon(Icons.restart_alt), findsNothing);
    });

    testWidgets('tapping zoom in button increases percentage above 100% and displays reset button', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      expect(find.text('100%'), findsOneWidget);
      expect(find.byIcon(Icons.restart_alt), findsNothing);

      // Tap zoom in
      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pumpAndSettle();

      // Scale should be 130% (1.3x) and reset button should appear
      expect(find.text('130%'), findsOneWidget);
      expect(find.byIcon(Icons.restart_alt), findsOneWidget);
    });

    testWidgets('tapping reset button restores zoom back to 100% and identity matrix', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      // Zoom in
      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pumpAndSettle();
      expect(find.text('130%'), findsOneWidget);
      expect(find.byIcon(Icons.restart_alt), findsOneWidget);

      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), greaterThan(1.0));

      // Tap reset button
      await tester.tap(find.byIcon(Icons.restart_alt));
      await tester.pumpAndSettle();

      expect(find.text('100%'), findsOneWidget);
      expect(find.byIcon(Icons.restart_alt), findsNothing);
      expect(viewer.transformationController!.value, equals(Matrix4.identity()));
    });

    testWidgets('scrolling over specific offset applies translation and scales cleanly', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      // Find center of video area
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final scrollOffset = Offset(center.dx + 50, center.dy + 50);

      // Send scroll signal (scroll up -> zoom in)
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(scrollOffset));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -100)));
      await tester.pumpAndSettle();

      // Reset button should appear indicating zoom is active
      expect(find.byIcon(Icons.restart_alt), findsOneWidget);

      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final matrix = viewer.transformationController!.value;
      expect(matrix.getMaxScaleOnAxis(), greaterThan(1.0));
      // Focal point scrolling should apply non-zero translation
      expect(matrix.getTranslation().x, isNot(0.0));
      expect(matrix.getTranslation().y, isNot(0.0));

      // Reset zoom
      await tester.tap(find.byIcon(Icons.restart_alt));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);
      expect(viewer.transformationController!.value, equals(Matrix4.identity()));
    });

    testWidgets('advancing to next clip resets any active zoom back to 100%', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      // Zoom in on clip 1
      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pumpAndSettle();
      expect(find.text('130%'), findsOneWidget);
      expect(find.byIcon(Icons.restart_alt), findsOneWidget);

      // Advance to next clip
      await tester.tap(find.widgetWithText(OutlinedButton, 'Siguiente'));
      await tester.pumpAndSettle();

      // Must be at clip 2 and zoom must be reset to 100%
      expect(find.text('Clip 2 de 2'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.byIcon(Icons.restart_alt), findsNothing);
    });

    testWidgets('Ctrl + keyboard zoom anchors to hovered pointer position', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1, proposal2],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      final center = tester.getCenter(find.byType(InteractiveViewer));
      final hoverPosition = Offset(center.dx + 80, center.dy + 60);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(hoverPosition));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final matrix = viewer.transformationController!.value;
      expect(matrix.getMaxScaleOnAxis(), closeTo(1.3, 0.05));
      expect(matrix.getTranslation().x, isNot(0.0));
      expect(matrix.getTranslation().y, isNot(0.0));
    });

    testWidgets('displays auto-ordenar bitácora switch and invokes callback on change', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool? updatedAutoSort;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => MediaPreviewDialog(
                        playlist: [proposal1],
                        initialIndex: 0,
                        projectMetadata: testMetadata,
                        activeCamera: 'A',
                        autoSortByClip: true,
                        onAutoSortChanged: (val) => updatedAutoSort = val,
                        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {},
                      ),
                    );
                  },
                  child: const Text('Open Preview'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Preview'));
      await tester.pumpAndSettle();

      final switchFinder = find.widgetWithText(SwitchListTile, 'Auto-ordenar bitácora por clip');
      expect(switchFinder, findsOneWidget);
      final switchWidget = tester.widget<SwitchListTile>(switchFinder);
      expect(switchWidget.value, isTrue);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(updatedAutoSort, isFalse);
    });
  });
}
