import 'package:flutter/services.dart';

class TimecodeUtils {
  static String normalize(String timecode, String frameRate) {
    if (timecode.isEmpty) return timecode;

    // clean non-digits
    String digits = timecode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return timecode;

    if (digits.length == 6) {
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
