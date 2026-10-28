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
  ) onSaveTake;
  final bool autoSortByClip;
  final ValueChanged<bool>? onAutoSortChanged;
  final Player? customPlayer;
  final VideoController? customVideoController;

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
  });

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  Player? _player;
  VideoController? _controller;
  bool _ownsPlayer = false;

  late int _currentIndex;
  final Map<int, _ClipTagState> _clipStates = {};

  final TransformationController _zoomController = TransformationController();
  double _currentZoom = 1.0;
  Offset? _hoveredPointerPosition;
  late bool _autoSortByClip;

  late TextEditingController _chapterController;
  late TextEditingController _sceneController;
  late TextEditingController _planeController;
  late TextEditingController _takeController;
  late TextEditingController _notesController;
  bool _isMos = false;
  bool _isSaving = false;

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

    try {
      if (widget.customPlayer != null) {
        _player = widget.customPlayer!;
        _controller = widget.customVideoController ?? VideoController(_player!);
      } else {
        _player = Player();
        _controller = VideoController(_player!);
        _ownsPlayer = true;
        if (widget.playlist.isNotEmpty) {
          final filePath = widget.playlist[_currentIndex].originalFilePath;
          if (filePath != null) {
            _player!.open(Media(filePath));
          }
        }
      }

      _player!.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });

      _player!.stream.position.listen((pos) {
        if (mounted && !_isDraggingSlider) {
          setState(() => _position = pos);
        }
      });

      _player!.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      });

      _player!.stream.volume.listen((vol) {
        if (mounted) {
          setState(() {
            _volume = vol;
            _isMuted = vol <= 0.0;
          });
        }
      });
    } catch (e) {
      debugPrint('Error initializing player: $e');
    }
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
    final currentTranslationOffset = Offset(currentTranslation.x, currentTranslation.y);

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
    _zoomTo(currentScale * 1.3, focalPoint: focalPoint ?? _hoveredPointerPosition);
  }

  void _zoomOut({Offset? focalPoint}) {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    _zoomTo(currentScale / 1.3, focalPoint: focalPoint ?? _hoveredPointerPosition);
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    if (event.logicalKey == LogicalKeyboardKey.pageDown ||
        ((isCtrl || isAlt) && event.logicalKey == LogicalKeyboardKey.arrowRight)) {
      if (_currentIndex < widget.playlist.length - 1) {
        _goToClip(_currentIndex + 1);
        return true;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.pageUp ||
        ((isCtrl || isAlt) && event.logicalKey == LogicalKeyboardKey.arrowLeft)) {
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
      try {
        _player?.open(Media(newProposal.originalFilePath!));
      } catch (_) {}
    }

    setState(() {
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
          final prevChapter = prevState?.chapter ?? _chapterController.text.trim();
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Lote completado con éxito! Se inspeccionaron todos los clips.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
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

  String _getLiveConventionName() {
    if (widget.playlist.isEmpty) return '—';
    final p = widget.playlist[_currentIndex];
    final ext = p.originalFilePath != null ? p_path.extension(p.originalFilePath!) : '';

    final scene = _sceneController.text.trim();
    final plane = _planeController.text.trim();
    final take = _takeController.text.trim();

    final fileReel = p.fileReel ?? ClipMatcherService.extractReel(p.originalFilePath ?? '');
    final defaultReel = widget.reelOverride ?? fileReel ?? p.associatedRecord?.reel ?? '';

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
          if (_currentIndex < widget.playlist.length - 1) _goToClip(_currentIndex + 1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () {
          if (_currentIndex < widget.playlist.length - 1) _goToClip(_currentIndex + 1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () {
          if (_currentIndex < widget.playlist.length - 1) _goToClip(_currentIndex + 1);
        },
        const SingleActivator(LogicalKeyboardKey.pageUp): () {
          if (_currentIndex > 0) _goToClip(_currentIndex - 1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () {
          if (_currentIndex > 0) _goToClip(_currentIndex - 1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () {
          if (_currentIndex > 0) _goToClip(_currentIndex - 1);
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _handleSaveAndNext,
        const SingleActivator(LogicalKeyboardKey.enter): _handleSaveAndNext,
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final isCtrl = HardwareKeyboard.instance.isControlPressed;
            final isAlt = HardwareKeyboard.instance.isAltPressed;

            if (event.logicalKey == LogicalKeyboardKey.space) {
              final primaryFocus = FocusManager.instance.primaryFocus;
              final isTextEditing = primaryFocus?.context?.widget is EditableText;
              if (!isTextEditing) {
                _togglePlayPause();
                return KeyEventResult.handled;
              }
            } else if (!isCtrl && !isAlt) {
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                final primaryFocus = FocusManager.instance.primaryFocus;
                final isTextEditing = primaryFocus?.context?.widget is EditableText;
                if (!isTextEditing) {
                  final target = _position - const Duration(seconds: 5);
                  _player?.seek(target < Duration.zero ? Duration.zero : target);
                  return KeyEventResult.handled;
                }
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                final primaryFocus = FocusManager.instance.primaryFocus;
                final isTextEditing = primaryFocus?.context?.widget is EditableText;
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C1C22) : const Color(0xFFF0F2F6),
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(12)),
                          border: Border(
                            bottom: BorderSide(
                              color: isDark ? const Color(0xFF2C2C36) : Colors.grey.shade300,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _currentIndex > 0 ? () => _goToClip(_currentIndex - 1) : null,
                              icon: const Icon(Icons.arrow_back_ios, size: 12),
                              label: const Text('Anterior'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Clip ${_currentIndex + 1} de ${widget.playlist.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isCurrentSaved) ...[
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: 'Toma registrada en bitácora',
                                      child: Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (tcRange.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    'TC: $tcRange',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              onPressed: _currentIndex < widget.playlist.length - 1
                                  ? () => _goToClip(_currentIndex + 1)
                                  : null,
                              icon: const Icon(Icons.arrow_forward_ios, size: 12),
                              label: const Text('Siguiente'),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                                        _zoomIn(focalPoint: pointerSignal.localPosition);
                                      } else if (pointerSignal.scrollDelta.dy > 0) {
                                        _zoomOut(focalPoint: pointerSignal.localPosition);
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
                                        _hoveredPointerPosition = event.localPosition;
                                      },
                                      onExit: (_) {
                                        _hoveredPointerPosition = null;
                                      },
                                      child: InteractiveViewer(
                                        transformationController: _zoomController,
                                        minScale: 1.0,
                                        maxScale: 5.0,
                                        panEnabled: true,
                                        scaleEnabled: true,
                                        trackpadScrollCausesScale: true,
                                        boundaryMargin: const EdgeInsets.all(600),
                                        clipBehavior: Clip.none,
                                        child: Center(
                                          child: AspectRatio(
                                            aspectRatio: 16 / 9,
                                            child: _controller != null
                                                ? Video(
                                                    controller: _controller!,
                                                    controls: NoVideoControls,
                                                  )
                                                : Container(
                                                    color: Colors.black87,
                                                    child: const Center(
                                                      child: Text(
                                                        'Vista previa de video',
                                                        style: TextStyle(color: Colors.white70, fontSize: 13),
                                                      ),
                                                    ),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.zoom_out, size: 16, color: Colors.white),
                                        tooltip: 'Alejar (Ctrl -)',
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(),
                                        onPressed: _currentZoom > 1.05 ? _zoomOut : null,
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
                                        icon: const Icon(Icons.zoom_in, size: 16, color: Colors.white),
                                        tooltip: 'Acercar (Ctrl +)',
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(),
                                        onPressed: _currentZoom < 4.95 ? _zoomIn : null,
                                      ),
                                      if (_currentZoom > 1.05) ...[
                                        Container(
                                          height: 16,
                                          width: 1,
                                          color: Colors.white24,
                                          margin: const EdgeInsets.symmetric(horizontal: 4),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.restart_alt, size: 16, color: Colors.white),
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1C1C22) : const Color(0xFFF7F8FA),
                          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12)),
                          border: Border(
                            top: BorderSide(
                              color: isDark ? const Color(0xFF2C2C36) : Colors.grey.shade300,
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                              ),
                              child: Slider(
                                value: _isDraggingSlider
                                    ? _dragSliderValue
                                    : (_duration.inMilliseconds > 0
                                        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                                        : 0.0),
                                onChanged: (val) {
                                  setState(() {
                                    _isDraggingSlider = true;
                                    _dragSliderValue = val;
                                  });
                                },
                                onChangeEnd: (val) {
                                  final targetMs = (val * _duration.inMilliseconds).round();
                                  _player?.seek(Duration(milliseconds: targetMs));
                                  setState(() {
                                    _isDraggingSlider = false;
                                    _position = Duration(milliseconds: targetMs);
                                  });
                                },
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                                  tooltip: _isPlaying ? 'Pausar (Espacio)' : 'Reproducir (Espacio)',
                                  onPressed: _togglePlayPause,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.replay_5),
                                  tooltip: 'Retroceder 5s (←)',
                                  onPressed: () {
                                    final target = _position - const Duration(seconds: 5);
                                    _player?.seek(target < Duration.zero ? Duration.zero : target);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.forward_5),
                                  tooltip: 'Avanzar 5s (→)',
                                  onPressed: () {
                                    final target = _position + const Duration(seconds: 5);
                                    _player?.seek(target > _duration ? _duration : target);
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
                                  icon: Icon(_isMuted || _volume <= 0.0
                                      ? Icons.volume_off
                                      : (_volume < 50 ? Icons.volume_down : Icons.volume_up)),
                                  tooltip: _isMuted ? 'Activar sonido' : 'Silenciar',
                                  onPressed: _toggleMute,
                                ),
                                SizedBox(
                                  width: 80,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
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
                    color: isDark ? const Color(0xFF1A1A20) : const Color(0xFFFAFAFC),
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                    border: Border(
                      left: BorderSide(
                        color: isDark ? const Color(0xFF2C2C36) : Colors.grey.shade300,
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
                          color: isDark ? const Color(0xFF24242E) : const Color(0xFFEDF2F7),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isDark ? const Color(0xFF383848) : Colors.grey.shade300,
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
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'CONVENCIÓN EN TIEMPO REAL',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.copy_rounded, size: 16),
                                      tooltip: 'Copiar nombre propuesto',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        final text = _getLiveConventionName();
                                        Clipboard.setData(ClipboardData(text: text));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Copiado: $text'),
                                            duration: const Duration(seconds: 1),
                                          ),
                                        );
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
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                          title: const Text('MOS (Mudo)', style: TextStyle(fontSize: 13)),
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
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                            message: 'Ubica automáticamente la toma según el número de clip',
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF282834) : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Reel: ${currentProposal.fileReel ?? widget.reelOverride ?? "—"}',
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF282834) : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Cámara: ${widget.activeCamera} · Clip: ${ClipMatcherService.extractClipNumber(filename)}',
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                ),
                              ),
                              if (tcRange.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF282834) : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'TC: $tcRange',
                                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
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
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check_circle_outline, size: 18),
                            label: Text(
                              _currentIndex < widget.playlist.length - 1
                                  ? (isCurrentSaved ? 'Actualizar y Siguiente (Enter ➔)' : 'Guardar y Siguiente (Enter ➔)')
                                  : (isCurrentSaved ? 'Actualizar y Finalizar (Enter ➔)' : 'Guardar y Finalizar (Enter ➔)'),
                              style: const TextStyle(fontWeight: FontWeight.bold),
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
