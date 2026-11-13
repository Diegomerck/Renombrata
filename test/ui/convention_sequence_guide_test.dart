import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/ui/widgets/convention_sequence_guide.dart';

void main() {
  group('ConventionSequenceGuide Tests', () {
    testWidgets('renders sequence tokens and camera badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConventionSequenceGuide(
              activeCamera: 'A',
              activeClipName: 'A001C002_260608HE.MP4',
              activeLineNumber: 2,
              cameraType: CameraType.regular,
            ),
          ),
        ),
      );

      expect(find.text('CAM A'), findsOneWidget);
      expect(find.text('Línea 2'), findsOneWidget);
      expect(find.textContaining('A001C002_260608HE.MP4'), findsOneWidget);

      expect(find.byKey(const ValueKey('guide_token_PROD')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide_token_ESC')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide_token_TOMA')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide_token_REEL')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide_token_% METADATOS')), findsOneWidget);
    });

    testWidgets('adapts tokens for GoPro camera type', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConventionSequenceGuide(
              activeCamera: 'GPR1',
              cameraType: CameraType.goPro,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('guide_token_GPR/TARJ')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide_token_FECHA')), findsOneWidget);
    });

    testWidgets('adapts tokens for Driving Shot camera type', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConventionSequenceGuide(
              activeCamera: 'DS',
              cameraType: CameraType.drivingShot,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('guide_token_TARJ')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide_token_DS')), findsOneWidget);
    });
  });
}

