import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/ui/dialogs/sony_m01_confirmation_dialog.dart';

void main() {
  Widget buildTestDialog({
    String? sampleVideoName,
    String? sampleXmlName,
    void Function(bool?)? onClosed,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await SonyM01ConfirmationDialog.show(
                context,
                sampleVideoName: sampleVideoName,
                sampleXmlName: sampleXmlName,
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

  group('SonyM01ConfirmationDialog Widget Tests', () {
    testWidgets('renders dialog title, instructions, and default sample file names', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(buildTestDialog());
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Archivos de Metadatos Sony (M01.XML) Detectados'), findsOneWidget);
      expect(
        find.textContaining('Se encontraron archivos de metadatos XML que terminan en M01'),
        findsOneWidget,
      );
      expect(
        find.text('Video: [A055C001_230309CV.mxf] <--> Metadatos: [A055C001_230309CVM01.xml]'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sony_m01_ignore_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('sony_m01_confirm_button')), findsOneWidget);
    });

    testWidgets('renders custom sample video and xml names when provided', (tester) async {
      setupDesktopWindow(tester);

      await tester.pumpWidget(
        buildTestDialog(
          sampleVideoName: 'B002C015_240101XY.mp4',
          sampleXmlName: 'B002C015_240101XYM01.XML',
        ),
      );
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(
        find.text('Video: [B002C015_240101XY.mp4] <--> Metadatos: [B002C015_240101XYM01.XML]'),
        findsOneWidget,
      );
    });

    testWidgets('tapping "Vincular y Renombrar Metadatos" pops true', (tester) async {
      setupDesktopWindow(tester);

      bool? dialogResult;
      await tester.pumpWidget(
        buildTestDialog(
          onClosed: (res) => dialogResult = res,
        ),
      );
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sony_m01_confirm_button')));
      await tester.pumpAndSettle();

      expect(dialogResult, isTrue);
      expect(find.byType(SonyM01ConfirmationDialog), findsNothing);
    });

    testWidgets('tapping "Ignorar Archivos M01" pops false', (tester) async {
      setupDesktopWindow(tester);

      bool? dialogResult;
      await tester.pumpWidget(
        buildTestDialog(
          onClosed: (res) => dialogResult = res,
        ),
      );
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sony_m01_ignore_button')));
      await tester.pumpAndSettle();

      expect(dialogResult, isFalse);
      expect(find.byType(SonyM01ConfirmationDialog), findsNothing);
    });
  });
}
