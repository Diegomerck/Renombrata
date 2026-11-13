import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/ui/widgets/convention_text_editing_controller.dart';

void main() {
  group('ConventionTextEditingController Tests', () {
    testWidgets(
      'buildTextSpan segments Fixed Header, Slate Core, and Fixed Tail without %',
      (tester) async {
        final controller = ConventionTextEditingController(
          text: 'MNBOENC_080626_17_11_T1_A001_1_D1_U3',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final span = controller.buildTextSpan(
                    context: context,
                    style: const TextStyle(color: Colors.white),
                    withComposing: false,
                  );
                  expect(span.children, isNotNull);
                  expect(span.children!.length, equals(3));

                  final headerSpan = span.children![0] as TextSpan;
                  final coreSpan = span.children![1] as TextSpan;
                  final tailSpan = span.children![2] as TextSpan;

                  // Fixed Header: {PROD}_{FECHA}_
                  expect(headerSpan.text, equals('MNBOENC_080626_'));
                  expect(headerSpan.style?.color, equals(const Color(0xFF64748B)));

                  // Slate Core: {CAP}_{ESC}_{PLANO}_{TOMA}_{REEL}
                  expect(coreSpan.text, equals('17_11_T1_A001'));
                  expect(coreSpan.style?.color, equals(const Color(0xFFF1F5F9)));

                  // Fixed Tail: _{CLIP}_{DIA}_{UNIDAD}
                  expect(tailSpan.text, equals('_1_D1_U3'));
                  expect(tailSpan.style?.color, equals(const Color(0xFF64748B)));

                  // Ensure zero character loss
                  final combined = span.children!
                      .map((s) => (s as TextSpan).text ?? '')
                      .join();
                  expect(combined, equals('MNBOENC_080626_17_11_T1_A001_1_D1_U3'));

                  return const SizedBox();
                },
              ),
            ),
          ),
        );
      },
    );

    testWidgets(
      'buildTextSpan distinguishes Header, Core, Tail, and Post-% Metadata',
      (tester) async {
        final controller = ConventionTextEditingController(
          text: 'MNBOENC_080626_17_11_T1_A001_1_D1_U3%A001_001_D1_U3',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final span = controller.buildTextSpan(
                    context: context,
                    style: const TextStyle(color: Colors.white),
                    withComposing: false,
                  );
                  expect(span.children, isNotNull);
                  expect(span.children!.length, equals(4));

                  final headerSpan = span.children![0] as TextSpan;
                  final coreSpan = span.children![1] as TextSpan;
                  final tailSpan = span.children![2] as TextSpan;
                  final postSpan = span.children![3] as TextSpan;

                  // 1. Header
                  expect(headerSpan.text, equals('MNBOENC_080626_'));
                  expect(headerSpan.style?.color, equals(const Color(0xFF64748B)));

                  // 2. Core
                  expect(coreSpan.text, equals('17_11_T1_A001'));
                  expect(coreSpan.style?.color, equals(const Color(0xFFF1F5F9)));

                  // 3. Tail
                  expect(tailSpan.text, equals('_1_D1_U3'));
                  expect(tailSpan.style?.color, equals(const Color(0xFF64748B)));

                  // 4. Post-Percent Metadata
                  expect(postSpan.text, equals('%A001_001_D1_U3'));
                  expect(postSpan.style?.color, equals(const Color(0xFF64748B)));
                  expect(postSpan.style?.fontStyle, equals(FontStyle.italic));

                  // Full string integrity
                  final combined = span.children!
                      .map((s) => (s as TextSpan).text ?? '')
                      .join();
                  expect(
                    combined,
                    equals('MNBOENC_080626_17_11_T1_A001_1_D1_U3%A001_001_D1_U3'),
                  );

                  return const SizedBox();
                },
              ),
            ),
          ),
        );
      },
    );

    testWidgets('buildTextSpan handles multi-line text with mixed format lines', (tester) async {
      final controller = ConventionTextEditingController(
        text: 'Line1_Physical%Sub1\nLine2_Physical_NoSub\nLine3_Physical%Sub3',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final span = controller.buildTextSpan(
                  context: context,
                  style: const TextStyle(color: Colors.white),
                  withComposing: false,
                );
                expect(span.children, isNotNull);
                // Line 1: prefix, suffix, newline
                // Line 2: full line, newline
                // Line 3: prefix, suffix
                expect(span.children!.length, equals(7));

                expect((span.children![0] as TextSpan).text, equals('Line1_Physical'));
                expect((span.children![1] as TextSpan).text, equals('%Sub1'));
                expect((span.children![2] as TextSpan).text, equals('\n'));
                expect((span.children![3] as TextSpan).text, equals('Line2_Physical_NoSub'));
                expect((span.children![4] as TextSpan).text, equals('\n'));
                expect((span.children![5] as TextSpan).text, equals('Line3_Physical'));
                expect((span.children![6] as TextSpan).text, equals('%Sub3'));
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    });
  });
}
