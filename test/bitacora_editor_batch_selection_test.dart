import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/bitacora_editor_tab.dart';

void main() {
  testWidgets('BitacoraEditorTab batch selection, deletion, and undo', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    RenombrataProject currentProject = RenombrataProject(
      log: ShootingLog(
        metadata: ShootingLogMetadata.empty(),
        records: [
          ShotRecord(id: 'rec_1', chapter: '1', scene: '10', plane: '1', take: '1', cameras: [], reel: 'A001'),
          ShotRecord(id: 'rec_2', chapter: '1', scene: '10', plane: '1', take: '2', cameras: [], reel: 'A001'),
          ShotRecord(id: 'rec_3', chapter: '1', scene: '10', plane: '2', take: '1', cameras: [], reel: 'A001'),
        ],
      ),
      defaultReel: 'A001',
      activeCamera: 'A',
      cameraNames: ['A'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return BitacoraEditorTab(
                project: currentProject,
                onProjectChanged: (updated) {
                  setState(() {
                    currentProject = updated;
                  });
                },
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify 3 takes are listed
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('3 tomas registradas'), findsOneWidget);

    // Header batch trash icon exists
    final headerTrashFinder = find.byTooltip('Eliminar tomas seleccionadas');
    expect(headerTrashFinder, findsOneWidget);

    // Find checkboxes
    final masterCheckboxFinder = find.byKey(const ValueKey('master_select_all_checkbox'));
    expect(masterCheckboxFinder, findsOneWidget);
    expect(tester.widget<Checkbox>(masterCheckboxFinder).value, false);

    final rowCheckbox1 = find.byKey(const ValueKey('row_checkbox_rec_1'));
    final rowCheckbox2 = find.byKey(const ValueKey('row_checkbox_rec_2'));
    final rowCheckbox3 = find.byKey(const ValueKey('row_checkbox_rec_3'));
    expect(rowCheckbox1, findsOneWidget);
    expect(rowCheckbox2, findsOneWidget);
    expect(rowCheckbox3, findsOneWidget);

    // Test master "Select All": clicking it selects all 3 takes
    await tester.tap(masterCheckboxFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(masterCheckboxFinder).value, true);
    expect(tester.widget<Checkbox>(rowCheckbox1).value, true);
    expect(tester.widget<Checkbox>(rowCheckbox2).value, true);
    expect(tester.widget<Checkbox>(rowCheckbox3).value, true);

    // Clicking master checkbox again unselects all
    await tester.tap(masterCheckboxFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(masterCheckboxFinder).value, false);
    expect(tester.widget<Checkbox>(rowCheckbox1).value, false);
    expect(tester.widget<Checkbox>(rowCheckbox2).value, false);
    expect(tester.widget<Checkbox>(rowCheckbox3).value, false);

    // Select row 1 and 2 individually
    await tester.tap(rowCheckbox1);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(masterCheckboxFinder).value, isNull); // partial selection -> indeterminate

    await tester.tap(rowCheckbox2);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(masterCheckboxFinder).value, isNull);

    // Tap header batch trash icon
    await tester.tap(headerTrashFinder);
    await tester.pumpAndSettle();

    // Verify dialog appears
    expect(find.text('¿Eliminar tomas seleccionadas?'), findsOneWidget);
    expect(find.textContaining('¿Eliminar 2 tomas seleccionadas?'), findsOneWidget);

    // Confirm deletion
    await tester.tap(find.widgetWithText(ElevatedButton, 'Eliminar'));
    await tester.pumpAndSettle();

    // Now only 1 take should remain (#1 for the third record)
    expect(currentProject.log.records.length, 1);
    expect(currentProject.log.records.first.id, 'rec_3');
    expect(find.text('1 tomas registradas'), findsOneWidget);

    // Test undo
    final undoButton = find.widgetWithText(ElevatedButton, 'Deshacer eliminación');
    expect(undoButton, findsOneWidget);
    await tester.tap(undoButton);
    await tester.pumpAndSettle();

    // Verify both deleted takes are restored in order
    expect(currentProject.log.records.length, 3);
    expect(currentProject.log.records[0].id, 'rec_1');
    expect(currentProject.log.records[1].id, 'rec_2');
    expect(currentProject.log.records[2].id, 'rec_3');
    expect(find.text('3 tomas registradas'), findsOneWidget);
    // Test single deletion via row trash icon
    final singleTrashFinder = find.byTooltip('Eliminar toma');
    expect(singleTrashFinder, findsWidgets);
    await tester.tap(singleTrashFinder.at(0));
    await tester.pumpAndSettle();

    expect(find.text('¿Eliminar toma?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect(currentProject.log.records.length, 2);
    expect(currentProject.log.records[0].id, 'rec_2');

    // Undo single deletion
    await tester.tap(undoButton);
    await tester.pumpAndSettle();

    expect(currentProject.log.records.length, 3);
    expect(currentProject.log.records[0].id, 'rec_1');
  });

  testWidgets('Light theme input decoration and contrast check', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    RenombrataProject project = RenombrataProject(
      log: ShootingLog(
        metadata: ShootingLogMetadata.empty(),
        records: [
          ShotRecord(id: 'rec_1', chapter: '1', scene: '10', plane: '1', take: '1', cameras: [], reel: 'A001'),
        ],
      ),
      defaultReel: 'A001',
      activeCamera: 'A',
      cameraNames: ['A'],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
          scaffoldBackgroundColor: const Color(0xFFE9EDF4),
          cardColor: const Color(0xFFF7F8FA),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFBCC4D2)),
            ),
          ),
          useMaterial3: true,
        ),
        home: Scaffold(
          body: BitacoraEditorTab(
            project: project,
            onProjectChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify TextField in grid cell has white fillColor
    final textFields = tester.widgetList<TextField>(find.byType(TextField));
    expect(textFields.isNotEmpty, isTrue);
    final gridCellField = textFields.firstWhere((t) => t.decoration?.hintText == 'Escena');
    expect(gridCellField.decoration?.filled, isTrue);
    expect(gridCellField.decoration?.fillColor, Colors.white);
  });
}
