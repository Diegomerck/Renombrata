import 'package:media_kit/media_kit.dart';

/// Helpers for frame-by-frame stepping in the media_kit based video players.
class FrameStepUtils {
  /// Default frame rate (23.976 fps) used when no frame rate is known.
  static const double defaultFps = 24000 / 1001;

  /// Converts a project frame-rate string (e.g. `23.98`, `24`, `29.97`) into
  /// the exact fps value used to compute a single frame duration.
  static double fpsFromFrameRate(String? frameRate) {
    final value = (frameRate ?? '').trim();
    if (value.isEmpty) return defaultFps;
    if (value.startsWith('23.97') || value.startsWith('23.98')) {
      return 24000 / 1001;
    }
    if (value.startsWith('29.97')) return 30000 / 1001;
    if (value.startsWith('59.94')) return 60000 / 1001;
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed != null && parsed > 0) return parsed;
    return defaultFps;
  }

  /// Duration of a single frame at [fps].
  static Duration frameDuration(double fps) {
    final safe = fps > 0 ? fps : defaultFps;
    return Duration(microseconds: (1000000 / safe).round());
  }

  /// Position one frame before/after [position], clamped to `[0, duration]`.
  static Duration targetPosition({
    required Duration position,
    required Duration duration,
    required bool forward,
    required double fps,
  }) {
    final frame = frameDuration(fps);
    var target = forward ? position + frame : position - frame;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    return target;
  }

  /// Pauses [player] and steps one frame back/forward.
  ///
  /// Uses mpv's native `frame-step` / `frame-back-step` commands. If they are
  /// unavailable (custom/mock players) it falls back to seeking by one frame
  /// duration. Returns the fallback seek target, or `null` when the native
  /// command handled the step (the position stream reports the new position).
  static Future<Duration?> step(
    Player player, {
    required bool forward,
    required Duration position,
    required Duration duration,
    required double fps,
  }) async {
    try {
      await player.pause();
    } catch (_) {}

    try {
      final platform = player.platform;
      if (platform == null) throw StateError('No native platform player');
      await (platform as dynamic).command([
        forward ? 'frame-step' : 'frame-back-step',
      ]);
      return null;
    } catch (_) {
      // Fall through to the seek-based fallback.
    }

    final target = targetPosition(
      position: position,
      duration: duration,
      forward: forward,
      fps: fps,
    );
    try {
      await player.seek(target);
    } catch (_) {}
    return target;
  }
}
