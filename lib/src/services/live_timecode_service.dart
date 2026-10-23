import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:renombrata/src/utils/timecode_formatter.dart';

class LiveTimecodeService extends ChangeNotifier {
  bool _isTimeOfDay = true;
  Duration _customOffset = Duration.zero;
  DateTime? _customStartTime;
  bool _isAutoStampEnabled = true;
  String _frameRate;
  Timer? _timer;
  final DateTime Function() _now;

  LiveTimecodeService({
    String frameRate = '23.98',
    bool isAutoStampEnabled = true,
    DateTime Function()? nowProvider,
    bool startTimer = true,
  })  : _frameRate = frameRate,
        _isAutoStampEnabled = isAutoStampEnabled,
        _now = nowProvider ?? DateTime.now {
    if (startTimer) {
      _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        notifyListeners();
      });
    }
  }

  bool get isTimeOfDay => _isTimeOfDay;
  Duration get customOffset => _customOffset;
  DateTime? get customStartTime => _customStartTime;
  bool get isAutoStampEnabled => _isAutoStampEnabled;
  String get frameRate => _frameRate;

  String get currentFormattedTimecode {
    final now = _now();
    if (_isTimeOfDay) {
      return TimecodeUtils.formatTimecodeFromDateTime(now, _frameRate);
    } else {
      final start = _customStartTime ?? now;
      final elapsed = now.difference(start);
      final totalDuration = elapsed + _customOffset;
      return TimecodeUtils.formatTimecodeFromDuration(
        totalDuration < Duration.zero ? Duration.zero : totalDuration,
        _frameRate,
      );
    }
  }

  /// Formatted timecode with frames zeroed (:00) for starting takes (TC In)
  String get currentFormattedTimecodeZeroFrames =>
      TimecodeUtils.withZeroFrames(currentFormattedTimecode);

  void syncToTimeOfDay() {
    _isTimeOfDay = true;
    _customStartTime = null;
    _customOffset = Duration.zero;
    notifyListeners();
  }

  void jamTimecode(int hours, int minutes, int seconds, int frames) {
    final fps = TimecodeUtils.getFpsInt(_frameRate);
    _isTimeOfDay = false;
    _customStartTime = _now();
    final millis = ((frames.clamp(0, fps - 1) / fps) * 1000).round();
    _customOffset = Duration(
      hours: hours.clamp(0, 23),
      minutes: minutes.clamp(0, 59),
      seconds: seconds.clamp(0, 59),
      milliseconds: millis,
    );
    notifyListeners();
  }

  void toggleAutoStamp(bool enabled) {
    if (_isAutoStampEnabled != enabled) {
      _isAutoStampEnabled = enabled;
      notifyListeners();
    }
  }

  void updateFrameRate(String newFps) {
    if (_frameRate != newFps) {
      _frameRate = newFps;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
