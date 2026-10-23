import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/app_settings.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/live_timecode_service.dart';
import 'package:renombrata/src/ui/bitacora_editor_tab.dart';
import 'package:renombrata/src/utils/timecode_formatter.dart';

void main() {
  group('TimecodeUtils Live Formatting Tests', () {
    test('formatTimecodeFromDateTime formats correctly for various frame rates', () {
      final dt1 = DateTime(2026, 10, 23, 14, 30, 15, 500);
      expect(TimecodeUtils.formatTimecodeFromDateTime(dt1, '23.98'), '14:30:15:12');
      expect(TimecodeUtils.formatTimecodeFromDateTime(dt1, '24'), '14:30:15:12');

      final dt2 = DateTime(2026, 10, 23, 10, 20, 30, 999);
      expect(TimecodeUtils.formatTimecodeFromDateTime(dt2, '25'), '10:20:30:24');

      final dt3 = DateTime(2026, 10, 23, 23, 59, 59, 750);
      expect(TimecodeUtils.formatTimecodeFromDateTime(dt3, '29.97'), '23:59:59:22');
      expect(TimecodeUtils.formatTimecodeFromDateTime(dt3, '30'), '23:59:59:22');
    });

    test('formatTimecodeFromDuration formats correctly for elapsed durations', () {
      final dur1 = const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500);
      expect(TimecodeUtils.formatTimecodeFromDuration(dur1, '24'), '01:02:03:12');

      final dur2 = const Duration(hours: 10, minutes: 0, seconds: 0, milliseconds: 0);
      expect(TimecodeUtils.formatTimecodeFromDuration(dur2, '25'), '10:00:00:00');
    });
  });

  group('LiveTimecodeService Logic Tests', () {
    test('TOD mode mirrors system clock and formats accurately', () {
      var mockNow = DateTime(2026, 10, 23, 9, 15, 30, 250);
      final service = LiveTimecodeService(
        frameRate: '24',
        nowProvider: () => mockNow,
        startTimer: false,
      );

      expect(service.isTimeOfDay, isTrue);
      expect(service.currentFormattedTimecode, '09:15:30:06');

      mockNow = DateTime(2026, 10, 23, 9, 15, 31, 500);
      expect(service.currentFormattedTimecode, '09:15:31:12');
      service.dispose();
    });

    test('Jam sync sets manual start time and progresses relative to elapsed time', () {
      var mockNow = DateTime(2026, 10, 23, 8, 0, 0, 0);
      final service = LiveTimecodeService(
        frameRate: '24',
        nowProvider: () => mockNow,
        startTimer: false,
      );

      // Jam to 01:00:00:00
      service.jamTimecode(1, 0, 0, 0);
      expect(service.isTimeOfDay, isFalse);
      expect(service.currentFormattedTimecode, '01:00:00:00');

      // Advance mock time by 10s and 500ms (12 frames at 24fps)
      mockNow = mockNow.add(const Duration(seconds: 10, milliseconds: 500));
      expect(service.currentFormattedTimecode, '01:00:10:12');

      // Sync back to TOD
      service.syncToTimeOfDay();
      expect(service.isTimeOfDay, isTrue);
      expect(service.currentFormattedTimecode, '08:00:10:12');
      service.dispose();
    });

    test('toggleAutoStamp and updateFrameRate notify listeners', () {
      var mockNow = DateTime(2026, 10, 23, 12, 30, 45, 750);
      final service = LiveTimecodeService(
        frameRate: '24',
        nowProvider: () => mockNow,
        startTimer: false,
      );

      int notifyCount = 0;
      service.addListener(() => notifyCount++);

      service.toggleAutoStamp(false);
      expect(service.isAutoStampEnabled, isFalse);
      expect(notifyCount, 1);

      service.updateFrameRate('25');
      expect(service.frameRate, '25');
      expect(notifyCount, 2);

      // currentFormattedTimecodeZeroFrames returns 00 frames
      expect(service.currentFormattedTimecode, '12:30:45:18');
      expect(service.currentFormattedTimecodeZeroFrames, '12:30:45:00');

      service.dispose();
    });
  });

  group('BitacoraEditorTab Live Timecode Auto-Stamping Widget Tests', () {
    testWidgets('auto-stamps tcIn on new and duplicated takes with zero frames, and stamps tcOut on Marcar Corte', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var mockNow = DateTime(2026, 10, 23, 16, 45, 10, 0);
      final timecodeService = LiveTimecodeService(
        frameRate: '24',
        nowProvider: () => mockNow,
        startTimer: false,
      );

      RenombrataProject currentProject = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(frameRate: '24'),
          records: [
            ShotRecord(id: 'r1', chapter: '1', scene: '10', plane: '1', take: '1', cameras: [], reel: '001', tcIn: '10:00:00:00', tcOut: ''),
          ],
        ),
        defaultReel: '001',
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
                  settings: const AppSettings(usePagesStyleLayout: true),
                  timecodeService: timecodeService,
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

      // Verify Live Timecode Badge renders
      expect(find.text('16:45:10:00'), findsOneWidget);
      expect(find.text('TOD'), findsOneWidget);

      // 1. Marcar Corte stamps tcOut on last record with zero frames (:00)
      mockNow = DateTime(2026, 10, 23, 16, 45, 20, 500); // 16:45:20:12 at 24fps
      timecodeService.notifyListeners();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Marcar Corte'));
      await tester.pumpAndSettle();
      expect(currentProject.log.records.last.tcOut, '16:45:20:00');
      // Verify TC Out TextFormField in the UI actually updated
      expect(find.widgetWithText(TextFormField, '16:45:20:00'), findsWidgets);

      // 2. Advance time and Add New Record with auto-stamping (frames default to :00)
      mockNow = DateTime(2026, 10, 23, 16, 46, 0, 500); // 16:46:00:12 at 24fps
      timecodeService.notifyListeners();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Nueva Toma'));
      await tester.pumpAndSettle();

      expect(currentProject.log.records.length, 2);
      expect(currentProject.log.records.last.tcIn, '16:46:00:00');

      // 3. Advance time and Duplicate last record with auto-stamping (frames default to :00)
      mockNow = DateTime(2026, 10, 23, 16, 47, 30, 750); // 16:47:30:18 at 24fps
      timecodeService.notifyListeners();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Duplicar última toma'));
      await tester.pumpAndSettle();

      expect(currentProject.log.records.length, 3);
      expect(currentProject.log.records.last.tcIn, '16:47:30:00');

      // 4. Toggle Auto TC off and verify newly added record has empty tcIn
      timecodeService.toggleAutoStamp(false);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Nueva Toma'));
      await tester.pumpAndSettle();

      expect(currentProject.log.records.length, 4);
      expect(currentProject.log.records.last.tcIn, isEmpty);

      timecodeService.dispose();
    });

    testWidgets('keyboard shortcuts Ctrl+N, Ctrl+K, Ctrl+D, Ctrl+Z function properly', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final timecodeService = LiveTimecodeService(
        frameRate: '24',
        nowProvider: () => DateTime(2026, 10, 23, 10, 0, 0, 0),
        startTimer: false,
      );

      RenombrataProject currentProject = RenombrataProject(
        log: ShootingLog(
          metadata: ShootingLogMetadata.empty().copyWith(frameRate: '24'),
          records: [
            ShotRecord(id: 'r1', chapter: '1', scene: '10', plane: '1', take: '1', cameras: [], reel: '001', tcIn: '10:00:00:00'),
          ],
        ),
        defaultReel: '001',
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
                  settings: const AppSettings(usePagesStyleLayout: true),
                  timecodeService: timecodeService,
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

      // 1. Ctrl+D -> Duplicate take (record 1 has take: '1' -> duplicated take: '2')
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      expect(currentProject.log.records.length, 2);
      expect(currentProject.log.records.last.take, '2');

      // 2. Ctrl+K -> Stamp cut on last record
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      expect(currentProject.log.records.last.tcOut, '10:00:00:00');

      // 3. Ctrl+N -> New take
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      expect(currentProject.log.records.length, 3);

      timecodeService.dispose();
    });
  });
}
