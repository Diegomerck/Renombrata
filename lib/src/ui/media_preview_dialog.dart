import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p_path;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/services/convention_name_generator.dart';
import 'package:renombrata/src/utils/media_proxy_utils.dart';
import 'package:renombrata/src/utils/frame_step_utils.dart';
import 'package:renombrata/src/services/still_capture_service.dart';

class _ClipTagState {
  final String chapter;
  final String scene;
  final String plane;
  final String take;
  final String notes;
  final bool isMos;
  final bool isSaved;

  _ClipTagState({
    required this.chapter,
    required this.scene,
    required this.plane,
    required this.take,
    required this.notes,
    required this.isMos,
    this.isSaved = false,
  });
}

class MediaPreviewDialog extends StatefulWidget {
  final List<RenameProposal> playlist;
  final int initialIndex;
  final ShootingLogMetadata projectMetadata;
  final String activeCamera;
  final String? reelOverride;
  final Future<void> Function(
    RenameProposal proposal,
    String chapter,
    String scene,
    String plane,
    String take,
    bool isMos,
    String notes,
  )
  onSaveTake;
  final bool autoSortByClip;
  final ValueChanged<bool>? onAutoSortChanged;
  final Player? customPlayer;
  final VideoController? customVideoController;
  final void Function(String message, {bool isError})? onNotification;
  final String? customStillsDirectoryPath;

  const MediaPreviewDialog({
    super.key,
    required this.playlist,
    required this.initialIndex,
    required this.projectMetadata,
    required this.activeCamera,
    this.reelOverride,
    required this.onSaveTake,
    this.autoSortByClip = true,
    this.onAutoSortChanged,
    this.customPlayer,
    this.customVideoController,
    this.onNotification,
    this.customStillsDirectoryPath,
  });

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  Player? _player;
  VideoController? _controller;
  bool _ownsPlayer = false;
  String? _playbackError;
  String? _linkedProxyPath;
  bool _activeIsProxy = true;
  final List<StreamSubscription> _subscriptions = [];

  late int _currentIndex;
  final Map<int, _ClipTagState> _clipStates = {};

  final TransformationController _zoomController = TransformationController();
  double _currentZoom = 1.0;
  Offset? _hoveredPointerPosition;
  late bool _autoSortByClip;
  String? _statusFeedbackMessage;
  bool _statusFeedbackIsError = false;
  Timer? _statusFeedbackTimer;

  void _showFeedback(String message, {bool isError = false}) {
    _statusFeedbackTimer?.cancel();
    setState(() {
      _statusFeedbackMessage = message;
      _statusFeedbackIsError = isError;
    });
    _statusFeedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _statusFeedbackMessage = null;
        });
      }
    });
  }

  late TextEditingController _chapterController;
  late TextEditingController _sceneController;
  late TextEditingController _planeController;
  late TextEditingController _takeController;
  late TextEditingController _notesController;
  bool _isMos = false;
  bool _isSaving = false;
  bool _isCapturingStill = false;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100.0;
  double _preMuteVolume = 100.0;
  bool _isMuted = false;
  bool _isDraggingSlider = false;
  double _dragSliderValue = 0.0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.playlist.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.playlist.length - 1);

    _autoSortByClip = widget.autoSortByClip;

    _chapterController = TextEditingController();
    _sceneController = TextEditingController();
    _planeController = TextEditingController();
    _takeController = TextEditingController();
    _notesController = TextEditingController();

    _chapterController.addListener(_onFormFieldChanged);
    _sceneController.addListener(_onFormFieldChanged);
    _planeController.addListener(_onFormFieldChanged);
    _takeController.addListener(_onFormFieldChanged);
    _notesController.addListener(_onFormFieldChanged);

    _zoomController.addListener(() {
      final scale = _zoomController.value.getMaxScaleOnAxis();
      if ((scale - _currentZoom).abs() > 0.02) {
        if (mounted) {
          setState(() => _currentZoom = scale);
        }
      }
    });

    if (widget.playlist.isNotEmpty) {
      final initialProposal = widget.playlist[_currentIndex];
      if (initialProposal.associatedRecord != null) {
        final rec = initialProposal.associatedRecord!;
        _clipStates[_currentIndex] = _ClipTagState(
          chapter: rec.chapter,
          scene: rec.scene,
          plane: rec.plane ?? '',
          take: rec.take,
          notes: rec.observations ?? '',
          isMos: rec.isMos,
          isSaved: true,
        );
      } else {
        _clipStates[_currentIndex] = _ClipTagState(
          chapter: '',
          scene: '',
          plane: '',
          take: '1',
          notes: '',
          isMos: false,
          isSaved: false,
        );
      }

      final st = _clipStates[_currentIndex]!;
      _chapterController.text = st.chapter;
      _sceneController.text = st.scene;
      _planeController.text = st.plane;
      _takeController.text = st.take;
      _notesController.text = st.notes;
      _isMos = st.isMos;
    }

    HardwareKeyboard.instance.addHandler(_handleHardwareKey);

    if (widget.playlist.isNotEmpty) {
      final initialPath = widget.playlist[_currentIndex].originalFilePath;
      if (initialPath != null) {
        _linkedProxyPath = MediaProxyUtils.findLinkedProxyPath(initialPath);
      }
    }

    try {
      if (widget.customPlayer != null) {
        _player = widget.customPlayer!;
        if (widget.customVideoController != null) {
          _controller = widget.customVideoController;
        } else {
          try {
            _controller = VideoController(
              _player!,
              configuration: const VideoControllerConfiguration(
                enableHardwareAcceleration: false,
              ),
            );
          } catch (_) {
            try {
              _controller = VideoController(_player!);
            } catch (_) {
              _controller = null;
            }
          }
        }
      } else {
        // Set osc: true to avoid media_kit attempting internal mpv property 'osc: no',
        // which triggers mpv runtime warning '_setProperty(osc, 1)'.
        _player = Player(
          configuration: const PlayerConfiguration(
            bufferSize: 32 * 1024 * 1024,
            osc: true,
          ),
        );
        try {
          final platform = _player?.platform;
          if (platform != null) {
            (platform as dynamic).setProperty('audio-channels', 'stereo');
            (platform as dynamic).setProperty('audio-pitch-correction', 'yes');
          }
        } catch (_) {}
        try {
          _controller = VideoController(
            _player!,
            configuration: const VideoControllerConfiguration(
              enableHardwareAcceleration: false,
            ),
          );
        } catch (e) {
          debugPrint('Software VideoController init failed, falling back: $e');
          try {
            _controller = VideoController(_player!);
          } catch (_) {
            _controller = null;
          }
        }
        _ownsPlayer = true;
      }

      if (widget.playlist.isNotEmpty) {
        final filePath = widget.playlist[_currentIndex].originalFilePath;
        if (filePath != null) {
          _playMedia(filePath);
        }
      }

      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();

      try {
        _subscriptions.add(
          _player!.stream.tracks.listen((tracks) {
            if (_currentIndex >= 0 && _currentIndex < widget.playlist.length) {
              final currentPath =
                  widget.playlist[_currentIndex].originalFilePath;
              if (currentPath != null) {
                final useProxy = _linkedProxyPath != null && _activeIsProxy;
                if (!useProxy && MediaProxyUtils.isCanonRaw(currentPath)) {
                  try {
                    final platform = _player?.platform;
                    if (platform != null) {
                      try {
                        (platform as dynamic).setProperty('vid', 'no');
                      } catch (_) {}
                    }
                  } catch (_) {}
                  try {
                    _player?.setVideoTrack(VideoTrack.no());
                  } catch (_) {}
                  try {
                    _player?.setVolume(100.0);
                  } catch (_) {}
                }
              }
            }
            if (tracks.audio.isNotEmpty) {
              final currentAudio = _player!.state.track.audio;
              if (currentAudio.id == 'no') {
                _player!.setAudioTrack(tracks.audio.first);
              }
            }
          }),
        );
      } catch (_) {}

      _subscriptions.add(
        _player!.stream.playing.listen((playing) {
          if (mounted) setState(() => _isPlaying = playing);
        }),
      );

      _subscriptions.add(
        _player!.stream.position.listen((pos) {
          if (mounted && !_isDraggingSlider) {
            setState(() => _position = pos);
          }
        }),
      );

      _subscriptions.add(
        _player!.stream.duration.listen((dur) {
          if (mounted) setState(() => _duration = dur);
        }),
      );

      _subscriptions.add(
        _player!.stream.volume.listen((vol) {
          if (mounted) {
            setState(() {
              _volume = vol;
              _isMuted = vol <= 0.0;
            });
          }
        }),
      );

      try {
        _subscriptions.add(
          _player!.stream.error.listen((err) {
            debugPrint('MediaPreviewDialog player error: $err');
            if (mounted) {
              setState(() {
                _playbackError = err.toString();
              });
            }
          }),
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('Error initializing player: $e');
    }
  }

  String _normalizeMediaPath(String inputPath) {
    final trimmed = inputPath.trim();
    if (trimmed.startsWith('file:')) {
      try {
        return Uri.parse(trimmed).toFilePath();
      } catch (_) {
        return trimmed.replaceFirst(RegExp(r'^file:/*'), '');
      }
    }
    return trimmed;
  }

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
    if (mounted) {
      setState(() => _currentZoom = 1.0);
    }
  }

  void _zoomTo(double targetScale, {Offset? focalPoint}) {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    final clampedScale = targetScale.clamp(1.0, 5.0);
    if ((clampedScale - currentScale).abs() < 0.005) return;

    if (clampedScale <= 1.05) {
      _resetZoom();
      return;
    }

    // If no focal point is provided, default to the center of the viewport
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final defaultFocal = box != null
        ? Offset(box.size.width / 2, box.size.height / 2)
        : const Offset(400, 225);
    final focal = focalPoint ?? defaultFocal;

    // Extract current translation
    final currentTranslation = _zoomController.value.getTranslation();
    final currentTranslationOffset = Offset(
      currentTranslation.x,
      currentTranslation.y,
    );

    // Calculate new translation such that the content under the focal point remains stationary
    final contentPoint = (focal - currentTranslationOffset) / currentScale;
    final newTranslationOffset = focal - (contentPoint * clampedScale);

    final matrix = Matrix4.identity()
      ..translate(newTranslationOffset.dx, newTranslationOffset.dy)
      ..scale(clampedScale);

    _zoomController.value = matrix;
    if (mounted) {
      setState(() => _currentZoom = clampedScale);
    }
  }

  void _zoomIn({Offset? focalPoint}) {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    _zoomTo(
      currentScale * 1.3,
      focalPoint: focalPoint ?? _hoveredPointerPosition,
    );
  }

  void _zoomOut({Offset? focalPoint}) {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    _zoomTo(
      currentScale / 1.3,
      focalPoint: focalPoint ?? _hoveredPointerPosition,
    );
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    if (event.logicalKey == LogicalKeyboardKey.pageDown ||
        ((isCtrl || isAlt) &&
            event.logicalKey == LogicalKeyboardKey.arrowRight)) {
      if (_currentIndex < widget.playlist.length - 1) {
        _goToClip(_currentIndex + 1);
        return true;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.pageUp ||
        ((isCtrl || isAlt) &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft)) {
      if (_currentIndex > 0) {
        _goToClip(_currentIndex - 1);
        return true;
      }
    }

    if (isCtrl && event.logicalKey == LogicalKeyboardKey.enter) {
      _handleSaveAndNext();
      return true;
    }

    if (isCtrl) {
      if (event.logicalKey == LogicalKeyboardKey.equal ||
          event.logicalKey == LogicalKeyboardKey.add) {
        _zoomIn();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.minus ||
          event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
        _zoomOut();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.digit0 ||
          event.logicalKey == LogicalKeyboardKey.numpad0) {
        _resetZoom();
        return true;
      }
    }

    return false;
  }

  void _onFormFieldChanged() {
    if (mounted) setState(() {});
  }

  String _incrementTake(String take) {
    final trimmed = take.trim();
    if (trimmed.isEmpty) return '1';
    final match = RegExp(r'^(.*?)(\d+)$').firstMatch(trimmed);
    if (match != null) {
      final prefix = match.group(1)!;
      final numStr = match.group(2)!;
      final val = int.tryParse(numStr);
      if (val != null) {
        final nextVal = val + 1;
        final padded = numStr.startsWith('0') && numStr.length > 1
            ? nextVal.toString().padLeft(numStr.length, '0')
            : nextVal.toString();
        return '$prefix$padded';
      }
    }
    return '${trimmed}1';
  }

  void _stepTake(int delta) {
    final trimmed = _takeController.text.trim();
    if (trimmed.isEmpty) {
      _takeController.text = '1';
      return;
    }
    final match = RegExp(r'^(.*?)(\d+)$').firstMatch(trimmed);
    if (match != null) {
      final prefix = match.group(1)!;
      final numStr = match.group(2)!;
      final val = int.tryParse(numStr);
      if (val != null) {
        final nextVal = (val + delta).clamp(1, 9999);
        final padded = numStr.startsWith('0') && numStr.length > 1
            ? nextVal.toString().padLeft(numStr.length, '0')
            : nextVal.toString();
        _takeController.text = '$prefix$padded';
      }
    } else {
      _takeController.text = '1';
    }
  }

  void _playMedia(
    String path, {
    Duration? seekPosition,
    bool forceDirectMaster = false,
  }) {
    final proxy = MediaProxyUtils.findLinkedProxyPath(path);
    _linkedProxyPath = proxy;

    final bool useProxy = proxy != null && _activeIsProxy && !forceDirectMaster;
    final String mediaToPlay = useProxy ? proxy : path;
    final bool isCrmDirect = MediaProxyUtils.isCanonRaw(mediaToPlay);

    try {
      final platform = _player?.platform;
      if (isCrmDirect) {
        if (platform != null) {
          try {
            (platform as dynamic).setProperty('vid', 'no');
          } catch (_) {}
        }
        try {
          _player?.setVideoTrack(VideoTrack.no());
        } catch (_) {}
      } else {
        if (platform != null) {
          try {
            (platform as dynamic).setProperty('vid', 'auto');
          } catch (_) {}
        }
        try {
          _player?.setVideoTrack(VideoTrack.auto());
        } catch (_) {}
      }
    } catch (_) {}

    try {
      _player?.open(Media(_normalizeMediaPath(mediaToPlay))).then((_) {
        if (isCrmDirect) {
          try {
            final platform = _player?.platform;
            if (platform != null) {
              try {
                (platform as dynamic).setProperty('vid', 'no');
              } catch (_) {}
            }
          } catch (_) {}
          try {
            _player?.setVideoTrack(VideoTrack.no());
          } catch (_) {}
          try {
            _player?.setVolume(100.0);
          } catch (_) {}
        }
        if (seekPosition != null && seekPosition > Duration.zero) {
          _player?.seek(seekPosition);
        }
      });
    } catch (e) {
      debugPrint('Error opening media in preview: $e');
    }
  }

  void _goToClip(int newIndex) {
    if (newIndex < 0 || newIndex >= widget.playlist.length) return;
    if (newIndex == _currentIndex) return;

    _resetZoom();

    // 1. Save current input values into _clipStates[_currentIndex]
    _clipStates[_currentIndex] = _ClipTagState(
      chapter: _chapterController.text.trim(),
      scene: _sceneController.text.trim(),
      plane: _planeController.text.trim(),
      take: _takeController.text.trim(),
      notes: _notesController.text.trim(),
      isMos: _isMos,
      isSaved: _clipStates[_currentIndex]?.isSaved ?? false,
    );

    final newProposal = widget.playlist[newIndex];
    if (newProposal.originalFilePath != null) {
      _playMedia(newProposal.originalFilePath!);
    }

    setState(() {
      _playbackError = null;
      if (_clipStates.containsKey(newIndex)) {
        // Restore exact cached values: DO NOT call _incrementTake
        final cached = _clipStates[newIndex]!;
        _chapterController.text = cached.chapter;
        _sceneController.text = cached.scene;
        _planeController.text = cached.plane;
        _takeController.text = cached.take;
        _notesController.text = cached.notes;
        _isMos = cached.isMos;
      } else {
        // newIndex has NOT been visited yet
        if (newProposal.associatedRecord != null) {
          final rec = newProposal.associatedRecord!;
          _clipStates[newIndex] = _ClipTagState(
            chapter: rec.chapter,
            scene: rec.scene,
            plane: rec.plane ?? '',
            take: rec.take,
            notes: rec.observations ?? '',
            isMos: rec.isMos,
            isSaved: true,
          );
          _chapterController.text = rec.chapter;
          _sceneController.text = rec.scene;
          _planeController.text = rec.plane ?? '';
          _takeController.text = rec.take;
          _notesController.text = rec.observations ?? '';
          _isMos = rec.isMos;
        } else {
          final prevState = _clipStates[_currentIndex];
          final prevChapter =
              prevState?.chapter ?? _chapterController.text.trim();
          final prevScene = prevState?.scene ?? _sceneController.text.trim();
          final prevPlane = prevState?.plane ?? _planeController.text.trim();
          final prevTake = prevState?.take ?? _takeController.text.trim();
          final nextTake = _incrementTake(prevTake);

          _chapterController.text = prevChapter;
          _sceneController.text = prevScene;
          _planeController.text = prevPlane;
          _takeController.text = nextTake;
          _notesController.text = '';
          _isMos = false;

          _clipStates[newIndex] = _ClipTagState(
            chapter: prevChapter,
            scene: prevScene,
            plane: prevPlane,
            take: nextTake,
            notes: '',
            isMos: false,
            isSaved: false,
          );
        }
      }
      _currentIndex = newIndex;
    });
  }

  Future<void> _handleSaveAndNext() async {
    if (_isSaving || widget.playlist.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final currentProposal = widget.playlist[_currentIndex];
      final chapter = _chapterController.text.trim();
      final scene = _sceneController.text.trim();
      final plane = _planeController.text.trim();
      final take = _takeController.text.trim();
      final notes = _notesController.text.trim();

      await widget.onSaveTake(
        currentProposal,
        chapter,
        scene,
        plane,
        take,
        _isMos,
        notes,
      );

      _clipStates[_currentIndex] = _ClipTagState(
        chapter: chapter,
        scene: scene,
        plane: plane,
        take: take,
        notes: notes,
        isMos: _isMos,
        isSaved: true,
      );

      if (mounted) {
        if (_currentIndex < widget.playlist.length - 1) {
          _goToClip(_currentIndex + 1);
        } else {
          widget.onNotification?.call(
            '¡Lote completado con éxito! Se inspeccionaron todos los clips.',
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        _showFeedback('Error al guardar: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _statusFeedbackTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _zoomController.dispose();

    _chapterController.removeListener(_onFormFieldChanged);
    _sceneController.removeListener(_onFormFieldChanged);
    _planeController.removeListener(_onFormFieldChanged);
    _takeController.removeListener(_onFormFieldChanged);
    _notesController.removeListener(_onFormFieldChanged);

    _chapterController.dispose();
    _sceneController.dispose();
    _planeController.dispose();
    _takeController.dispose();
    _notesController.dispose();

    if (_ownsPlayer && _player != null) {
      _player!.dispose();
    }
    super.dispose();
  }

  void _togglePlayPause() {
    _player?.playOrPause();
  }

  /// Whether the current clip is actually decoded as video (not a RAW /
  /// audio-only slate monitor), so frame stepping is meaningful.
  bool _canStepFrames() {
    if (_player == null || widget.playlist.isEmpty) return false;
    final path = widget.playlist[_currentIndex].originalFilePath;
    if (path == null) return false;
    if (path.toLowerCase().endsWith('.wav')) return false;
    if (_playbackError != null) return false;
    final isPlayingProxy = _linkedProxyPath != null && _activeIsProxy;
    if (MediaProxyUtils.isCanonRaw(path) && !isPlayingProxy) return false;
    return true;
  }

  /// Pauses playback and steps one frame back/forward.
  Future<void> _stepFrame({required bool forward}) async {
    final player = _player;
    if (player == null) return;
    final target = await FrameStepUtils.step(
      player,
      forward: forward,
      position: _position,
      duration: _duration,
      fps: FrameStepUtils.fpsFromFrameRate(widget.projectMetadata.frameRate),
    );
    if (target != null && mounted) {
      setState(() => _position = target);
    }
  }

  void _toggleMute() {
    if (_isMuted) {
      final target = _preMuteVolume > 0 ? _preMuteVolume : 100.0;
      _player?.setVolume(target);
      setState(() {
        _volume = target;
        _isMuted = false;
      });
    } else {
      _preMuteVolume = _volume;
      _player?.setVolume(0.0);
      setState(() {
        _volume = 0.0;
        _isMuted = true;
      });
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _formatFileSize(String? filePath) {
    if (filePath == null) return '—';
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        if (bytes >= 1024 * 1024 * 1024) {
          return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
        } else if (bytes >= 1024 * 1024) {
          return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
        } else if (bytes >= 1024) {
          return '${(bytes / 1024).toStringAsFixed(0)} KB';
        } else {
          return '$bytes B';
        }
      }
    } catch (_) {}
    return '—';
  }

  Widget _buildBroadcastSlateMonitor(
    RenameProposal? clip,
    ThemeData theme,
    bool isDark, {
    bool isCanonRaw = false,
  }) {
    if (clip == null) return const SizedBox.shrink();
    final originalPath = clip.originalFilePath;
    final originalName = originalPath != null
        ? p_path.basename(originalPath)
        : 'Clip';
    final ext = originalPath != null
        ? p_path.extension(originalPath).toUpperCase()
        : '';
    final formattedSize = _formatFileSize(originalPath);
    final tcIn = clip.fileTcIn ?? '—';
    final tcOut = clip.fileTcOut ?? '—';
    final playbackError = _playbackError ?? '';
    final posterFrame = MediaProxyUtils.findPosterFrame(originalPath);

    final bgColor = isDark ? const Color(0xFF0C0E14) : const Color(0xFFF8FAFC);
    final cardBorderColor = isDark
        ? const Color(0xFF1E2230)
        : const Color(0xFFE2E8F0);
    final cardBgColor = isDark ? const Color(0xFF121520) : Colors.white;

    final cardContent = Container(
      key: isCanonRaw
          ? const ValueKey('preview_canon_raw_hud')
          : const ValueKey('preview_slate_card'),
      constraints: const BoxConstraints(maxWidth: 580),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: posterFrame != null
            ? (isDark
                  ? const Color(0xFF121520).withValues(alpha: 0.88)
                  : Colors.white.withValues(alpha: 0.94))
            : cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCanonRaw
              ? (isDark
                    ? Colors.amber.shade500.withValues(alpha: 0.6)
                    : const Color(0xFFD97706).withValues(alpha: 0.6))
              : cardBorderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.45)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (isCanonRaw)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isPlaying
                    ? (isDark
                          ? Colors.amber.shade900.withValues(alpha: 0.35)
                          : const Color(0xFFFEF3C7))
                    : (isDark
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.12)
                          : const Color(0xFFE0F2FE)),
                border: Border.all(
                  color: _isPlaying
                      ? (isDark
                            ? Colors.amber.shade500
                            : const Color(0xFFD97706))
                      : (isDark
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                            : const Color(0xFF38BDF8)),
                  width: 2,
                ),
                boxShadow: _isPlaying
                    ? [
                        BoxShadow(
                          color:
                              (isDark
                                      ? Colors.amber.shade500
                                      : const Color(0xFFD97706))
                                  .withValues(alpha: 0.35),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                _isPlaying ? Icons.graphic_eq : Icons.camera_alt_outlined,
                size: 46,
                color: _isPlaying
                    ? (isDark ? Colors.amber.shade300 : const Color(0xFFB45309))
                    : (isDark
                          ? const Color(0xFF00E5FF)
                          : const Color(0xFF0284C7)),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF00E5FF).withValues(alpha: 0.12)
                    : const Color(0xFFE0F2FE),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF00E5FF).withValues(alpha: 0.35)
                      : const Color(0xFF38BDF8),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.movie_filter_outlined,
                size: 44,
                color: isDark
                    ? const Color(0xFF00E5FF)
                    : const Color(0xFF0284C7),
              ),
            ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: isCanonRaw
                ? [
                    Container(
                      key: const ValueKey('preview_canon_raw_badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.amber.shade900.withValues(alpha: 0.35)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark
                              ? Colors.amber.shade500.withValues(alpha: 0.8)
                              : const Color(0xFFD97706),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        '[CANON CINEMA RAW LIGHT]',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1.1,
                          color: isDark
                              ? Colors.amber.shade300
                              : const Color(0xFFB45309),
                        ),
                      ),
                    ),
                    Container(
                      key: const ValueKey('preview_smpte_live_badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.15)
                            : const Color(0xFFE0F7FA),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF00E5FF).withValues(alpha: 0.7)
                              : const Color(0xFF00838F),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        '[AUDIO & TIMECODE SMPTE EN VIVO]',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1.1,
                          color: isDark
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFF006064),
                        ),
                      ),
                    ),
                  ]
                : [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.12)
                            : const Color(0xFFE0F7FA),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF00E5FF).withValues(alpha: 0.6)
                              : const Color(0xFF00838F),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        '[MONITOR DE METADATOS SMPTE]',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1.1,
                          color: isDark
                              ? const Color(0xFF00E5FF)
                              : const Color(0xFF006064),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.amber.shade900.withValues(alpha: 0.3)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark
                              ? Colors.amber.shade500.withValues(alpha: 0.6)
                              : const Color(0xFFD97706),
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        '[BROADCAST / RAW MONITOR]',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 1.1,
                          color: isDark
                              ? Colors.amber.shade300
                              : const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
          ),
          const SizedBox(height: 12),
          Text(
            originalName,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.bold,
              fontSize: 15,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                size: 14,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              ),
              const SizedBox(width: 4),
              Text(
                'Tamaño: $formattedSize',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                    width: 1,
                  ),
                ),
                child: Text(
                  'Formato nativo: $ext',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF050B14) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF00E5FF).withValues(alpha: 0.35)
                    : const Color(0xFF0284C7).withValues(alpha: 0.45),
                width: 1.2,
              ),
            ),
            child: Text(
              'Timecode: $tcIn → $tcOut',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? const Color(0xFF00E5FF)
                    : const Color(0xFF0369A1),
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              isCanonRaw
                  ? 'Reproduciendo audio nativo PCM (24-bit) y código de tiempo SMPTE sincronizado. El formato CRAW de sensor opera en modo claqueta de audio.'
                  : 'Metadatos y Timecode SMPTE sincronizados. El códec nativo no requiere decodificación visual para reconciliación y renombrado.',
              style: TextStyle(
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF475569),
                fontSize: 11,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (isCanonRaw) ...[
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('preview_craw_audio_waveform'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF080C14)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isPlaying
                      ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
                      : (isDark ? Colors.white12 : const Color(0xFFCBD5E1)),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isPlaying ? Icons.graphic_eq : Icons.volume_mute_outlined,
                    size: 15,
                    color: _isPlaying
                        ? const Color(0xFF00E5FF)
                        : Colors.white38,
                  ),
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(14, (i) {
                      final factor = _isPlaying
                          ? ((math.sin(
                                          i * 0.7 +
                                              (_position.inMilliseconds /
                                                  180.0),
                                        ) *
                                        0.45 +
                                    0.55))
                                .clamp(0.2, 1.0)
                          : 0.18;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        width: 3,
                        height: (18 * factor).clamp(3.0, 18.0),
                        decoration: BoxDecoration(
                          color: _isPlaying
                              ? const Color(0xFF00E5FF)
                              : Colors.white24,
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isPlaying
                        ? 'PCM 24-BIT EN REPRODUCCIÓN'
                        : 'AUDIO EN ESPERA',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: _isPlaying
                          ? const Color(0xFF00E5FF)
                          : Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!isCanonRaw && playbackError.isNotEmpty) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.red.shade900.withValues(alpha: 0.25)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: isDark
                        ? Colors.red.shade400.withValues(alpha: 0.35)
                        : const Color(0xFFF87171).withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  playbackError,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: isDark
                        ? Colors.red.shade300
                        : const Color(0xFF991B1B),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final slateBody = Center(child: SingleChildScrollView(child: cardContent));

    if (posterFrame != null) {
      return Container(
        key: const ValueKey('preview_broadcast_slate_monitor'),
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Image.file(
                posterFrame,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
            // Cinema EVF HUD overlay
            Positioned.fill(
              child: Container(
                key: isCanonRaw
                    ? const ValueKey('preview_canon_raw_hud')
                    : null,
                padding: const EdgeInsets.all(12),
                child: Stack(
                  children: [
                    // Top-left floating badges
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            key: const ValueKey('preview_canon_raw_badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark
                                    ? Colors.amber.shade500.withValues(
                                        alpha: 0.8,
                                      )
                                    : const Color(0xFFD97706),
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              isCanonRaw
                                  ? '[CANON RAW 2K POSTER]'
                                  : '[POSTER FRAME 2K]',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                letterSpacing: 1.1,
                                color: isDark
                                    ? Colors.amber.shade300
                                    : const Color(0xFFB45309),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            key: const ValueKey('preview_smpte_live_badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark
                                    ? const Color(
                                        0xFF00E5FF,
                                      ).withValues(alpha: 0.7)
                                    : const Color(0xFF00838F),
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              '[AUDIO PCM 24-BIT]',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                letterSpacing: 1.1,
                                color: isDark
                                    ? const Color(0xFF00E5FF)
                                    : const Color(0xFF006064),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Bottom-left floating timecode pill
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(
                              0xFF00E5FF,
                            ).withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              size: 14,
                              color: Color(0xFF00E5FF),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'SMPTE: $tcIn \u2192 $tcOut',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: Color(0xFF00E5FF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('preview_broadcast_slate_monitor'),
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: slateBody,
    );
  }

  String _getLiveConventionName() {
    if (widget.playlist.isEmpty) return '—';
    final p = widget.playlist[_currentIndex];
    final ext = p.originalFilePath != null
        ? p_path.extension(p.originalFilePath!)
        : '';

    final scene = _sceneController.text.trim();
    final plane = _planeController.text.trim();
    final take = _takeController.text.trim();

    final fileReel =
        p.fileReel ?? ClipMatcherService.extractReel(p.originalFilePath ?? '');
    final defaultReel =
        widget.reelOverride ?? fileReel ?? p.associatedRecord?.reel ?? '';

    final base = ConventionNameGenerator.generate(
      nomenclature: widget.projectMetadata.nomenclature,
      date: widget.projectMetadata.date,
      scene: scene.isEmpty ? 'ESC' : scene,
      plane: plane.isEmpty ? null : plane,
      take: take.isEmpty ? '1' : take,
      reel: defaultReel,
      day: widget.projectMetadata.day,
      unit: widget.projectMetadata.unit,
      activeCamera: widget.activeCamera,
      reelOverride: widget.reelOverride,
    );

    return '$base$ext';
  }


  Widget _buildStatusFeedbackBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: _statusFeedbackIsError
          ? (isDark ? Colors.red.shade900.withValues(alpha: 0.8) : Colors.red.shade100)
          : (isDark ? Colors.green.shade900.withValues(alpha: 0.8) : Colors.green.shade100),
      child: Row(
        children: [
          Icon(
            _statusFeedbackIsError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: _statusFeedbackIsError
                ? (isDark ? Colors.red.shade200 : Colors.red.shade900)
                : (isDark ? Colors.green.shade200 : Colors.green.shade900),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusFeedbackMessage!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _statusFeedbackIsError
                    ? (isDark ? Colors.red.shade200 : Colors.red.shade900)
                    : (isDark ? Colors.green.shade200 : Colors.green.shade900),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              _statusFeedbackTimer?.cancel();
              setState(() => _statusFeedbackMessage = null);
            },
            color: _statusFeedbackIsError
                ? (isDark ? Colors.red.shade200 : Colors.red.shade900)
                : (isDark ? Colors.green.shade200 : Colors.green.shade900),
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPlaylist = widget.playlist.isNotEmpty;
    final currentProposal = hasPlaylist ? widget.playlist[_currentIndex] : null;
    final filename = currentProposal?.originalFilePath != null
        ? p_path.basename(currentProposal!.originalFilePath!)
        : 'Sin archivo';

    String tcRange = '';
    if (currentProposal?.fileTcIn != null) {
      if (currentProposal!.fileTcOut != null) {
        tcRange = '${currentProposal.fileTcIn} → ${currentProposal.fileTcOut}';
      } else {
        tcRange = currentProposal.fileTcIn!;
      }
    }

    final isCurrentSaved = _clipStates[_currentIndex]?.isSaved ?? false;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.pageDown): () {
          if (_currentIndex < widget.playlist.length - 1) {
            _goToClip(_currentIndex + 1);
          }
        },
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          control: true,
        ): () {
          if (_currentIndex < widget.playlist.length - 1) {
            _goToClip(_currentIndex + 1);
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () {
          if (_currentIndex < widget.playlist.length - 1) {
            _goToClip(_currentIndex + 1);
          }
        },
        const SingleActivator(LogicalKeyboardKey.pageUp): () {
          if (_currentIndex > 0) {
            _goToClip(_currentIndex - 1);
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () {
          if (_currentIndex > 0) {
            _goToClip(_currentIndex - 1);
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true): () {
          if (_currentIndex > 0) {
            _goToClip(_currentIndex - 1);
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true): () {
          if (_currentIndex < widget.playlist.length - 1) {
            _goToClip(_currentIndex + 1);
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () {
          if (_currentIndex > 0) {
            _goToClip(_currentIndex - 1);
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _handleSaveAndNext,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _handleSaveAndNext,
        const SingleActivator(LogicalKeyboardKey.enter): _handleSaveAndNext,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final isCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
            final isAlt = HardwareKeyboard.instance.isAltPressed;

            if (event.logicalKey == LogicalKeyboardKey.space) {
              final primaryFocus = FocusManager.instance.primaryFocus;
              final isTextEditing =
                  primaryFocus?.context?.widget is EditableText;
              if (!isTextEditing) {
                _togglePlayPause();
                return KeyEventResult.handled;
              }
            } else if (!isCtrl && !isAlt) {
              if (event.logicalKey == LogicalKeyboardKey.comma ||
                  event.logicalKey == LogicalKeyboardKey.period) {
                final primaryFocus = FocusManager.instance.primaryFocus;
                final isTextEditing =
                    primaryFocus?.context?.widget is EditableText;
                if (!isTextEditing && _canStepFrames()) {
                  _stepFrame(
                    forward: event.logicalKey == LogicalKeyboardKey.period,
                  );
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                final primaryFocus = FocusManager.instance.primaryFocus;
                final isTextEditing =
                    primaryFocus?.context?.widget is EditableText;
                if (!isTextEditing) {
                  final target = _position - const Duration(seconds: 5);
                  _player?.seek(
                    target < Duration.zero ? Duration.zero : target,
                  );
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                final primaryFocus = FocusManager.instance.primaryFocus;
                final isTextEditing =
                    primaryFocus?.context?.widget is EditableText;
                if (!isTextEditing) {
                  final target = _position + const Duration(seconds: 5);
                  _player?.seek(target > _duration ? _duration : target);
                  return KeyEventResult.handled;
                }
              }
            }
          }
          return KeyEventResult.ignored;
        },
        child: Dialog(
          backgroundColor: isDark ? const Color(0xFF141418) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 720),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ==========================================
                // LEFT VIEWPORT (Expanded flex: 3)
                // ==========================================
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Navigation / Title Bar
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1C1C22)
                              : const Color(0xFFF0F2F6),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                          ),
                          border: Border(
                            bottom: BorderSide(
                              color: isDark
                                  ? const Color(0xFF2C2C36)
                                  : Colors.grey.shade300,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _currentIndex > 0
                                  ? () => _goToClip(_currentIndex - 1)
                                  : null,
                              icon: const Icon(Icons.arrow_back_ios, size: 12),
                              label: const Text('Anterior'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Clip ${_currentIndex + 1} de ${widget.playlist.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      filename,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isCurrentSaved) ...[
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: 'Toma registrada en bitácora',
                                      child: Icon(
                                        Icons.check_circle,
                                        size: 14,
                                        color: Colors.green.shade600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (tcRange.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    'TC: $tcRange',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              onPressed:
                                  _currentIndex < widget.playlist.length - 1
                                  ? () => _goToClip(_currentIndex + 1)
                                  : null,
                              icon: const Icon(
                                Icons.arrow_forward_ios,
                                size: 12,
                              ),
                              label: const Text('Siguiente'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              tooltip: 'Cerrar (Esc)',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                      if (_statusFeedbackMessage != null)
                        _buildStatusFeedbackBanner(isDark),

                      // Video Screen Surface with Interactive Slate Magnifier
                      Expanded(
                        child: Container(
                          color: Colors.black,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRect(
                                child: Listener(
                                  behavior: HitTestBehavior.opaque,
                                  onPointerSignal: (pointerSignal) {
                                    if (pointerSignal is PointerScrollEvent) {
                                      if (pointerSignal.scrollDelta.dy < 0) {
                                        _zoomIn(
                                          focalPoint:
                                              pointerSignal.localPosition,
                                        );
                                      } else if (pointerSignal.scrollDelta.dy >
                                          0) {
                                        _zoomOut(
                                          focalPoint:
                                              pointerSignal.localPosition,
                                        );
                                      }
                                    }
                                  },
                                  child: GestureDetector(
                                    onDoubleTap: _resetZoom,
                                    child: MouseRegion(
                                      cursor: _currentZoom > 1.05
                                          ? SystemMouseCursors.grab
                                          : SystemMouseCursors.basic,
                                      onHover: (event) {
                                        _hoveredPointerPosition =
                                            event.localPosition;
                                      },
                                      onExit: (_) {
                                        _hoveredPointerPosition = null;
                                      },
                                      child: InteractiveViewer(
                                        transformationController:
                                            _zoomController,
                                        minScale: 1.0,
                                        maxScale: 5.0,
                                        panEnabled: true,
                                        scaleEnabled: true,
                                        trackpadScrollCausesScale: true,
                                        boundaryMargin: const EdgeInsets.all(
                                          600,
                                        ),
                                        clipBehavior: Clip.none,
                                        child: Center(
                                          child: AspectRatio(
                                            aspectRatio: 16 / 9,
                                            child: Builder(
                                              builder: (context) {
                                                final currentPath =
                                                    currentProposal
                                                        ?.originalFilePath;
                                                final isCrm =
                                                    MediaProxyUtils.isCanonRaw(
                                                      currentPath,
                                                    );
                                                final isDecoderErr =
                                                    MediaProxyUtils.isRawDecoderError(
                                                      _playbackError,
                                                    );
                                                final hasLinkedProxy =
                                                    _linkedProxyPath != null;
                                                final isPlayingProxy =
                                                    hasLinkedProxy &&
                                                    _activeIsProxy;
                                                final isCanonRawSlate =
                                                    (isCrm &&
                                                        !isPlayingProxy) ||
                                                    isDecoderErr;

                                                if (isCanonRawSlate ||
                                                    _playbackError != null) {
                                                  return _buildBroadcastSlateMonitor(
                                                    currentProposal,
                                                    Theme.of(context),
                                                    isDark,
                                                    isCanonRaw: isCanonRawSlate,
                                                  );
                                                }

                                                return Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    _controller != null
                                                        ? Video(
                                                            controller:
                                                                _controller!,
                                                            controls:
                                                                NoVideoControls,
                                                          )
                                                        : Container(
                                                            color:
                                                                Colors.black87,
                                                            child: const Center(
                                                              child: Text(
                                                                'Vista previa de video',
                                                                style: TextStyle(
                                                                  color: Colors
                                                                      .white70,
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                    if (isPlayingProxy)
                                                      Positioned(
                                                        top: 10,
                                                        left: 10,
                                                        child: Container(
                                                          key: const ValueKey(
                                                            'preview_proxy_linked_badge',
                                                          ),
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 10,
                                                                vertical: 4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                              0xFF065F46,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                            border: Border.all(
                                                              color:
                                                                  const Color(
                                                                    0xFF10B981,
                                                                  ),
                                                              width: 1.2,
                                                            ),
                                                            boxShadow: const [
                                                              BoxShadow(
                                                                color: Colors
                                                                    .black45,
                                                                blurRadius: 4,
                                                                offset: Offset(
                                                                  0,
                                                                  2,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              const Icon(
                                                                Icons.link,
                                                                size: 12,
                                                                color: Color(
                                                                  0xFF34D399,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              Text(
                                                                '[PROXY VINCULADO: ${p_path.basename(_linkedProxyPath!)}]',
                                                                style: const TextStyle(
                                                                  fontFamily:
                                                                      'monospace',
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Color(
                                                                    0xFFD1FAE5,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Floating Magnifier HUD Overlay
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.zoom_out,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        tooltip: 'Alejar (Ctrl -)',
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(),
                                        onPressed: _currentZoom > 1.05
                                            ? _zoomOut
                                            : null,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${(_currentZoom * 100).round()}%',
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.zoom_in,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        tooltip: 'Acercar (Ctrl +)',
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(),
                                        onPressed: _currentZoom < 4.95
                                            ? _zoomIn
                                            : null,
                                      ),
                                      if (_currentZoom > 1.05) ...[
                                        Container(
                                          height: 16,
                                          width: 1,
                                          color: Colors.white24,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.restart_alt,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                          tooltip: 'Restablecer 100% (Ctrl 0)',
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(4),
                                          constraints: const BoxConstraints(),
                                          onPressed: _resetZoom,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bottom Transport Bar
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1C1C22)
                              : const Color(0xFFF7F8FA),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: isDark
                                  ? const Color(0xFF2C2C36)
                                  : Colors.grey.shade300,
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 10,
                                ),
                              ),
                              child: Slider(
                                value: _isDraggingSlider
                                    ? _dragSliderValue
                                    : (_duration.inMilliseconds > 0
                                          ? (_position.inMilliseconds /
                                                    _duration.inMilliseconds)
                                                .clamp(0.0, 1.0)
                                          : 0.0),
                                onChanged: (val) {
                                  setState(() {
                                    _isDraggingSlider = true;
                                    _dragSliderValue = val;
                                  });
                                },
                                onChangeEnd: (val) {
                                  final targetMs =
                                      (val * _duration.inMilliseconds).round();
                                  _player?.seek(
                                    Duration(milliseconds: targetMs),
                                  );
                                  setState(() {
                                    _isDraggingSlider = false;
                                    _position = Duration(
                                      milliseconds: targetMs,
                                    );
                                  });
                                },
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  key: const ValueKey(
                                    'preview_frame_back_button',
                                  ),
                                  icon: const Icon(Icons.navigate_before),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Fotograma anterior (,)',
                                  onPressed: _canStepFrames()
                                      ? () => _stepFrame(forward: false)
                                      : null,
                                ),
                                IconButton(
                                  icon: Icon(
                                    _isPlaying ? Icons.pause : Icons.play_arrow,
                                  ),
                                  tooltip: _isPlaying
                                      ? 'Pausar (Espacio)'
                                      : 'Reproducir (Espacio)',
                                  onPressed: _togglePlayPause,
                                ),
                                IconButton(
                                  key: const ValueKey(
                                    'preview_frame_forward_button',
                                  ),
                                  icon: const Icon(Icons.navigate_next),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Fotograma siguiente (.)',
                                  onPressed: _canStepFrames()
                                      ? () => _stepFrame(forward: true)
                                      : null,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.replay_5),
                                  tooltip: 'Retroceder 5s (←)',
                                  onPressed: () {
                                    final target =
                                        _position - const Duration(seconds: 5);
                                    _player?.seek(
                                      target < Duration.zero
                                          ? Duration.zero
                                          : target,
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.forward_5),
                                  tooltip: 'Avanzar 5s (→)',
                                  onPressed: () {
                                    final target =
                                        _position + const Duration(seconds: 5);
                                    _player?.seek(
                                      target > _duration ? _duration : target,
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Theme.of(context).hintColor,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  key: const ValueKey(
                                    'preview_capture_still_button',
                                  ),
                                  icon: _isCapturingStill
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.camera_alt_outlined),
                                  tooltip: _isCapturingStill
                                      ? 'Capturando fotograma...'
                                      : 'Capturar fotograma (Guardar en Escritorio)',
                                  onPressed: _isCapturingStill
                                      ? null
                                      : () async {
                                          if (widget.playlist.isEmpty ||
                                              _currentIndex < 0 ||
                                              _currentIndex >=
                                                  widget.playlist.length) {
                                            _showFeedback(
                                              'No se pudo capturar el fotograma del video',
                                              isError: true,
                                            );
                                            return;
                                          }

                                          setState(() {
                                            _isCapturingStill = true;
                                          });

                                          try {
                                            final proposal =
                                                widget.playlist[_currentIndex];
                                            String baseName;
                                            if (proposal.proposedFileName
                                                    .trim()
                                                    .isNotEmpty) {
                                              baseName =
                                                  proposal.proposedFileName.trim();
                                            } else {
                                              final liveName =
                                                  _getLiveConventionName();
                                              if (liveName.isNotEmpty &&
                                                  liveName != '—') {
                                                baseName = liveName;
                                              } else if (proposal.originalFilePath !=
                                                  null) {
                                                baseName = p_path.basename(
                                                  proposal.originalFilePath!,
                                                );
                                              } else {
                                                baseName = 'Clip';
                                              }
                                            }

                                            final projectName = widget
                                                    .projectMetadata
                                                    .nomenclature
                                                    .isNotEmpty
                                                ? widget.projectMetadata.nomenclature
                                                : (widget
                                                        .projectMetadata
                                                        .production
                                                        .isNotEmpty
                                                    ? widget
                                                        .projectMetadata
                                                        .production
                                                    : 'Proyecto');
                                            final date = widget.projectMetadata.date;

                                            final stillsDir =
                                                StillCaptureService.getProjectStillsDirectory(
                                              projectName: projectName,
                                              date: date,
                                              baseDesktopPath: widget.customStillsDirectoryPath,
                                            );

                                            if (_player == null) {
                                              _showFeedback(
                                                'No se pudo capturar el fotograma del video',
                                                isError: true,
                                              );
                                              return;
                                            }

                                            final file =
                                                await StillCaptureService.captureStill(
                                              player: _player!,
                                              baseName: baseName,
                                              targetDir: stillsDir,
                                            );

                                            if (file != null && mounted) {
                                              final msg =
                                                  'Fotograma guardado: ${p_path.basename(file.path)} en ${p_path.basename(stillsDir.path)}';
                                              _showFeedback(msg);
                                              widget.onNotification?.call(msg);
                                            } else if (mounted) {
                                              const errMsg =
                                                  'No se pudo capturar el fotograma del video';
                                              _showFeedback(errMsg, isError: true);
                                              widget.onNotification?.call(
                                                errMsg,
                                                isError: true,
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() {
                                                _isCapturingStill = false;
                                              });
                                            }
                                          }
                                        },
                                ),
                                const SizedBox(width: 4),
                                if (_linkedProxyPath != null) ...[
                                  IconButton(
                                    key: const ValueKey(
                                      'preview_proxy_toggle_button',
                                    ),
                                    icon: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _activeIsProxy
                                            ? const Color(0xFF065F46)
                                            : const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: _activeIsProxy
                                              ? const Color(0xFF10B981)
                                              : Colors.white38,
                                        ),
                                      ),
                                      child: Text(
                                        _activeIsProxy ? 'PROXY' : 'ORIGINAL',
                                        style: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _activeIsProxy
                                              ? const Color(0xFFD1FAE5)
                                              : Colors.white70,
                                        ),
                                      ),
                                    ),
                                    tooltip: _activeIsProxy
                                        ? 'Cambiar a archivo maestro original'
                                        : 'Cambiar a proxy vinculado',
                                    onPressed: () {
                                      setState(() {
                                        _activeIsProxy = !_activeIsProxy;
                                        if (currentProposal?.originalFilePath !=
                                            null) {
                                          _playMedia(
                                            currentProposal!.originalFilePath!,
                                            seekPosition: _position,
                                            forceDirectMaster: !_activeIsProxy,
                                          );
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                IconButton(
                                  icon: Icon(
                                    _isMuted || _volume <= 0.0
                                        ? Icons.volume_off
                                        : (_volume < 50
                                              ? Icons.volume_down
                                              : Icons.volume_up),
                                  ),
                                  tooltip: _isMuted
                                      ? 'Activar sonido'
                                      : 'Silenciar',
                                  onPressed: _toggleMute,
                                ),
                                SizedBox(
                                  width: 80,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 4,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 8,
                                          ),
                                    ),
                                    child: Slider(
                                      value: _volume.clamp(0.0, 100.0),
                                      min: 0.0,
                                      max: 100.0,
                                      onChanged: (val) {
                                        _player?.setVolume(val);
                                        setState(() {
                                          _volume = val;
                                          _isMuted = val <= 0.0;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ==========================================
                // RIGHT QUICK-TAGGER PANEL (Width: 340px)
                // ==========================================
                Container(
                  width: 340,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A1A20)
                        : const Color(0xFFFAFAFC),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(12),
                    ),
                    border: Border(
                      left: BorderSide(
                        color: isDark
                            ? const Color(0xFF2C2C36)
                            : Colors.grey.shade300,
                      ),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Live Convention Name Card
                          Card(
                            elevation: 0,
                            color: isDark
                                ? const Color(0xFF24242E)
                                : const Color(0xFFEDF2F7),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isDark
                                    ? const Color(0xFF383848)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.auto_fix_high,
                                        size: 15,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'CONVENCIÓN EN TIEMPO REAL',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.copy_rounded,
                                          size: 16,
                                        ),
                                        tooltip: 'Copiar nombre propuesto',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          final text = _getLiveConventionName();
                                          Clipboard.setData(
                                            ClipboardData(text: text),
                                          );
                                          _showFeedback('Copiado: ');
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    _getLiveConventionName(),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Form Fields
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 65,
                                child: TextField(
                                  controller: _chapterController,
                                  decoration: const InputDecoration(
                                    labelText: 'Cap',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => _handleSaveAndNext(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _sceneController,
                                  decoration: const InputDecoration(
                                    labelText: 'Escena',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => _handleSaveAndNext(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 65,
                                child: TextField(
                                  controller: _planeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Plano',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => _handleSaveAndNext(),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          // Toma with quick +1 / -1 stepper buttons
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _takeController,
                                  decoration: const InputDecoration(
                                    labelText: 'Toma',
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => _handleSaveAndNext(),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton.outlined(
                                icon: const Icon(Icons.remove, size: 16),
                                tooltip: 'Toma -1',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _stepTake(-1),
                              ),
                              const SizedBox(width: 4),
                              IconButton.outlined(
                                icon: const Icon(Icons.add, size: 16),
                                tooltip: 'Toma +1',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _stepTake(1),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // MOS (Mudo) Checkbox
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text(
                              'MOS (Mudo)',
                              style: TextStyle(fontSize: 13),
                            ),
                            value: _isMos,
                            onChanged: (val) {
                              setState(() => _isMos = val ?? false);
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                          ),

                          const SizedBox(height: 8),

                          // Notas input
                          TextField(
                            controller: _notesController,
                            maxLines: 1,
                            decoration: const InputDecoration(
                              labelText: 'Notas',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _handleSaveAndNext(),
                          ),

                          const SizedBox(height: 8),

                          // Auto-ordenar bitácora por clip
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: const Tooltip(
                              message:
                                  'Ubica automáticamente la toma según el número de clip',
                              child: Text(
                                'Auto-ordenar bitácora por clip',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            value: _autoSortByClip,
                            onChanged: (val) {
                              setState(() => _autoSortByClip = val);
                              widget.onAutoSortChanged?.call(val);
                            },
                          ),

                          const SizedBox(height: 12),

                          // Read-only Metadata Badges
                          if (currentProposal != null) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF282834)
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Reel: ${currentProposal.fileReel ?? widget.reelOverride ?? "—"}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF282834)
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Cámara: ${widget.activeCamera} · Clip: ${ClipMatcherService.extractClipNumber(filename)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                if (tcRange.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF282834)
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'TC: $tcRange',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Action Button
                          SizedBox(
                            height: 42,
                            child: FilledButton.icon(
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.check_circle_outline,
                                      size: 18,
                                    ),
                              label: Text(
                                _currentIndex < widget.playlist.length - 1
                                    ? (isCurrentSaved
                                          ? 'Actualizar y Siguiente (Enter ➔)'
                                          : 'Guardar y Siguiente (Enter ➔)')
                                    : (isCurrentSaved
                                          ? 'Actualizar y Finalizar (Enter ➔)'
                                          : 'Guardar y Finalizar (Enter ➔)'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: _isSaving ? null : _handleSaveAndNext,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
