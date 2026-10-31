import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';

void main() {
  testWidgets('HomeScreen contains DropTarget and displays overlay on drag enter', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify DropTarget is present in tree
    final dropTargetFinder = find.byType(DropTarget);
    expect(dropTargetFinder, findsOneWidget);

    // Initial state: overlay is not visible
    expect(find.text('Suelta tus archivos aquí'), findsNothing);

    // Trigger drag entered
    final dropTarget = tester.widget<DropTarget>(dropTargetFinder);
    dropTarget.onDragEntered?.call(DropEventDetails(
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    ));
    await tester.pump();

    // Verify overlay appears with expected texts and badges
    expect(find.text('Suelta tus archivos aquí'), findsOneWidget);
    expect(find.textContaining('Suelta aquí carpetas de medios'), findsOneWidget);
    expect(find.text('Carpeta de Medios'), findsOneWidget);
    expect(find.text('Bitácora (.xlsx, .rtf, .txt, .pages)'), findsOneWidget);
    expect(find.text('Proyecto (.renombrata)'), findsOneWidget);

    // Trigger drag exited
    dropTarget.onDragExited?.call(DropEventDetails(
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    ));
    await tester.pump();

    // Overlay disappears
    expect(find.text('Suelta tus archivos aquí'), findsNothing);
  });

  testWidgets('DropTarget handles unsupported file with notification banner', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final dropTargetFinder = find.byType(DropTarget);
    final dropTarget = tester.widget<DropTarget>(dropTargetFinder);

    final tempFile = File('${Directory.systemTemp.path}/test_unknown.pdf');
    if (!tempFile.existsSync()) {
      tempFile.writeAsStringSync('dummy content');
    }
    addTearDown(() {
      if (tempFile.existsSync()) tempFile.deleteSync();
    });

    dropTarget.onDragDone?.call(DropDoneDetails(
      files: [DropItemFile(tempFile.path)],
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    ));
    await tester.pumpAndSettle();

    // Verify error notification is shown
    expect(find.textContaining('Archivo no soportado'), findsOneWidget);
  });

  testWidgets('DropTarget handles media directory and updates state', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final dropTargetFinder = find.byType(DropTarget);
    final dropTarget = tester.widget<DropTarget>(dropTargetFinder);

    final tempDir = Directory.systemTemp.createTempSync('renombrata_drop_media_');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    await tester.runAsync(() async {
      dropTarget.onDragDone?.call(DropDoneDetails(
        files: [DropItemFile(tempDir.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // Confirm folder ingestion dialog if presented
    final confirmBtn = find.text('Iniciar Proyecto con estos Medios');
    if (confirmBtn.evaluate().isNotEmpty) {
      await tester.runAsync(() async {
        await tester.tap(confirmBtn);
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
    }

    // Verify notification for media folder is shown
    expect(find.textContaining('Carpeta de medios cargada'), findsOneWidget);
  });

  testWidgets('DropTarget handles project file (.renombrata) and loads project', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final dropTargetFinder = find.byType(DropTarget);
    final dropTarget = tester.widget<DropTarget>(dropTargetFinder);

    final tempProjectFile = File('${Directory.systemTemp.path}/test_drop_project.renombrata');
    final log = ShootingLog(
      metadata: ShootingLogMetadata(
        nomenclature: 'TEST',
        date: '010124',
        unit: 'U1',
        day: 'D1',
        producer: 'P',
        production: 'PR',
        location: 'L',
        audioFormat: 'F',
        frameRate: '24fps',
        videoCodec: 'ProRes',
        responsibleEngineer: 'E',
        ingestor: 'I',
      ),
      records: [],
    );
    final project = RenombrataProject(
      log: log,
      defaultReel: 'A007_1',
      activeCamera: 'A',
    );
    tempProjectFile.writeAsStringSync(jsonEncode(project.toJson()));
    addTearDown(() {
      if (tempProjectFile.existsSync()) tempProjectFile.deleteSync();
    });

    await tester.runAsync(() async {
      dropTarget.onDragDone?.call(DropDoneDetails(
        files: [DropItemFile(tempProjectFile.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.textContaining('Proyecto cargado'), findsOneWidget);
  });

  testWidgets('DropTarget handles Excel bitácora (.xlsx) and imports log', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final dropTargetFinder = find.byType(DropTarget);
    final dropTarget = tester.widget<DropTarget>(dropTargetFinder);

    final tempExcelFile = File('${Directory.systemTemp.path}/test_drop_bitacora.xlsx');
    final excel = Excel.createExcel();
    final sheetName = excel.tables.keys.first;
    final sheet = excel[sheetName];

    // Metadata
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0), TextCellValue('Producer Name'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1), TextCellValue('Production Title'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2), TextCellValue('MNLDVDL'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3), TextCellValue('Location A'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 4), TextCellValue('071026'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0), TextCellValue('U3'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1), TextCellValue('D3'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 2), TextCellValue('Format X'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 3), TextCellValue('Eng Name'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 4), TextCellValue('Ingestor Name'));

    // Headers
    List<String> headers = ['CAP', 'ESCENA', 'PLANO', 'TOMA', 'CAM A', 'CAM B', 'CAM C', 'REEL', 'TC IN', 'TC OUT', 'OBSERVACIONES'];
    for (int i = 0; i < headers.length; i++) {
      sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 6), TextCellValue(headers[i]));
    }

    // Row 1
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 7), IntCellValue(1));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 7), TextCellValue('101'));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 7), IntCellValue(1));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 7), IntCellValue(1));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 7), IntCellValue(1));
    sheet.updateCell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 7), TextCellValue('A001'));

    tempExcelFile.writeAsBytesSync(excel.encode()!);
    addTearDown(() {
      if (tempExcelFile.existsSync()) tempExcelFile.deleteSync();
    });

    await tester.runAsync(() async {
      dropTarget.onDragDone?.call(DropDoneDetails(
        files: [DropItemFile(tempExcelFile.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // Verify notification for bitácora import
    expect(find.textContaining('Bitácora importada'), findsOneWidget);
  });

  testWidgets('DropTarget handles Apple Pages (.pages) file with platform dialog', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final dropTargetFinder = find.byType(DropTarget);
    final dropTarget = tester.widget<DropTarget>(dropTargetFinder);

    final tempPagesFile = File('${Directory.systemTemp.path}/test_callsheet.pages');
    tempPagesFile.writeAsStringSync('dummy pages content');
    addTearDown(() {
      if (tempPagesFile.existsSync()) tempPagesFile.deleteSync();
    });

    await tester.runAsync(() async {
      dropTarget.onDragDone?.call(DropDoneDetails(
        files: [DropItemFile(tempPagesFile.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    if (Platform.isWindows) {
      // On Windows, the informative dialog is shown
      expect(find.text('Archivo Apple Pages (.pages)'), findsOneWidget);
      expect(find.textContaining('Los archivos de Apple Pages (.pages) se procesan automáticamente en macOS'), findsOneWidget);
      expect(find.text('Entendido'), findsOneWidget);

      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.text('Archivo Apple Pages (.pages)'), findsNothing);
    }
  });

  testWidgets('DropTarget handles plain text bitácora (.txt) and imports log', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final dropTargetFinder = find.byType(DropTarget);
    final dropTarget = tester.widget<DropTarget>(dropTargetFinder);

    final tempTxtFile = File('${Directory.systemTemp.path}/test_bitacora.txt');
    tempTxtFile.writeAsStringSync('TODTA_2_13_P1_T1_A001_D01_1_U1\nTODTA_2_13_P1_TF1_A001_D01_2_U1\n');
    addTearDown(() {
      if (tempTxtFile.existsSync()) tempTxtFile.deleteSync();
    });

    await tester.runAsync(() async {
      dropTarget.onDragDone?.call(DropDoneDetails(
        files: [DropItemFile(tempTxtFile.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('Bitácora importada'), findsOneWidget);
    expect(find.textContaining('2 tomas registradas en 1 reels'), findsOneWidget);
  });

  testWidgets('DropTarget handles RTF bitácora (.rtf) and imports log', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final dropTargetFinder = find.byType(DropTarget);
    final dropTarget = tester.widget<DropTarget>(dropTargetFinder);

    final tempRtfFile = File('${Directory.systemTemp.path}/test_bitacora.rtf');
    tempRtfFile.writeAsStringSync(r'{\rtf1\ansi\deff0 {\fonttbl{\f0 Helvetica;}}\pard TODTA_2_13_P1_T1_A001_D01_1_U1\par TODTA_2_13_P1_T2_B001_D01_2_U1\par}');
    addTearDown(() {
      if (tempRtfFile.existsSync()) tempRtfFile.deleteSync();
    });

    await tester.runAsync(() async {
      dropTarget.onDragDone?.call(DropDoneDetails(
        files: [DropItemFile(tempRtfFile.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('Bitácora importada'), findsOneWidget);
    expect(find.textContaining('2 tomas registradas en 2 reels'), findsOneWidget);
  });
}
