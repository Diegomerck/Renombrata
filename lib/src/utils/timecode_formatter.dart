import 'package:flutter/services.dart';

class TimecodeUtils {
  static String normalize(String timecode, String frameRate) {
    final trimmed = timecode.trim();
    if (trimmed.isEmpty) return trimmed;

    // Check if input contains colons (e.g., '15:01', '9:30', '15:01:30', '15:01:30:12')
    if (trimmed.contains(':')) {
      final parts = trimmed.split(':').map((p) => p.replaceAll(RegExp(r'[^0-9]'), '')).toList();
      int h = 0, m = 0, s = 0, f = 0;
      if (parts.length == 1) {
        h = int.tryParse(parts[0]) ?? 0;
      } else if (parts.length == 2) {
        // HH:MM -> append 00 seconds and 00 frames
        h = int.tryParse(parts[0]) ?? 0;
        m = int.tryParse(parts[1]) ?? 0;
        s = 0;
        f = 0;
      } else if (parts.length == 3) {
        // HH:MM:SS -> append 00 frames
        h = int.tryParse(parts[0]) ?? 0;
        m = int.tryParse(parts[1]) ?? 0;
        s = int.tryParse(parts[2]) ?? 0;
        f = 0;
      } else if (parts.length >= 4) {
        h = int.tryParse(parts[0]) ?? 0;
        m = int.tryParse(parts[1]) ?? 0;
        s = int.tryParse(parts[2]) ?? 0;
        f = int.tryParse(parts[3]) ?? 0;
      }

      if (h > 23) h = 23;
      if (m > 59) m = 59;
      if (s > 59) s = 59;

      int maxFrames = 29;
      if (frameRate.startsWith('23.98') || frameRate.startsWith('24')) {
        maxFrames = 23;
      } else if (frameRate.startsWith('25')) {
        maxFrames = 24;
      }
      if (f > maxFrames) f = maxFrames;

      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}:${f.toString().padLeft(2, '0')}';
    }

    // clean non-digits
    String digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return trimmed;

    if (digits.length == 4) {
      // Treat as HHMM and append 0000 for seconds and frames
      digits = digits + '0000';
    } else if (digits.length == 6) {
      // Treat as HHMMSS and append 00 for frames
      digits = digits + '00';
    }

    // pad to 8 digits with zeros on the right
    digits = digits.padRight(8, '0');

    int hours = int.tryParse(digits.substring(0, 2)) ?? 0;
    int minutes = int.tryParse(digits.substring(2, 4)) ?? 0;
    int seconds = int.tryParse(digits.substring(4, 6)) ?? 0;
    int frames = int.tryParse(digits.substring(6, 8)) ?? 0;

    if (hours > 23) hours = 23;
    if (minutes > 59) minutes = 59;
    if (seconds > 59) seconds = 59;

    int maxFrames = 29;
    if (frameRate.startsWith('23.98') || frameRate.startsWith('24')) {
      maxFrames = 23;
    } else if (frameRate.startsWith('25')) {
      maxFrames = 24;
    }

    if (frames > maxFrames) frames = maxFrames;

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
  }

  static String withZeroFrames(String timecode) {
    final parts = timecode.split(':');
    if (parts.length == 4) {
      return '${parts[0]}:${parts[1]}:${parts[2]}:00';
    }
    return timecode;
  }

  static int getFpsInt(String frameRate) {
    if (frameRate.startsWith('23.98') || frameRate.startsWith('24')) return 24;
    if (frameRate.startsWith('25')) return 25;
    if (frameRate.startsWith('29.97') || frameRate.startsWith('30')) return 30;
    return 24;
  }

  static String formatTimecodeFromDateTime(DateTime time, String frameRate) {
    final fps = getFpsInt(frameRate);
    final frame = ((time.millisecond / 1000.0) * fps).floor().clamp(0, fps - 1);
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final f = frame.toString().padLeft(2, '0');
    return '$h:$m:$s:$f';
  }

  static String formatTimecodeFromDuration(Duration duration, String frameRate) {
    final fps = getFpsInt(frameRate);
    final totalSeconds = duration.inSeconds;
    final hours = (totalSeconds ~/ 3600) % 24;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final milliseconds = duration.inMilliseconds % 1000;
    final frame = ((milliseconds / 1000.0) * fps).floor().clamp(0, fps - 1);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}:${frame.toString().padLeft(2, '0')}';
  }
}

class TimecodeTextInputFormatter extends TextInputFormatter {
  final String frameRate;

  TimecodeTextInputFormatter(this.frameRate);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String newText = newValue.text;
    
    // Check if a colon was deleted
    if (oldValue.text.length > newValue.text.length && 
        oldValue.text.endsWith(':') && 
        !newValue.text.endsWith(':') &&
        oldValue.text.substring(0, oldValue.text.length - 1) == newValue.text) {
      if (newText.isNotEmpty) {
        newText = newText.substring(0, newText.length - 1);
      }
    }

    String cleanText = newText.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleanText.length >= 8) {
      cleanText = cleanText.substring(0, 8);
      // Automatically normalize if 8 digits are typed
      final normalized = TimecodeUtils.normalize(cleanText, frameRate);
      return TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }

    String formattedText = '';
    for (int i = 0; i < cleanText.length; i++) {
      if (i > 0 && i % 2 == 0) {
        formattedText += ':';
      }
      formattedText += cleanText[i];
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
