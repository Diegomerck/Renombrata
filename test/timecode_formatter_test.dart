import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/utils/timecode_formatter.dart';

void main() {
  group('TimecodeUtils', () {
    test('normalizes missing colons and pads right', () {
      expect(TimecodeUtils.normalize('1', '24'), '10:00:00:00');
      expect(TimecodeUtils.normalize('12', '24'), '12:00:00:00');
      expect(TimecodeUtils.normalize('123', '24'), '12:30:00:00');
    });

    test('clamps hours, minutes, seconds', () {
      expect(TimecodeUtils.normalize('25656500', '24'), '23:59:59:00');
    });

    test('clamps frames based on frame rate 23.98/24', () {
      expect(TimecodeUtils.normalize('01000028', '23.98'), '01:00:00:23');
      expect(TimecodeUtils.normalize('01000028', '24'), '01:00:00:23');
      expect(TimecodeUtils.normalize('01000028', '24 fps'), '01:00:00:23');
    });

    test('clamps frames based on frame rate 25', () {
      expect(TimecodeUtils.normalize('01000028', '25'), '01:00:00:24');
    });

    test('clamps frames based on frame rate 29.97/30', () {
      expect(TimecodeUtils.normalize('01000035', '29.97nd'), '01:00:00:29');
      expect(TimecodeUtils.normalize('01000035', '30'), '01:00:00:29');
      expect(TimecodeUtils.normalize('01000035', '59.94'), '01:00:00:29');
    });
  });
}
