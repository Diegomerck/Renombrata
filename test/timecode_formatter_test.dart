import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/utils/timecode_formatter.dart';

void main() {
  group('TimecodeUtils', () {
    test('normalizes missing colons and pads right', () {
      expect(TimecodeUtils.normalize('1', '24'), '10:00:00:00');
      expect(TimecodeUtils.normalize('12', '24'), '12:00:00:00');
      expect(TimecodeUtils.normalize('123', '24'), '12:30:00:00');
    });

    test('treats 6 digits as HH:MM:SS and appends 00 for frames', () {
      expect(TimecodeUtils.normalize('010000', '24'), '01:00:00:00');
      expect(TimecodeUtils.normalize('123456', '24'), '12:34:56:00');
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

    test('normalizes HH:MM to 8 digits by appending :00:00', () {
      expect(TimecodeUtils.normalize('15:01', '24'), '15:01:00:00');
      expect(TimecodeUtils.normalize('15:04', '24'), '15:04:00:00');
      expect(TimecodeUtils.normalize('9:05', '24'), '09:05:00:00');
      expect(TimecodeUtils.normalize('1501', '24'), '15:01:00:00');
    });

    test('normalizes HH:MM:SS to 8 digits by appending :00 frames', () {
      expect(TimecodeUtils.normalize('15:01:30', '24'), '15:01:30:00');
      expect(TimecodeUtils.normalize('09:05:15', '24'), '09:05:15:00');
    });

    test('normalizes timecodes without frames by appending :00 frames', () {
      expect(TimecodeUtils.normalize('100033', '24'), '10:00:33:00');
      expect(TimecodeUtils.normalize('10:00:33', '24'), '10:00:33:00');
      expect(TimecodeUtils.normalize('10:00', '24'), '10:00:00:00');
      expect(TimecodeUtils.normalize('1000', '24'), '10:00:00:00');
      expect(TimecodeUtils.normalize('10', '24'), '10:00:00:00');
      expect(TimecodeUtils.normalize('10003312', '24'), '10:00:33:12');
    });

    test('withZeroFrames zeroes out frame digits', () {
      expect(TimecodeUtils.withZeroFrames('13:00:09:14'), '13:00:09:00');
      expect(TimecodeUtils.withZeroFrames('01:02:03:23'), '01:02:03:00');
    });
  });
}
