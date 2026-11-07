import 'package:renombrata/src/ui/dialogs/folder_ingestion_dialog.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/services/bitacora_parser_service.dart';
import 'package:renombrata/src/services/rtf_bitacora_parser_service.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/services/clip_matcher_service.dart';
import 'package:renombrata/src/services/rename_service.dart';
import 'package:renombrata/src/services/report_export_service.dart';
import 'package:renombrata/src/services/project_service.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/app_settings.dart';
import 'package:renombrata/src/services/settings_service.dart';
import 'package:renombrata/src/ui/settings_dialog.dart';
import 'package:renombrata/src/ui/bitacora_editor_tab.dart';
import 'package:renombrata/src/ui/conflict_resolver_dialog.dart';
import 'package:renombrata/src/ui/media_preview_dialog.dart';
import 'package:renombrata/src/utils/media_proxy_utils.dart';
import 'package:path/path.dart' as p;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter/gestures.dart';
import 'package:renombrata/src/utils/timecode_formatter.dart';
import 'package:renombrata/src/services/pages_converter_service.dart';
import 'package:renombrata/src/ui/quick_paste_convention_dialog.dart';
import 'package:renombrata/src/services/convention_generator_service.dart';
import 'package:renombrata/src/services/convention_name_generator.dart';
import 'package:renombrata/src/ui/widgets/line_numbered_text_field.dart';
import 'package:renombrata/src/ui/dialogs/take_linker_dialog.dart';
import 'package:renombrata/src/ui/dialogs/sony_m01_confirmation_dialog.dart';
import 'package:renombrata/src/services/still_capture_service.dart';
import 'package:renombrata/src/utils/frame_step_utils.dart';
import '../../main.dart';

class HomeScreen extends StatefulWidget {
  final RenombrataProject? initialProject;
  final DryRunReport? initialReport;
  final Player? customStudioPlayer;
  final VideoController? customStudioVideoController;
  final bool? initialStudioMode;
  final AppSettings? initialSettings;

  const HomeScreen({
    super.key,
    this.initialProject,
    this.initialReport,
    this.customStudioPlayer,
    this.customStudioVideoController,
    this.initialStudioMode,
    this.initialSettings,
  });

  static String computeLiveSmpte(
    Duration position,
    String? baseTcIn,
    String frameRate,
  ) {
    final fps = TimecodeUtils.getFpsInt(frameRate);
    int baseFrames = 0;
    if (baseTcIn != null && baseTcIn.trim().isNotEmpty) {
      final parts = baseTcIn
          .trim()
          .split(':')
          .map((p) => int.tryParse(p) ?? 0)
          .toList();
      if (parts.length >= 4) {
        final h = parts[0];
        final m = parts[1];
        final s = parts[2];
        final f = parts[3];
        baseFrames = ((h * 3600) + (m * 60) + s) * fps + f;
      }
    }

    final elapsedFrames = ((position.inMicroseconds / 1000000.0) * fps).floor();
    final totalFrames = baseFrames + elapsedFrames;
    final totalSeconds = totalFrames ~/ fps;
    final frame = totalFrames % fps;
    final hours = (totalSeconds ~/ 3600) % 24;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}:${frame.toString().padLeft(2, '0')}';
  }

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _ConventionLineStatus {
  final int lineNumber;
  final String text;
  final IconData icon;
  final Color color;
  final String? targetFilePath;

  const _ConventionLineStatus({
    required this.lineNumber,
    required this.text,
    required this.icon,
    required this.color,
    this.targetFilePath,
  });
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  RenombrataProject _project = RenombrataProject(
    log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
    defaultReel: '001',
    activeCamera: 'A',
  );

  AppSettings _appSettings = AppSettings.defaults();

  @visibleForTesting
  AppSettings get appSettings => _appSettings;

  @visibleForTesting
  set appSettings(AppSettings s) => _appSettings = s;

  bool _isCapturingStill = false;
  final ValueNotifier<bool> _studioShutterFlashNotifier =
      ValueNotifier<bool>(false);
  Timer? _studioShutterTimer;

  @visibleForTesting
  RenombrataProject get project => _project;

  String? _projectPath;
  bool _isDirty = false;

  String? _mediaFolderPath;
  List<ScannedFile>? _explicitScannedFiles;
  bool _renameMetadata = true;

  DryRunReport? _report;
  DryRunReport? _baseReport;
  bool _isLoading = false;
  List<Map<String, dynamic>> _renameHistory = [];
  Map<String, String?> _manualOverrides = {};
  String? _selectedReelFilter;
  bool _isDragging = false;

  String? _notificationMessage;
  bool _isNotificationError = false;
  Timer? _notificationTimer;

  DryRunReport? _previousReportBeforePaste;

  bool _isStudioMode = true;
  RenameProposal? _selectedStudioClip;
  Player? _studioPlayer;
  VideoController? _studioVideoController;
  final ValueNotifier<bool> _studioIsPlayingNotifier = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<Duration> _studioPositionNotifier =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> _studioDurationNotifier =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<double> _studioVolumeNotifier = ValueNotifier<double>(
    100.0,
  );
  final ValueNotifier<bool> _studioIsMutedNotifier = ValueNotifier<bool>(false);
  double _studioPreMuteVolume = 100.0;
  bool _studioIsDraggingSlider = false;
  double _studioDragSliderValue = 0.0;

  final TransformationController _studioZoomController =
      TransformationController();
  double _studioCurrentZoom = 1.0;
  Offset? _studioHoveredPointerPosition;

  TransformationController get studioZoomController => _studioZoomController;
  double get studioCurrentZoom => _studioCurrentZoom;
  ValueNotifier<Duration> get studioPositionNotifier => _studioPositionNotifier;
  ValueNotifier<Duration> get studioDurationNotifier => _studioDurationNotifier;
  ValueNotifier<bool> get studioIsPlayingNotifier => _studioIsPlayingNotifier;

  @visibleForTesting
  VideoController? get studioVideoController => _studioVideoController;

  @visibleForTesting
  set studioVideoController(VideoController? controller) {
    _studioVideoController = controller;
  }

  @visibleForTesting
  Player? get studioPlayer => _studioPlayer;

  @visibleForTesting
  set studioPlayer(Player? player) {
    _studioPlayer = player;
  }

  final List<StreamSubscription> _studioSubscriptions = [];

  @visibleForTesting
  List<StreamSubscription> get studioSubscriptions => _studioSubscriptions;

  @visibleForTesting
  void selectStudioClip(RenameProposal p) => _selectStudioClip(p);

  final TextEditingController _studioChapterController =
      TextEditingController();
  final TextEditingController _studioSceneController = TextEditingController();
  final TextEditingController _studioPlaneController = TextEditingController();
  final TextEditingController _studioTakeController = TextEditingController();
  final TextEditingController _studioReelController = TextEditingController();
  final TextEditingController _studioNotesController = TextEditingController();
  String? _lastSelectedReel;
  bool _studioIsMos = false;
  bool _studioIsTf = false;
  Timer? _studioSaveDebounceTimer;
  bool _isStudioSaving = false;
  bool _isStudioPendingSave = false;
  @visibleForTesting
  bool get isStudioPendingSave => _isStudioPendingSave;
  Duration _lastStudioPlaybackPosition = Duration.zero;
  double? _userStudioMediaWidth;
  double? _userStudioConventionWidth;
  final ValueNotifier<bool> _studioActiveIsProxyNotifier = ValueNotifier<bool>(
    true,
  );
  final ValueNotifier<String?> _studioLinkedProxyPathNotifier =
      ValueNotifier<String?>(null);
  final ValueNotifier<String?> _studioPlaybackErrorNotifier =
      ValueNotifier<String?>(null);

  ValueNotifier<bool> get studioActiveIsProxyNotifier =>
      _studioActiveIsProxyNotifier;
  ValueNotifier<String?> get studioLinkedProxyPathNotifier =>
      _studioLinkedProxyPathNotifier;
  ValueNotifier<String?> get studioPlaybackErrorNotifier =>
      _studioPlaybackErrorNotifier;

  final FocusNode _conventionEditorFocusNode = FocusNode(
    debugLabel: 'conventionEditor',
  );
  final FocusNode _studioChapterFocusNode = FocusNode(
    debugLabel: 'studioChapter',
  );
  final FocusNode _studioSceneFocusNode = FocusNode(debugLabel: 'studioScene');
  final FocusNode _studioTakeFocusNode = FocusNode(debugLabel: 'studioTake');
  final FocusNode _studioPlaneFocusNode = FocusNode(debugLabel: 'studioPlane');
  final FocusNode _studioReelFocusNode = FocusNode(debugLabel: 'studioReel');
  final FocusNode _studioNotesFocusNode = FocusNode(debugLabel: 'studioNotes');
  final FocusNode _studioWorkspaceFocusNode = FocusNode(
    debugLabel: 'studioWorkspace',
  );
  final FocusNode _studioMediaListFocusNode = FocusNode(
    debugLabel: 'studioMediaList',
  );
  final FocusNode _studioInspectorFocusNode = FocusNode(
    debugLabel: 'studioInspector',
  );
  final FocusNode _conventionEditorPanelFocusNode = FocusNode(
    debugLabel: 'conventionEditorPanel',
  );

  @visibleForTesting
  FocusNode get studioWorkspaceFocusNode => _studioWorkspaceFocusNode;

  @visibleForTesting
  FocusNode get studioMediaListFocusNode => _studioMediaListFocusNode;

  @visibleForTesting
  FocusNode get studioInspectorFocusNode => _studioInspectorFocusNode;

  @visibleForTesting
  FocusNode get conventionEditorPanelFocusNode =>
      _conventionEditorPanelFocusNode;

  @visibleForTesting
  FocusNode get conventionEditorFocusNode => _conventionEditorFocusNode;

  @visibleForTesting
  FocusNode get studioChapterFocusNode => _studioChapterFocusNode;

  @visibleForTesting
  FocusNode get studioSceneFocusNode => _studioSceneFocusNode;

  @visibleForTesting
  FocusNode get studioTakeFocusNode => _studioTakeFocusNode;

  @visibleForTesting
  FocusNode get studioPlaneFocusNode => _studioPlaneFocusNode;

  @visibleForTesting
  FocusNode get studioReelFocusNode => _studioReelFocusNode;

  @visibleForTesting
  FocusNode get studioNotesFocusNode => _studioNotesFocusNode;

  @visibleForTesting
  void focusFirstVisibleSlateField() => _focusFirstVisibleSlateField();

  @visibleForTesting
  void toggleStudioPlay() => _toggleStudioPlay();

  @visibleForTesting
  void seekStudioRelative(int seconds) => _seekStudioRelative(seconds);

  @visibleForTesting
  void selectPreviousStudioClip() => _selectPreviousStudioClip();

  @visibleForTesting
  void selectNextStudioClip() => _selectNextStudioClip();

  @visibleForTesting
  ({double mediaWidth, double conventionWidth}) calculateStudioPaneWidths(
    double totalWidth,
  ) {
    if (totalWidth <= 1250) {
      final t = ((totalWidth - 1100.0) / 150.0).clamp(0.0, 1.0);
      final media = 280.0 + (330.0 - 280.0) * t;
      final conv = 310.0 + (360.0 - 310.0) * t;
      return (mediaWidth: media, conventionWidth: conv);
    }
    final centerTarget = (totalWidth * 0.44).clamp(680.0, 850.0);
    final remainder = totalWidth - centerTarget - 24.0;
    final mediaWidth = (remainder * 0.42).clamp(340.0, 520.0);
    final conventionWidth = (remainder - mediaWidth).clamp(380.0, 600.0);
    return (mediaWidth: mediaWidth, conventionWidth: conventionWidth);
  }

  @visibleForTesting
  bool get isStudioMode => _isStudioMode;

  @visibleForTesting
  RenameProposal? get selectedStudioClip => _selectedStudioClip;

  @visibleForTesting
  List<RenameProposal> get studioMediaClips => _studioMediaClips;

  @visibleForTesting
  DryRunReport? get previousReportBeforePaste => _previousReportBeforePaste;

  @visibleForTesting
  set previousReportBeforePaste(DryRunReport? value) =>
      _previousReportBeforePaste = value;

  @visibleForTesting
  DryRunReport? get report => _report;

  @visibleForTesting
  bool get studioIsMos => _studioIsMos;

  @visibleForTesting
  bool get studioIsTf => _studioIsTf;

  @visibleForTesting
  bool get studioIsDs => false;

  @visibleForTesting
  bool get studioIsFf => false;

  @visibleForTesting
  bool get studioIsGpr => false;

  @visibleForTesting
  bool get studioIsDr => false;

  @visibleForTesting
  TextEditingController get studioChapterController => _studioChapterController;

  @visibleForTesting
  TextEditingController get studioSceneController => _studioSceneController;

  @visibleForTesting
  TextEditingController get studioPlaneController => _studioPlaneController;

  @visibleForTesting
  TextEditingController get studioTakeController => _studioTakeController;

  @visibleForTesting
  TextEditingController get studioReelController => _studioReelController;

  @visibleForTesting
  TextEditingController get studioNotesController => _studioNotesController;

  @visibleForTesting
  TextEditingController get conventionEditorController =>
      _conventionEditorController;

  @visibleForTesting
  UndoHistoryController get conventionEditorUndoController =>
      _conventionEditorUndoController;

  @visibleForTesting
  void onConventionTextChanged(String text) => _onConventionTextChanged(text);

  @visibleForTesting
  Map<String, String> get livePastedOverrides => _livePastedOverrides;

  @visibleForTesting
  void updateProject(RenombrataProject newProject) =>
      _updateProject(newProject);

  @visibleForTesting
  List<RenameProposal> get reportProposals => _report?.proposals ?? [];

  @visibleForTesting
  Future<void> checkAndSyncTimecodes(DryRunReport report) =>
      _checkAndSyncTimecodes(report);

  final TextEditingController _reelController = TextEditingController(
    text: '001',
  );
  final ScrollController _horizontalTableScrollController = ScrollController();
  final ScrollController _verticalTableScrollController = ScrollController();
  final ScrollController _studioMediaListScrollController = ScrollController();
  final ScrollController _conventionLineStatusScrollController =
      ScrollController();
  bool _showConventionEditorPane = false;
  final TextEditingController _conventionEditorController =
      TextEditingController();
  final UndoHistoryController _conventionEditorUndoController =
      UndoHistoryController();
  Map<String, String> _livePastedOverrides = {};
  Map<String, int> _livePastedLineNumbers = {};
  Map<String, String> _duplicateClipConflicts = {};
  final Set<String> _resolvedConflictPaths = {};
  bool _filterOnlyConventionMatches = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialStudioMode != null) {
      _isStudioMode = widget.initialStudioMode!;
    }
    if (widget.initialProject != null) {
      _project = widget.initialProject!;
    }
    if (widget.initialReport != null) {
      _report = widget.initialReport;
      if (_isStudioMode && _selectedStudioClip == null) {
        final clips =
            _report!.proposals.where((p) => !p.isCompanionFile).toList();
        if (clips.isNotEmpty) {
          _selectedStudioClip = clips.first;
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _evaluateConventionMatches();
      });
    }
    if (widget.initialSettings != null) {
      _appSettings = widget.initialSettings!;
    }
    _reelController.text = _project.defaultReel;
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0) {
        if (_appSettings.pauseVideoOnTabSwitch) {
          _studioPlayer?.pause();
          _studioIsPlayingNotifier.value = false;
        }
      } else if (_tabController.index == 1) {
        _restoreStudioPlayerIfNeeded();
      }
    });
    _studioMediaListFocusNode.addListener(_onStudioFocusChanged);
    _studioInspectorFocusNode.addListener(_onStudioFocusChanged);
    _conventionEditorPanelFocusNode.addListener(_onStudioFocusChanged);
    _conventionEditorFocusNode.addListener(_onStudioFocusChanged);
    if (widget.customStudioPlayer != null) {
      _initStudioPlayer();
    }
    SettingsService.loadSettings().then((s) {
      if (mounted && widget.initialSettings == null) {
        setState(() {
          _appSettings = s;
        });
      }
    });
  }

  void _onStudioFocusChanged() {
    if (mounted) setState(() {});
  }

  void _initStudioPlayer() {
    for (final sub in _studioSubscriptions) {
      sub.cancel();
    }
    _studioSubscriptions.clear();

    try {
      if (widget.customStudioPlayer != null) {
        _studioPlayer = widget.customStudioPlayer;
        if (widget.customStudioVideoController != null) {
          _studioVideoController = widget.customStudioVideoController;
        } else {
          try {
            _studioVideoController = VideoController(_studioPlayer!);
          } catch (_) {
            _studioVideoController = null;
          }
        }
      } else {
        _studioPlayer = Player();
        _studioVideoController = VideoController(
          _studioPlayer!,
          configuration: const VideoControllerConfiguration(
            enableHardwareAcceleration: true,
          ),
        );
      }
      try {
        _studioSubscriptions.add(
          _studioPlayer!.stream.tracks.listen((tracks) {
            if (_selectedStudioClip != null) {
              final path = _selectedStudioClip!.originalFilePath;
              if (path != null) {
                final proxy = _studioLinkedProxyPathNotifier.value;
                final useProxy =
                    proxy != null && _studioActiveIsProxyNotifier.value;
                if (!useProxy && MediaProxyUtils.isCanonRaw(path)) {
                  try {
                    final platform = _studioPlayer?.platform;
                    if (platform != null) {
                      try {
                        (platform as dynamic).setProperty('vid', 'no');
                      } catch (_) {}
                    }
                  } catch (_) {}
                  try {
                    _studioPlayer?.setVideoTrack(VideoTrack.no());
                  } catch (_) {}
                  try {
                    _studioPlayer?.setVolume(100.0);
                  } catch (_) {}
                }
              }
            }
          }),
        );
      } catch (_) {}
      _studioSubscriptions.add(
        _studioPlayer!.stream.playing.listen((p) {
          if (mounted) _studioIsPlayingNotifier.value = p;
        }),
      );
      _studioSubscriptions.add(
        _studioPlayer!.stream.position.listen((pos) {
          if (mounted && !_studioIsDraggingSlider) {
            _studioPositionNotifier.value = pos;
          }
        }),
      );
      _studioSubscriptions.add(
        _studioPlayer!.stream.duration.listen((dur) {
          if (mounted) _studioDurationNotifier.value = dur;
        }),
      );
      _studioSubscriptions.add(
        _studioPlayer!.stream.volume.listen((vol) {
          if (mounted) {
            _studioVolumeNotifier.value = vol;
            _studioIsMutedNotifier.value = vol <= 0.0;
          }
        }),
      );
      _studioSubscriptions.add(_studioPlayer!.stream.log.listen((_) {}));
      _studioSubscriptions.add(
        _studioPlayer!.stream.error.listen((err) {
          if (mounted) {
            _studioPlaybackErrorNotifier.value = err;
            setState(() {});
          }
        }),
      );
    } catch (e) {
      debugPrint('Studio player init skipped: $e');
      _studioPlayer = null;
      _studioVideoController = null;
    }
  }

  void _resetStudioZoom() {
    _studioZoomController.value = Matrix4.identity();
    if (mounted) {
      setState(() => _studioCurrentZoom = 1.0);
    }
  }

  void _studioZoomTo(double targetScale, {Offset? focalPoint}) {
    final currentScale = _studioZoomController.value.getMaxScaleOnAxis();
    final clampedScale = targetScale.clamp(1.0, 5.0);
    if ((clampedScale - currentScale).abs() < 0.005) return;

    if (clampedScale <= 1.05) {
      _resetStudioZoom();
      return;
    }

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final defaultFocal = box != null
        ? Offset(box.size.width / 2, box.size.height / 2)
        : const Offset(400, 225);
    final focal = focalPoint ?? defaultFocal;

    final currentTranslation = _studioZoomController.value.getTranslation();
    final currentTranslationOffset = Offset(
      currentTranslation.x,
      currentTranslation.y,
    );

    final contentPoint = (focal - currentTranslationOffset) / currentScale;
    final newTranslationOffset = focal - (contentPoint * clampedScale);

    final matrix = Matrix4.identity()
      ..translate(newTranslationOffset.dx, newTranslationOffset.dy)
      ..scale(clampedScale);

    _studioZoomController.value = matrix;
    if (mounted) {
      setState(() => _studioCurrentZoom = clampedScale);
    }
  }

  void _studioZoomIn({Offset? focalPoint}) {
    final currentScale = _studioZoomController.value.getMaxScaleOnAxis();
    _studioZoomTo(
      currentScale * 1.3,
      focalPoint: focalPoint ?? _studioHoveredPointerPosition,
    );
  }

  void _studioZoomOut({Offset? focalPoint}) {
    final currentScale = _studioZoomController.value.getMaxScaleOnAxis();
    _studioZoomTo(
      currentScale / 1.3,
      focalPoint: focalPoint ?? _studioHoveredPointerPosition,
    );
  }

  String _computeLiveSmpte(
    Duration position,
    String? baseTcIn,
    String frameRate,
  ) => HomeScreen.computeLiveSmpte(position, baseTcIn, frameRate);

  void _openSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => SettingsDialog(
        currentSettings: _appSettings,
        onSettingsChanged: (newSettings) {
          setState(() {
            _appSettings = newSettings;
          });
        },
        project: _project,
        onProjectChanged: _updateProject,
      ),
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    // Safely halt active native Direct3D rendering before hot restart isolate teardown
    try {
      _studioPlayer?.pause();
    } catch (_) {}
  }

  void _disposeStudioPlayer() {
    for (final sub in _studioSubscriptions) {
      sub.cancel();
    }
    _studioSubscriptions.clear();
    try {
      if (_studioPositionNotifier.value > Duration.zero) {
        _lastStudioPlaybackPosition = _studioPositionNotifier.value;
      }
      _studioPlayer?.pause();
      _studioVideoController = null;
      _studioPlayer?.dispose();
      _studioPlayer = null;
    } catch (e) {
      debugPrint('Error disposing studio player: $e');
    }
  }

  void _playStudioMedia(
    String path, {
    Duration? seekPosition,
    bool forceDirectMaster = false,
  }) {
    final proxy = MediaProxyUtils.findLinkedProxyPath(path);
    _studioLinkedProxyPathNotifier.value = proxy;

    final bool useProxy =
        proxy != null &&
        _studioActiveIsProxyNotifier.value &&
        !forceDirectMaster;
    final String mediaToPlay = useProxy ? proxy : path;
    final bool isCrmDirect = MediaProxyUtils.isCanonRaw(mediaToPlay);

    if (_studioPlayer == null) {
      _initStudioPlayer();
    }

    try {
      final platform = _studioPlayer?.platform;
      if (isCrmDirect) {
        if (platform != null) {
          try {
            (platform as dynamic).setProperty('vid', 'no');
          } catch (_) {}
        }
        try {
          _studioPlayer?.setVideoTrack(VideoTrack.no());
        } catch (_) {}
      } else {
        if (platform != null) {
          try {
            (platform as dynamic).setProperty('vid', 'auto');
          } catch (_) {}
        }
        try {
          _studioPlayer?.setVideoTrack(VideoTrack.auto());
        } catch (_) {}
      }
    } catch (_) {}

    try {
      _studioPlayer?.open(Media(mediaToPlay)).then((_) {
        if (isCrmDirect) {
          try {
            final platform = _studioPlayer?.platform;
            if (platform != null) {
              try {
                (platform as dynamic).setProperty('vid', 'no');
              } catch (_) {}
            }
          } catch (_) {}
          try {
            _studioPlayer?.setVideoTrack(VideoTrack.no());
          } catch (_) {}
          try {
            _studioPlayer?.setVolume(100.0);
          } catch (_) {}
        }
        if (seekPosition != null && seekPosition > Duration.zero) {
          _studioPlayer?.seek(seekPosition);
        }
      });
    } catch (e) {
      debugPrint('Error playing studio media: $e');
    }
  }

  void _restoreStudioPlayerIfNeeded() {
    if (_selectedStudioClip == null) return;
    final path = _selectedStudioClip!.originalFilePath;
    if (path == null || !_isPlayableVideo(path)) return;

    if (!File(path).existsSync() && !path.startsWith('/media/')) return;

    _playStudioMedia(path, seekPosition: _lastStudioPlaybackPosition);
  }

  @override
  void dispose() {
    _studioShutterTimer?.cancel();
    _studioShutterFlashNotifier.dispose();
    _studioSaveDebounceTimer?.cancel();
    _disposeStudioPlayer();
    _tabController.dispose();

    _reelController.dispose();
    _horizontalTableScrollController.dispose();
    _verticalTableScrollController.dispose();
    _studioMediaListScrollController.dispose();
    _conventionLineStatusScrollController.dispose();
    _studioMediaListFocusNode.removeListener(_onStudioFocusChanged);
    _studioInspectorFocusNode.removeListener(_onStudioFocusChanged);
    _conventionEditorPanelFocusNode.removeListener(_onStudioFocusChanged);
    _conventionEditorFocusNode.removeListener(_onStudioFocusChanged);
    _studioMediaListFocusNode.dispose();
    _studioInspectorFocusNode.dispose();
    _conventionEditorPanelFocusNode.dispose();
    _studioWorkspaceFocusNode.dispose();
    _studioChapterFocusNode.dispose();
    _studioSceneFocusNode.dispose();
    _studioPlaneFocusNode.dispose();
    _studioTakeFocusNode.dispose();
    _studioReelFocusNode.dispose();
    _studioNotesFocusNode.dispose();
    _conventionEditorController.dispose();
    _conventionEditorUndoController.dispose();
    _conventionEditorFocusNode.dispose();
    _studioZoomController.dispose();
    _studioPositionNotifier.dispose();
    _studioDurationNotifier.dispose();
    _studioIsPlayingNotifier.dispose();
    _studioVolumeNotifier.dispose();
    _studioIsMutedNotifier.dispose();
    _studioActiveIsProxyNotifier.dispose();
    _studioLinkedProxyPathNotifier.dispose();
    _studioPlaybackErrorNotifier.dispose();
    _studioChapterController.dispose();
    _studioSceneController.dispose();
    _studioPlaneController.dispose();
    _studioTakeController.dispose();
    _studioReelController.dispose();
    _studioNotesController.dispose();
    _notificationTimer?.cancel();
    super.dispose();
  }

  String _computeDefaultReel(String camera) {
    final effectiveCam = camera.toUpperCase() == 'ALL'
        ? (_project.cameraNames.isNotEmpty ? _project.cameraNames.first : 'A')
        : camera;
    if (_project.log.records.isEmpty) return '${effectiveCam}001';

    String baseReel = '';
    for (var r in _project.log.records) {
      if (r.reel.trim().isNotEmpty) {
        baseReel = r.reel.trim();
        break;
      }
    }

    if (baseReel.isEmpty) return '${effectiveCam}001';

    final letterMatch = RegExp(r'^([A-Za-z])(\d+.*)$').firstMatch(baseReel);
    if (letterMatch != null) {
      return '$effectiveCam${letterMatch.group(2)}';
    } else {
      final numericMatch = RegExp(r'^(\d+.*)$').firstMatch(baseReel);
      if (numericMatch != null) {
        return '$effectiveCam$baseReel';
      }
    }
    return baseReel;
  }

  void _regenerateConventionLines() {
    final clips = _studioMediaClips;
    if (clips.isEmpty) return;

    final selClip = _selectedStudioClip;
    final existingLines = _conventionEditorController.text.split('\n');
    if (_project.log.records.isEmpty &&
        _conventionEditorController.text.trim().isEmpty &&
        (selClip == null || !_isStudioSlateModified(selClip))) {
      return;
    }

    final newLines = <String>[];
    for (int i = 0; i < clips.length; i++) {
      final clip = clips[i];
      final clipIndex = i + 1;
      final rec = clip.associatedRecord;

      final isCurrentSelected =
          _selectedStudioClip?.originalFilePath == clip.originalFilePath;
      final hadLine =
          i < existingLines.length && existingLines[i].trim().isNotEmpty;
      if (rec == null &&
          !(isCurrentSelected && _isStudioSlateModified(clip)) &&
          !hadLine) {
        newLines.add('');
        continue;
      }

      final chapter =
          isCurrentSelected && _studioChapterController.text.trim().isNotEmpty
          ? _studioChapterController.text.trim()
          : (rec?.chapter ?? '');
      final scene =
          isCurrentSelected && _studioSceneController.text.trim().isNotEmpty
          ? _studioSceneController.text.trim()
          : (rec?.scene ?? '');
      final plane =
          isCurrentSelected && _studioPlaneController.text.trim().isNotEmpty
          ? _studioPlaneController.text.trim()
          : rec?.plane;
      final take =
          isCurrentSelected && _studioTakeController.text.trim().isNotEmpty
          ? _studioTakeController.text.trim()
          : (rec?.take.isNotEmpty == true ? rec!.take : '1');
      final reel =
          isCurrentSelected && _studioReelController.text.trim().isNotEmpty
          ? _studioReelController.text.trim()
          : (rec?.reel.isNotEmpty == true
                ? rec!.reel
                : (_getProposalReel(clip).isNotEmpty
                      ? _getProposalReel(clip)
                      : _project.defaultReel));
      final camera = _project.activeCamera;

      final conventionName = ConventionGeneratorService.generateConventionName(
        project: _project,
        chapter: chapter,
        scene: scene,
        plane: plane,
        take: take,
        reel: reel,
        camera: camera,
        clipIndex: clipIndex,
      );

      newLines.add(conventionName);
      if (clip.originalFilePath != null) {
        _livePastedOverrides[clip.originalFilePath!] = conventionName;
        _livePastedLineNumbers[clip.originalFilePath!] = clipIndex;
      }
    }

    while (newLines.isNotEmpty && newLines.last.trim().isEmpty) {
      newLines.removeLast();
    }
    _conventionEditorController.text = newLines.join('\n');
    _evaluateConventionMatches();
  }

  void _updateProject(RenombrataProject newProject) {
    setState(() {
      _project = newProject;
      _isDirty = true;
      if (_reelController.text != newProject.defaultReel) {
        _reelController.text = newProject.defaultReel;
      }
    });
    _regenerateConventionLines();
    // Auto-generate preview if tab is on renamer
    _generatePreview();
  }

  void _showNotification(String message, {bool isError = false}) {
    _notificationTimer?.cancel();
    setState(() {
      _notificationMessage = message;
      _isNotificationError = isError;
    });
    _notificationTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _notificationMessage = null;
        });
      }
    });
  }

  void _clearNotification() {
    _notificationTimer?.cancel();
    setState(() {
      _notificationMessage = null;
    });
  }

  Future<void> _newProject() async {
    final confirm = await _checkUnsavedChanges();
    if (!confirm) return;

    setState(() {
      _project = RenombrataProject(
        log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
        defaultReel: '001',
        activeCamera: 'A',
      );
      _projectPath = null;
      _isDirty = false;
      _reelController.text = _project.defaultReel;
      _manualOverrides = {};
      _baseReport = null;
      _selectedReelFilter = null;
    });
    _generatePreview();
  }

  Future<void> _openProject() async {
    final confirm = await _checkUnsavedChanges();
    if (!confirm) return;

    List<PlatformFile> result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['renombrata', 'json'],
    );

    if (result.isNotEmpty && result.single.path != null) {
      try {
        final project = await ProjectService.loadProject(result.single.path!);
        setState(() {
          _project = project;
          _projectPath = result.single.path!;
          _isDirty = false;
          _reelController.text = _project.defaultReel;
          _manualOverrides = {};
          _baseReport = null;
          _selectedReelFilter = null;
        });
        _generatePreview();
        if (mounted) {
          _showNotification('Proyecto cargado correctamente.');
        }
      } catch (e) {
        if (mounted) {
          _showNotification('Error al cargar proyecto: $e', isError: true);
        }
      }
    }
  }

  Future<void> _saveProject() async {
    if (_projectPath == null) {
      await _saveProjectAs();
      return;
    }

    // Save current active camera and reel to project before saving
    _project = _project.copyWith(
      activeCamera: _project.activeCamera,
      defaultReel: _reelController.text.trim(),
    );

    try {
      await ProjectService.saveProject(_project, _projectPath!);
      setState(() {
        _isDirty = false;
      });
      if (mounted) {
        _showNotification('Proyecto guardado.');
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Error al guardar: $e', isError: true);
      }
    }
  }

  Future<void> _saveProjectAs() async {
    String? outputDir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta para guardar proyecto',
    );

    if (outputDir != null) {
      String outputFile =
          '$outputDir${Platform.pathSeparator}proyecto.renombrata';
      setState(() {
        _projectPath = outputFile;
      });
      await _saveProject();
    }
  }

  Future<bool> _checkUnsavedChanges() async {
    if (!_isDirty) return true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hay cambios sin guardar'),
        content: const Text(
          '¿Desea continuar y perder los cambios no guardados?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar cambios'),
          ),
        ],
      ),
    );

    return confirm == true;
  }

  Future<void> _pickBitacora() async {
    List<PlatformFile> result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'pages', 'rtf', 'txt'],
    );

    if (result.isNotEmpty && result.single.path != null) {
      final path = result.single.path!;
      final lower = path.toLowerCase();
      if (lower.endsWith('.pages')) {
        await _handlePagesFile(path);
        return;
      }
      if (lower.endsWith('.rtf') || lower.endsWith('.txt')) {
        await _handleRtfOrTxtFile(path);
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        final file = File(path);
        final log = BitacoraParserService.parse(file);
        setState(() {
          _project = _project.copyWith(log: log);
          _isDirty = true;
          _reelController.text = _computeDefaultReel(_project.activeCamera);
          _manualOverrides = {};
          _baseReport = null;
        });
        await _generatePreview();
        if (_report != null) {
          await _checkAndSyncTimecodes(_report!);
        }
        if (mounted) {
          _showNotification('Bitácora importada correctamente.');
        }
      } catch (e) {
        setState(() {
          _report = null;
        });
        if (mounted) {
          _showNotification(
            'Error al leer la bitácora: Verifique que sea un archivo Excel válido',
            isError: true,
          );
        }
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickMediaFolder() async {
    try {
      String? selectedDirectory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Seleccionar carpeta de medios / clips',
      );

      if (selectedDirectory != null) {
        final scannedFiles = MediaScannerService.scanDirectory(
          selectedDirectory,
          searchSubdirectories: true,
        );
        if (!mounted) return;
        final result = await FolderIngestionDialog.show(
          context: context,
          folderPath: selectedDirectory,
          project: _project,
          scannedFiles: scannedFiles,
        );
        if (result == null || !mounted) return;

        await _applyFolderIngestionResult(selectedDirectory, result);
      }
    } catch (e) {
      if (mounted) {
        _showNotification(
          'Error al abrir selector de carpeta: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _applyFolderIngestionResult(
    String folderPath,
    FolderIngestionResult result,
  ) async {
    setState(() {
      _mediaFolderPath = folderPath;
      _explicitScannedFiles = null;
      _manualOverrides = {};
      _baseReport = null;

      if (result.nomenclature != null ||
          result.date != null ||
          result.unit != null) {
        final metadata = _project.log.metadata.copyWith(
          nomenclature: result.nomenclature?.isNotEmpty == true
              ? result.nomenclature!
              : _project.log.metadata.nomenclature,
          production: result.nomenclature?.isNotEmpty == true
              ? result.nomenclature!
              : _project.log.metadata.production,
          date: result.date?.isNotEmpty == true
              ? result.date!
              : _project.log.metadata.date,
          unit: result.unit?.isNotEmpty == true
              ? result.unit!
              : _project.log.metadata.unit,
        );
        _project = _project.copyWith(
          log: _project.log.copyWith(metadata: metadata),
        );
      }

      final camName = result.selectedCamera;
      final camType = result.cameraType;
      var currentCameras = List<CameraConfig>.from(
        result.updatedCameras ?? _project.cameras,
      );
      final existingIdx = currentCameras.indexWhere(
        (c) => c.name.toUpperCase() == camName.toUpperCase(),
      );
      if (existingIdx != -1) {
        currentCameras[existingIdx] = currentCameras[existingIdx].copyWith(
          type: camType,
        );
      } else {
        currentCameras.add(CameraConfig(name: camName, type: camType));
      }

      final effectiveReel = result.reel?.isNotEmpty == true
          ? result.reel!
          : _computeDefaultReel(camName);
      _project = _project.copyWith(
        cameras: currentCameras,
        activeCamera: camName,
        defaultReel: effectiveReel,
      );
      _reelController.text = effectiveReel;
      _isDirty = true;
    });

    await _generatePreview();
    if (_report != null) {
      await _checkAndSyncTimecodes(_report!);
    }
    if (mounted) {
      final folderName = p.basename(folderPath);
      final totalScanned = _report?.proposals.length ?? 0;
      _showNotification(
        'Carpeta de medios cargada: $folderName ($totalScanned clips detectados)',
      );
    }
  }

  Future<void> _generatePreview({Map<String, String?>? manualOverrides}) async {
    if (_mediaFolderPath == null) {
      if (_report == null) {
        setState(() {
          _baseReport = null;
          _renameHistory = [];
        });
      }
      return;
    }

    if (manualOverrides != null) {
      _manualOverrides = manualOverrides;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final history = await RenameService.readRenameHistory(_mediaFolderPath!);
      final scannedFiles = _explicitScannedFiles ??
          MediaScannerService.scanDirectory(
            _mediaFolderPath!,
            searchSubdirectories: true,
          );

      // Check Sony M01 metadata files if undecided
      if (_project.hasConfirmedM01Sidecars == null &&
          MediaScannerService.hasSonyM01Files(scannedFiles) &&
          mounted) {
        ScannedFile? sampleVideo;
        ScannedFile? sampleXml;
        for (final v in scannedFiles.where((f) => f.isVideo)) {
          final comp = ClipMatcherService.findCompanionXml(
            v,
            scannedFiles.where((f) => f.isXml).toList(),
            pairM01Sidecars: true,
          );
          if (comp != null && ClipMatcherService.isM01Companion(v, comp)) {
            sampleVideo = v;
            sampleXml = comp;
            break;
          }
        }
        final confirmed = await SonyM01ConfirmationDialog.show(
          context,
          sampleVideoName: sampleVideo?.basename,
          sampleXmlName: sampleXml?.basename,
        );
        if (confirmed != null && mounted) {
          _project = _project.copyWith(hasConfirmedM01Sidecars: confirmed);
          _isDirty = true;
        }
      }

      final pairM01 = _project.hasConfirmedM01Sidecars ?? false;

      final baseReport = await ClipMatcherService.matchFilesAsync(
        scannedFiles: scannedFiles,
        log: _project.log,
        targetCamera: _project.activeCamera,
        reelOverride: _reelController.text.trim().isNotEmpty
            ? _reelController.text.trim()
            : null,
        renameHistory: history,
        manualOverrides: const {},
        pairM01Sidecars: pairM01,
        cameraTypes: {
          for (final c in _project.cameras) c.name.toUpperCase(): c.type,
        },
      );

      final report = _manualOverrides.isEmpty
          ? baseReport
          : await ClipMatcherService.matchFilesAsync(
              scannedFiles: scannedFiles,
              log: _project.log,
              targetCamera: _project.activeCamera,
              reelOverride: _reelController.text.trim().isNotEmpty
                  ? _reelController.text.trim()
                  : null,
              renameHistory: history,
              manualOverrides: _manualOverrides,
              pairM01Sidecars: pairM01,
              cameraTypes: {
                for (final c in _project.cameras) c.name.toUpperCase(): c.type,
              },
            );

      setState(() {
        _baseReport = baseReport;
        _report = report;
        _renameHistory = history;
        if (_isStudioMode) {
          final clips =
              report.proposals.where((p) => !p.isCompanionFile).toList();
          if (clips.isNotEmpty &&
              (_selectedStudioClip == null ||
                  !clips.any((c) =>
                      c.originalFilePath ==
                      _selectedStudioClip!.originalFilePath))) {
            _selectedStudioClip = clips.first;
            final path = clips.first.originalFilePath;
            if (path != null && _isPlayableVideo(path)) {
              _playStudioMedia(path);
            }
          }
        }
      });
      _evaluateConventionMatches();
    } catch (e) {
      if (mounted) {
        _showNotification('Error al procesar archivos: $e', isError: true);
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _executeRename() async {
    if (_report == null || _mediaFolderPath == null) return;

    final readyCount = _report!.proposals.where((p) {
      if (p.status != ProposalStatus.ready) return false;
      if (!_renameMetadata && p.isCompanionFile) return false;
      return true;
    }).length;

    if (readyCount == 0) return;

    int faltantes = _report!.totalMissing;
    int noRegistrados = _report!.totalUnmatched;

    String extraWarning = '';
    if (faltantes > 0 || noRegistrados > 0) {
      extraWarning =
          '\n\nAviso: Existen archivos faltantes o no registrados en esta carpeta. Solo se renombrarán los $readyCount archivos listos coincidentes.';
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Confirmar renombrado de archivos?'),
        content: Text(
          'Se renombrarán $readyCount archivos en el disco. Esta acción modificará los nombres originales.$extraWarning',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar y Renombrar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await RenameService.executeRename(
        mediaFolderPath: _mediaFolderPath!,
        proposals: _report!.proposals,
        renameMetadata: _renameMetadata,
      );

      // Call _generatePreview to reload history and update UI accurately
      _manualOverrides = {};
      _baseReport = null;
      await _generatePreview();

      if (mounted) {
        _showNotification('Renombrado exitoso.');
      }
    } catch (e) {
      if (mounted) {
        final message = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : e.toString();
        _showNotification(message, isError: true);
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _openConflictResolver() async {
    if (_report == null && _baseReport == null) return;

    final reportToUse = _report ?? _baseReport!;

    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => ConflictResolverDialog(
        report: reportToUse,
        log: _project.log,
        currentOverrides: _manualOverrides,
      ),
    );

    if (result != null) {
      setState(() {
        _manualOverrides = result;
      });
      if (_project.log.records.isNotEmpty) {
        await _generatePreview(manualOverrides: _manualOverrides);
      }

      if (_report != null) {
        final updatedProposals = List<RenameProposal>.from(_report!.proposals);
        for (final entry in result.entries) {
          final filePath = entry.key;
          final assignment = entry.value;
          _resolvedConflictPaths.add(filePath);
          _duplicateClipConflicts.remove(filePath);

          final idx = updatedProposals.indexWhere(
            (p) => p.originalFilePath == filePath,
          );
          if (idx == -1) continue;

          final prop = updatedProposals[idx];
          final origExt = p.extension(filePath);
          final fn = p.basename(filePath);
          final reel = _getProposalReel(prop).toUpperCase();
          final clipNum =
              int.tryParse(ClipMatcherService.extractClipNumber(fn)) ?? 0;
          final conventionLine = _findConventionNameForClip(reel, clipNum);

          if (assignment == null) {
            updatedProposals[idx] = prop.copyWith(
              status: ProposalStatus.unmatchedClip,
            );
          } else if (assignment == '__PRIMARY__' ||
              (_project.log.records.any((r) => r.id == assignment))) {
            String targetName = conventionLine ?? prop.proposedFileName;
            if (p.extension(targetName).isEmpty && origExt.isNotEmpty) {
              targetName = '$targetName$origExt';
            }
            updatedProposals[idx] = prop.copyWith(
              proposedFileName: targetName,
              status: ProposalStatus.ready,
            );
            _updateCompanionProposals(updatedProposals, filePath, targetName);
          } else if (assignment == '__ALT__' ||
              assignment.startsWith('__ALT__:')) {
            String baseName =
                conventionLine != null && conventionLine.isNotEmpty
                ? p.basenameWithoutExtension(conventionLine)
                : p.basenameWithoutExtension(
                    prop.proposedFileName.isNotEmpty
                        ? prop.proposedFileName
                        : filePath,
                  );
            if (baseName.endsWith('_ALT')) {
              baseName = baseName.substring(0, baseName.length - 4);
            }
            final altName = '${baseName}_ALT$origExt';
            updatedProposals[idx] = prop.copyWith(
              proposedFileName: altName,
              status: ProposalStatus.ready,
            );
            _updateCompanionProposals(updatedProposals, filePath, altName);
          }
        }
        setState(() {
          _report = DryRunReport(proposals: updatedProposals);
        });
      }

      _evaluateConventionMatches();
      _showNotification('Conflicto resuelto correctamente');
    }
  }

  String _getProposalReel(RenameProposal p) {
    if (p.fileReel != null && p.fileReel!.trim().isNotEmpty) {
      return p.fileReel!.trim();
    }
    if (p.associatedRecord?.reel != null &&
        p.associatedRecord!.reel.trim().isNotEmpty) {
      return p.associatedRecord!.reel.trim();
    }
    if (p.originalFilePath != null) {
      final extracted = ClipMatcherService.extractReel(p.originalFilePath!);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
    }
    return 'A001';
  }

  void _onConventionTextChanged(String text) {
    _syncConventionEditorToBitacora(text);
    _evaluateConventionMatches();
  }

  void _syncConventionEditorToBitacora(String text) {
    if (text.trim().isEmpty) return;
    final lines = text.split(RegExp(r'\r?\n'));
    final mediaClips = _studioMediaClips;
    final records = List<ShotRecord>.from(_project.log.records);
    bool logChanged = false;

    for (int i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) continue;

      final parsed = ConventionGeneratorService.parseConventionLine(
        line: trimmed,
        project: _project,
      );
      if (parsed == null) continue;

      final chapter = parsed['chapter'] ?? '';
      final scene = parsed['scene'] ?? '';
      final plane = parsed['plane'];
      final take = parsed['take'] ?? '1';
      final reel = parsed['reel'] ?? _project.defaultReel;
      final clipIndex = int.tryParse(parsed['clipIndex'] ?? '') ?? (i + 1);

      RenameProposal? matchedClip;
      if (clipIndex > 0 && clipIndex <= mediaClips.length) {
        matchedClip = mediaClips[clipIndex - 1];
      }

      final camera = _project.activeCamera;
      final clipNum = matchedClip != null
          ? ClipMatcherService.extractClipNumber(
              matchedClip.originalFilePath ?? '',
            )
          : clipIndex.toString();

      int existingIdx = -1;
      if (matchedClip?.associatedRecord != null) {
        existingIdx = records.indexWhere(
          (r) => r.id == matchedClip!.associatedRecord!.id,
        );
      }
      if (existingIdx == -1) {
        existingIdx = records.indexWhere(
          (r) => r.cameras.any(
            (c) => c.clipName == clipNum && c.cameraName == camera,
          ),
        );
      }
      if (existingIdx == -1) {
        existingIdx = records.indexWhere(
          (r) =>
              r.scene == scene &&
              (plane == null || r.plane == plane) &&
              r.take == take,
        );
      }

      if (existingIdx != -1) {
        final existing = records[existingIdx];
        records[existingIdx] = existing.copyWith(
          chapter: chapter.isNotEmpty ? chapter : existing.chapter,
          scene: scene.isNotEmpty ? scene : existing.scene,
          plane: plane ?? existing.plane,
          take: take.isNotEmpty ? take : existing.take,
          reel: reel.isNotEmpty ? reel : existing.reel,
        );
        logChanged = true;
      } else {
        final newRecord = ShotRecord(
          chapter: chapter,
          scene: scene,
          plane: plane,
          take: take,
          cameras: [CameraTakeRecord(cameraName: camera, clipName: clipNum)],
          reel: reel,
          tcIn: matchedClip?.fileTcIn,
          tcOut: matchedClip?.fileTcOut,
        );
        records.add(newRecord);
        logChanged = true;
      }

      // If active clip matches this line, refresh Slate quick entry text controllers
      if (_selectedStudioClip != null &&
          matchedClip != null &&
          _selectedStudioClip!.originalFilePath ==
              matchedClip.originalFilePath) {
        _studioChapterController.text = chapter;
        _studioSceneController.text = scene;
        _studioPlaneController.text = plane ?? '';
        _studioTakeController.text = take;
        _studioReelController.text = reel;
        _lastSelectedReel = reel;
      }
    }

    if (logChanged) {
      setState(() {
        _project = _project.copyWith(
          log: _project.log.copyWith(records: records),
        );
        _isDirty = true;
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _conventionEditorController.text = data.text!;
      _onConventionTextChanged(data.text!);
    }
  }

  void _clearConventionEditor() {
    _conventionEditorController.clear();
    setState(() {
      _livePastedOverrides = {};
      _livePastedLineNumbers = {};
      _duplicateClipConflicts = {};
      _resolvedConflictPaths.clear();
      _filterOnlyConventionMatches = false;
    });
  }

  bool _doReelsMatchForCamera({
    required String? lineReel,
    required String clipReel,
    required String? clipFilePath,
  }) {
    if (lineReel == null || lineReel.trim().isEmpty) return true;

    final lReel = lineReel.trim().toUpperCase();
    final cReel = clipReel.trim().toUpperCase();

    // Extract explicit leading camera letter from lineReel (e.g. "A" in "A001")
    final lCamMatch = RegExp(r'^([A-Z])\d+').firstMatch(lReel);
    final lCam = lCamMatch?.group(1);

    // Extract clip camera from clipReel or clip filename
    final cCamMatch = RegExp(r'^([A-Z])\d+').firstMatch(cReel);
    String? cCam = cCamMatch?.group(1);
    if (cCam == null && clipFilePath != null && clipFilePath.isNotEmpty) {
      cCam = ClipMatcherService.extractCamera(clipFilePath);
    }

    // Rule A: If both lineReel and clip have explicit camera letters and they differ, return false immediately!
    if (lCam != null && cCam != null && lCam != cCam) {
      return false;
    }

    // Rule B: If _project.activeCamera != 'ALL', and lCam != null && lCam != _project.activeCamera.toUpperCase():
    if (_project.activeCamera.toUpperCase() != 'ALL' &&
        lCam != null &&
        lCam != _project.activeCamera.toUpperCase()) {
      return false;
    }

    // Extract numeric portions
    final lReelNumeric = lReel.replaceAll(RegExp(r'^[A-Z]'), '');
    final cReelNumeric = cReel.replaceAll(RegExp(r'^[A-Z]'), '');

    if (lReel == cReel) return true;
    if (_project.activeCamera.toUpperCase() != 'ALL') {
      if ('${_project.activeCamera.toUpperCase()}$lReel' == cReel) return true;
      if (lReel == '${_project.activeCamera.toUpperCase()}$cReel') return true;
    }

    // Rule C: Only when camera letters do not conflict (either lCam == cCam, or lReel
    // is purely numeric like "001" and the clip belongs to the active camera) may
    // lReelNumeric == cReelNumeric return true.
    if (lReelNumeric.isNotEmpty && lReelNumeric == cReelNumeric) {
      if (lCam != null && cCam != null && lCam == cCam) {
        return true;
      }
      if (lCam == null) {
        if (_project.activeCamera.toUpperCase() == 'ALL') {
          return true;
        } else if (cCam == null ||
            cCam == _project.activeCamera.toUpperCase()) {
          return true;
        }
      }
    }

    return false;
  }

  bool _hasUnappliedTextOverride(RenameProposal proposal) {
    if (proposal.originalFilePath == null) return false;
    final path = proposal.originalFilePath!;
    if (!_livePastedOverrides.containsKey(path)) return false;
    if (_duplicateClipConflicts.containsKey(path)) return false;

    final override = _livePastedOverrides[path]!;
    final origExt = p.extension(path);
    final targetWithExt = p.extension(override).isEmpty && origExt.isNotEmpty
        ? '$override$origExt'
        : override;

    return proposal.status != ProposalStatus.ready ||
        proposal.proposedFileName.toLowerCase() != targetWithExt.toLowerCase();
  }

  String? _getOriginalClipName(RenameProposal clip) {
    if (clip.originalFilePath == null) return null;
    final path = clip.originalFilePath!;
    final base = p.basename(path).toLowerCase();
    for (final entry in _renameHistory) {
      final renamedPath = entry['renamedPath'] as String?;
      final originalPath = entry['originalPath'] as String?;
      if (renamedPath != null && originalPath != null) {
        if (p.basename(renamedPath).toLowerCase() == base ||
            renamedPath.toLowerCase() == path.toLowerCase()) {
          return p.basename(originalPath);
        }
      }
    }
    return null;
  }

  String _getOriginalClipSubtitle(RenameProposal clip) {
    final orig = _getOriginalClipName(clip);
    if (orig != null && orig.isNotEmpty) {
      return 'Original: $orig';
    }
    return 'Renombrado en disco';
  }

  void _evaluateConventionMatches() {
    if (_report == null) return;

    final text = _conventionEditorController.text;
    final mediaClips = _report!.proposals
        .where((p) => !p.isCompanionFile && p.originalFilePath != null)
        .toList();

    if (text.trim().isEmpty) {
      setState(() {
        _livePastedOverrides = {};
        _livePastedLineNumbers = {};
        _duplicateClipConflicts = {};
        _filterOnlyConventionMatches = false;
      });
      return;
    }

    final rawLines = text.split(RegExp(r'\r?\n'));
    final parsedLines = <PastedLineItem>[];
    for (int i = 0; i < rawLines.length; i++) {
      final trimmed = rawLines[i].trim();
      if (trimmed.isEmpty) continue;
      final lineIndex = i + 1;

      var item = QuickPasteConventionDialog.parsePastedLine(trimmed, lineIndex);
      final conventionParsed = ConventionGeneratorService.parseConventionLine(
        line: trimmed,
        project: _project,
      );

      if (conventionParsed != null) {
        final parsedClip = int.tryParse(conventionParsed['clipIndex'] ?? '');
        final parsedReel = conventionParsed['reel'];
        item = PastedLineItem(
          lineNumber: lineIndex,
          rawLine: trimmed,
          clipNumber: parsedClip ?? item.clipNumber,
          reel: parsedReel ?? item.reel,
          hasExtractedClip: (parsedClip != null) || item.hasExtractedClip,
        );
      }

      if (item.hasExtractedClip) {
        parsedLines.add(item);
      }
    }

    // Check duplicate clip lines in pasted text
    final pastedByKey = <String, List<PastedLineItem>>{};
    for (final line in parsedLines) {
      if (line.hasExtractedClip && line.clipNumber != null) {
        final reelKey = line.reel?.toUpperCase() ?? 'ALL';
        final key = '${reelKey}_${line.clipNumber}';
        pastedByKey.putIfAbsent(key, () => []).add(line);
        final reelKeyNum = reelKey.replaceAll(RegExp(r'^[A-Z]'), '');
        if (reelKeyNum.isNotEmpty && reelKeyNum != reelKey) {
          pastedByKey
              .putIfAbsent('${reelKeyNum}_${line.clipNumber}', () => [])
              .add(line);
        }
      }
    }
    final duplicatePastedKeys = <String>{};
    for (final entry in pastedByKey.entries) {
      if (entry.value.length > 1) {
        duplicatePastedKeys.add(entry.key);
      }
    }

    // Check for duplicate files on disk for the same (Reel, ClipNumber)
    final diskClipsByKey = <String, List<RenameProposal>>{};
    for (final clip in mediaClips) {
      if (clip.status == ProposalStatus.alreadyRenamed) continue;
      final fileName = p.basename(clip.originalFilePath!);
      final reel = _getProposalReel(clip).toUpperCase();
      final clipNumStr = ClipMatcherService.extractClipNumber(fileName);
      final clipNum = int.tryParse(clipNumStr);
      if (clipNum != null) {
        final key = '${reel}_$clipNum';
        diskClipsByKey.putIfAbsent(key, () => []).add(clip);
      }
    }

    final newDuplicateClipConflicts = <String, String>{};
    for (final entry in diskClipsByKey.entries) {
      if (entry.value.length > 1) {
        final firstClip = entry.value.first;
        final clipNum =
            int.tryParse(
              ClipMatcherService.extractClipNumber(
                p.basename(firstClip.originalFilePath!),
              ),
            ) ??
            0;
        final clipNumDisplay = clipNum.toString().padLeft(2, '0');
        for (final clip in entry.value) {
          final path = clip.originalFilePath!;
          if (!_resolvedConflictPaths.contains(path)) {
            newDuplicateClipConflicts[path] =
                'Conflicto: Clip #$clipNumDisplay duplicado';
          }
        }
      }
    }

    if (newDuplicateClipConflicts.isNotEmpty) {
      bool reportChanged = false;
      final updatedProposals = _report!.proposals.map((prop) {
        if (prop.status == ProposalStatus.alreadyRenamed) return prop;
        if (prop.originalFilePath != null &&
            newDuplicateClipConflicts.containsKey(prop.originalFilePath)) {
          if (prop.status != ProposalStatus.conflict) {
            reportChanged = true;
            return prop.copyWith(status: ProposalStatus.conflict);
          }
        }
        return prop;
      }).toList();
      if (reportChanged) {
        _report = DryRunReport(proposals: updatedProposals);
      }
    }

    final newLiveOverrides = <String, String>{};
    final newLiveLineNumbers = <String, int>{};

    // Intelligent matching by (Reel, ClipNumber) - without arbitrary sequential fallback
    for (final clip in mediaClips) {
      if (clip.status == ProposalStatus.alreadyRenamed) continue;
      final path = clip.originalFilePath!;
      if (newDuplicateClipConflicts.containsKey(path)) continue;
      if (_resolvedConflictPaths.contains(path)) continue;

      final fileName = p.basename(path);
      final reel = _getProposalReel(clip).toUpperCase();
      final clipNumStr = ClipMatcherService.extractClipNumber(fileName);
      final clipNum = int.tryParse(clipNumStr);
      if (clipNum == null) continue;

      final candidates = <PastedLineItem>[];
      for (final line in parsedLines) {
        if (!line.hasExtractedClip || line.clipNumber != clipNum) continue;

        if (_doReelsMatchForCamera(
          lineReel: line.reel,
          clipReel: reel,
          clipFilePath: path,
        )) {
          candidates.add(line);
        }
      }

      if (candidates.length == 1) {
        final matchedLine = candidates.first;
        final matchedReel = matchedLine.reel?.toUpperCase() ?? 'ALL';
        final matchedReelNum = matchedReel.replaceAll(RegExp(r'^[A-Z]'), '');
        final lineKey = '${matchedReel}_${matchedLine.clipNumber}';
        final altLineKey = '${matchedReelNum}_${matchedLine.clipNumber}';
        if (!duplicatePastedKeys.contains(lineKey) &&
            !duplicatePastedKeys.contains(altLineKey)) {
          newLiveOverrides[path] = matchedLine.rawLine;
          newLiveLineNumbers[path] = matchedLine.lineNumber;
        }
      }
    }

    setState(() {
      _livePastedOverrides = newLiveOverrides;
      _livePastedLineNumbers = newLiveLineNumbers;
      _duplicateClipConflicts = newDuplicateClipConflicts;
    });
  }

  void _scrollToClip(String originalFilePath) {
    if (!_verticalTableScrollController.hasClients || _report == null) return;
    List<RenameProposal> displayProposals = _report!.proposals;
    if (!_renameMetadata) {
      displayProposals = displayProposals
          .where((p) => !p.isCompanionFile)
          .toList();
    }
    if (_selectedReelFilter != null) {
      displayProposals = displayProposals
          .where((p) => _getProposalReel(p) == _selectedReelFilter)
          .toList();
    }
    if (_filterOnlyConventionMatches) {
      displayProposals = displayProposals
          .where(
            (p) =>
                p.originalFilePath != null &&
                _livePastedOverrides.containsKey(p.originalFilePath),
          )
          .toList();
    }
    final index = displayProposals.indexWhere(
      (p) => p.originalFilePath == originalFilePath,
    );
    if (index != -1) {
      const rowHeight = 48.0;
      final targetOffset = (index * rowHeight).clamp(
        0.0,
        _verticalTableScrollController.position.maxScrollExtent,
      );
      _verticalTableScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  List<_ConventionLineStatus> _getConventionLineStatuses() {
    if (_report == null) return [];
    final text = _conventionEditorController.text;
    if (text.trim().isEmpty) return [];

    final rawLines = text.split(RegExp(r'\r?\n'));
    final mediaClips = _report!.proposals
        .where((p) => !p.isCompanionFile && p.originalFilePath != null)
        .toList();

    final statuses = <_ConventionLineStatus>[];

    for (int i = 0; i < rawLines.length; i++) {
      final trimmed = rawLines[i].trim();
      if (trimmed.isEmpty) continue;

      final lineIndex = i + 1;
      final parsed = QuickPasteConventionDialog.parsePastedLine(
        trimmed,
        lineIndex,
      );
      final conventionParsed = ConventionGeneratorService.parseConventionLine(
        line: trimmed,
        project: _project,
      );

      // 1. Check if it matched a loaded media clip
      String? matchedPath;
      for (final entry in _livePastedLineNumbers.entries) {
        if (entry.value == lineIndex &&
            !_duplicateClipConflicts.containsKey(entry.key) &&
            _livePastedOverrides.containsKey(entry.key)) {
          matchedPath = entry.key;
          break;
        }
      }

      if (matchedPath != null) {
        final originalFileName = p.basename(matchedPath);
        statuses.add(
          _ConventionLineStatus(
            lineNumber: lineIndex,
            text: 'Línea $lineIndex: $originalFileName',
            icon: Icons.check_circle,
            color: Colors.green,
            targetFilePath: matchedPath,
          ),
        );
        continue;
      }

      // 2. Check if the line could not be parsed
      final effectiveClipNumber = parsed.hasExtractedClip
          ? parsed.clipNumber
          : int.tryParse(conventionParsed?['clipIndex'] ?? '');

      if (effectiveClipNumber == null) {
        statuses.add(
          _ConventionLineStatus(
            lineNumber: lineIndex,
            text: 'Línea $lineIndex: Formato de convención no reconocido',
            icon: Icons.help_outline,
            color: Colors.grey,
          ),
        );
        continue;
      }

      // 3. Extracted clip number: check disk files
      final clipNum = effectiveClipNumber;
      final clipNumDisplay = clipNum.toString().padLeft(2, '0');
      final lineReel = (parsed.reel ?? conventionParsed?['reel'])
          ?.toUpperCase();

      final matchingClipsOnDisk = mediaClips.where((c) {
        final fn = p.basename(c.originalFilePath!);
        final cn = int.tryParse(ClipMatcherService.extractClipNumber(fn));
        final r = _getProposalReel(c).toUpperCase();
        if (cn != clipNum) return false;
        return _doReelsMatchForCamera(
          lineReel: lineReel,
          clipReel: r,
          clipFilePath: c.originalFilePath,
        );
      }).toList();

      if (matchingClipsOnDisk.length > 1) {
        // Duplicate clip conflict on disk
        statuses.add(
          _ConventionLineStatus(
            lineNumber: lineIndex,
            text:
                'Línea $lineIndex: Conflicto en disco (Clip #$clipNumDisplay duplicado)',
            icon: Icons.warning_amber_rounded,
            color: Colors.red,
            targetFilePath: matchingClipsOnDisk.first.originalFilePath,
          ),
        );
      } else if (matchingClipsOnDisk.isEmpty) {
        final alreadyRenamedProp = _report!.proposals.where((prop) {
          if (prop.status != ProposalStatus.alreadyRenamed) return false;
          final fn = prop.originalFilePath != null
              ? p.basenameWithoutExtension(prop.originalFilePath!)
              : p.basenameWithoutExtension(prop.proposedFileName);
          return fn.toLowerCase() == trimmed.toLowerCase();
        }).firstOrNull;

        if (alreadyRenamedProp != null) {
          final fn = p.basename(
            alreadyRenamedProp.originalFilePath ??
                alreadyRenamedProp.proposedFileName,
          );
          statuses.add(
            _ConventionLineStatus(
              lineNumber: lineIndex,
              text: 'Línea $lineIndex: Renombrado en disco ($fn)',
              icon: Icons.task_alt,
              color: Colors.green,
              targetFilePath: alreadyRenamedProp.originalFilePath,
            ),
          );
        } else {
          statuses.add(
            _ConventionLineStatus(
              lineNumber: lineIndex,
              text:
                  'Línea $lineIndex: Sin archivo en disco (Clip #$clipNumDisplay)',
              icon: Icons.info_outline,
              color: Colors.amber,
            ),
          );
        }
      } else {
        // Single file on disk, but conflict in text or not matched
        statuses.add(
          _ConventionLineStatus(
            lineNumber: lineIndex,
            text:
                'Línea $lineIndex: Conflicto en texto (Clip #$clipNumDisplay duplicado)',
            icon: Icons.warning_amber_rounded,
            color: Colors.red,
            targetFilePath: matchingClipsOnDisk.first.originalFilePath,
          ),
        );
      }
    }

    return statuses;
  }

  String? _findConventionNameForClip(
    String reel,
    int clipNumber, [
    String? clipFilePath,
  ]) {
    final lines = _conventionEditorController.text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (int i = 0; i < lines.length; i++) {
      final parsed = QuickPasteConventionDialog.parsePastedLine(
        lines[i],
        i + 1,
      );
      if (parsed.hasExtractedClip && parsed.clipNumber == clipNumber) {
        if (_doReelsMatchForCamera(
          lineReel: parsed.reel,
          clipReel: reel,
          clipFilePath: clipFilePath,
        )) {
          return parsed.rawLine;
        }
      }
    }
    return null;
  }

  void _updateCompanionProposals(
    List<RenameProposal> proposals,
    String origVideoPath,
    String newProposedVideoName,
  ) {
    final origBase = p.basenameWithoutExtension(origVideoPath);
    final newProposedBase = p.basenameWithoutExtension(newProposedVideoName);
    for (int j = 0; j < proposals.length; j++) {
      final comp = proposals[j];
      if (comp.isCompanionFile && comp.originalFilePath != null) {
        final compBase = p.basenameWithoutExtension(comp.originalFilePath!);
        final isGoProMatch =
            origBase.toUpperCase().startsWith('GX') &&
            compBase.toUpperCase().startsWith('GL') &&
            origBase.length >= 8 &&
            compBase.length >= 8 &&
            origBase.substring(2) == compBase.substring(2);
        final isSonyM01 =
            compBase.toUpperCase() == '${origBase.toUpperCase()}M01';
        final isMatched =
            comp.companionFilePath == origVideoPath ||
            compBase == origBase ||
            isSonyM01 ||
            isGoProMatch;
        if (isMatched) {
          final compExt = p.extension(comp.originalFilePath!);
          final suffix = isSonyM01 ? 'M01' : '';
          proposals[j] = comp.copyWith(
            proposedFileName: '$newProposedBase$suffix$compExt',
            status: ProposalStatus.ready,
          );
        }
      }
    }
  }

  void _applyNonBlockingMatches() {
    if (_report == null) return;
    _previousReportBeforePaste = _report;
    final updatedProposals = List<RenameProposal>.from(_report!.proposals);
    int appliedCount = 0;

    for (int i = 0; i < updatedProposals.length; i++) {
      final proposal = updatedProposals[i];
      if (proposal.isCompanionFile || proposal.originalFilePath == null) {
        continue;
      }

      final filePath = proposal.originalFilePath!;
      if (_duplicateClipConflicts.containsKey(filePath)) continue;

      final matchedName = _livePastedOverrides[filePath];
      if (matchedName != null && matchedName.trim().isNotEmpty) {
        final rawPasted = matchedName.trim();
        final origExt = p.extension(filePath);
        String newProposedName = rawPasted;
        if (p.extension(rawPasted).isEmpty && origExt.isNotEmpty) {
          newProposedName = '$rawPasted$origExt';
        }

        updatedProposals[i] = proposal.copyWith(
          proposedFileName: newProposedName,
          status: ProposalStatus.ready,
        );

        _updateCompanionProposals(updatedProposals, filePath, newProposedName);
        appliedCount++;
      }
    }

    setState(() {
      _report = DryRunReport(proposals: updatedProposals);
    });

    final conflictsCount = _duplicateClipConflicts.length;
    final message = conflictsCount > 0
        ? '$appliedCount nombres aplicados ($conflictsCount pendientes de resolver)'
        : '$appliedCount nombres aplicados';

    _conventionEditorPanelFocusNode.requestFocus();
    _showNotification(message);
  }

  void _undoPastedMatches() {
    if (_previousReportBeforePaste != null) {
      setState(() {
        _report = _previousReportBeforePaste;
        _previousReportBeforePaste = null;
      });
      _evaluateConventionMatches();
      _showNotification('Cambios de convención deshechos.');
    }
  }

  void _handleFooterConflictResolution() {
    _openConflictResolver();
  }

  int? get _activeConventionEditorLineNumber {
    if (_selectedStudioClip == null) return null;
    final path = _selectedStudioClip!.originalFilePath;
    if (path != null && _livePastedLineNumbers.containsKey(path)) {
      return _livePastedLineNumbers[path];
    }
    final clips = _studioMediaClips;
    final idx = clips.indexWhere((c) => c.originalFilePath == path);
    if (idx != -1) {
      return idx + 1;
    }
    return null;
  }

  Widget _buildConventionEditorPane({double width = 380}) {
    final lines = _conventionEditorController.text
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final lineCount = lines.length;
    final mediaClips =
        _report?.proposals.where((p) => !p.isCompanionFile).toList() ?? [];
    final totalClips = mediaClips.length;
    final matchedCount = _livePastedOverrides.keys
        .where((k) => !_duplicateClipConflicts.containsKey(k))
        .length;
    final unappliedCount = mediaClips.where(_hasUnappliedTextOverride).length;
    final isApplied = unappliedCount == 0 && matchedCount > 0;

    final theme = Theme.of(context);
    final hasFocus =
        _conventionEditorPanelFocusNode.hasFocus ||
        _conventionEditorFocusNode.hasFocus;

    return SizedBox(
      width: width,
      child: Focus(
        focusNode: _conventionEditorPanelFocusNode,
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: hasFocus
                  ? theme.colorScheme.primary
                  : theme.dividerColor.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top bar
                Row(
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Convención de Texto',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Tooltip(
                      message: 'Pegar desde el portapapeles',
                      child: IconButton(
                        icon: const Icon(Icons.paste_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: _pasteFromClipboard,
                      ),
                    ),
                    Tooltip(
                      message: 'Limpiar texto',
                      child: IconButton(
                        icon: const Icon(Icons.clear_all_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: _clearConventionEditor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Text Editor with Code Gutter Line Numbers
                Expanded(
                  child: LineNumberedTextField(
                    controller: _conventionEditorController,
                    undoController: _conventionEditorUndoController,
                    focusNode: _conventionEditorFocusNode,
                    activeLineNumber: _activeConventionEditorLineNumber,
                    hintText:
                        'Pega o escribe aquí la lista de convenciones...\n\nEjemplo:\nMNBOENC_080626_17_11_T1_A001_1_D1_U3',
                    onChanged: _onConventionTextChanged,
                  ),
                ),
                // Live Line-by-Line Inspection Section
                Builder(
                  builder: (context) {
                    final lineStatuses = _getConventionLineStatuses();
                    if (lineStatuses.isEmpty) return const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Estado de Líneas en Vivo',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${lineStatuses.length} líneas',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 140),
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.brightness == Brightness.dark
                                    ? Colors.black26
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                              child: Scrollbar(
                                controller:
                                    _conventionLineStatusScrollController,
                                thumbVisibility: true,
                                child: ListView.builder(
                                  controller:
                                      _conventionLineStatusScrollController,
                                  primary: false,
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                    horizontal: 6,
                                  ),
                                  itemCount: lineStatuses.length,
                                  itemBuilder: (context, i) {
                                    final item = lineStatuses[i];
                                    final isSelectedClipLine =
                                        item.targetFilePath != null &&
                                        item.targetFilePath ==
                                            _selectedStudioClip
                                                ?.originalFilePath;

                                    return InkWell(
                                      onTap: item.targetFilePath != null
                                          ? () {
                                              _scrollToClip(
                                                item.targetFilePath!,
                                              );
                                              if (_isStudioMode &&
                                                  _report != null) {
                                                final matches = _report!
                                                    .proposals
                                                    .where(
                                                      (p) =>
                                                          p.originalFilePath ==
                                                          item.targetFilePath,
                                                    )
                                                    .toList();
                                                if (matches.isNotEmpty) {
                                                  _selectStudioClip(
                                                    matches.first,
                                                  );
                                                }
                                              }
                                            }
                                          : null,
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3.0,
                                          horizontal: 4.0,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelectedClipLine
                                              ? theme.colorScheme.primary
                                                    .withValues(
                                                      alpha:
                                                          theme.brightness ==
                                                              Brightness.dark
                                                          ? 0.3
                                                          : 0.15,
                                                    )
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: isSelectedClipLine
                                              ? Border.all(
                                                  color:
                                                      theme.colorScheme.primary,
                                                  width: 1.5,
                                                )
                                              : null,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              item.icon,
                                              size: 14,
                                              color: item.color,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                item.text,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: isSelectedClipLine
                                                      ? FontWeight.bold
                                                      : FontWeight.w500,
                                                  color: isSelectedClipLine
                                                      ? theme
                                                            .colorScheme
                                                            .primary
                                                      : item.color,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                // Bottom bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Líneas: $lineCount | Clips coincidentes: $matchedCount/$totalClips',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.hintColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.icon(
                            icon: Icon(
                              isApplied ? Icons.check_circle : Icons.check,
                              size: 16,
                              color: isApplied ? Colors.green : null,
                            ),
                            label: Text(
                              unappliedCount > 0
                                  ? 'Aplicar Coincidencias ($unappliedCount)'
                                  : (matchedCount > 0
                                        ? 'Coincidencias Aplicadas ($matchedCount)'
                                        : 'Aplicar Coincidencias (0)'),
                            ),
                            onPressed: unappliedCount > 0
                                ? _applyNonBlockingMatches
                                : null,
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.undo, size: 16),
                            label: const Text('Deshacer'),
                            onPressed: _previousReportBeforePaste != null
                                ? _undoPastedMatches
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isPlayableVideo(String? filePath) {
    if (filePath == null) return false;
    final ext = p.extension(filePath).toLowerCase();
    return ['.mp4', '.mov', '.mxf', '.crm', '.lrv', '.wav'].contains(ext);
  }

  void _openMediaPreview(RenameProposal proposal) {
    if (_report == null) return;
    final playlist = _report!.proposals
        .where(
          (p) =>
              p.originalFilePath != null &&
              _isPlayableVideo(p.originalFilePath),
        )
        .toList();
    if (playlist.isEmpty) return;

    final initialIndex = playlist.indexOf(proposal);

    showDialog(
      context: context,
      builder: (ctx) => MediaPreviewDialog(
        playlist: playlist,
        initialIndex: initialIndex >= 0 ? initialIndex : 0,
        projectMetadata: _project.log.metadata,
        activeCamera: _project.activeCamera,
        reelOverride: _reelController.text.trim().isNotEmpty
            ? _reelController.text.trim()
            : null,
        autoSortByClip: _project.autoSortByClip,
        onAutoSortChanged: (val) {
          setState(() {
            _project = _project.copyWith(autoSortByClip: val);
            _isDirty = true;
          });
        },
        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {
          final clipNum = ClipMatcherService.extractClipNumber(
            prop.originalFilePath ?? '',
          );
          final fileReel =
              prop.fileReel ??
              ClipMatcherService.extractReel(prop.originalFilePath ?? '');
          final targetReel = _reelController.text.trim().isNotEmpty
              ? _reelController.text.trim()
              : (fileReel ?? _project.defaultReel);

          final records = List<ShotRecord>.from(_project.log.records);
          final existingIdx = records.indexWhere(
            (r) =>
                (chapter.isEmpty || r.chapter.trim() == chapter.trim()) &&
                r.scene.trim() == scene.trim() &&
                (r.plane ?? '').trim() == plane.trim() &&
                r.take.trim() == take.trim(),
          );

          if (existingIdx != -1) {
            final existing = records[existingIdx];
            final updatedCameras = List<CameraTakeRecord>.from(
              existing.cameras,
            );
            final camIdx = updatedCameras.indexWhere(
              (c) => c.cameraName == _project.activeCamera,
            );
            if (camIdx != -1) {
              updatedCameras[camIdx] = updatedCameras[camIdx].copyWith(
                clipName: clipNum,
              );
            } else {
              updatedCameras.add(
                CameraTakeRecord(
                  cameraName: _project.activeCamera,
                  clipName: clipNum,
                ),
              );
            }

            records[existingIdx] = existing.copyWith(
              chapter: chapter.isNotEmpty ? chapter : existing.chapter,
              cameras: updatedCameras,
              reel: targetReel.isNotEmpty ? targetReel : existing.reel,
              tcIn: prop.fileTcIn ?? existing.tcIn,
              tcOut: prop.fileTcOut ?? existing.tcOut,
              observations: notes.isNotEmpty ? notes : existing.observations,
              isMos: isMos,
            );
          } else {
            final newRecord = ShotRecord(
              chapter: chapter,
              scene: scene,
              plane: plane.isNotEmpty ? plane : null,
              take: take,
              cameras: [
                CameraTakeRecord(
                  cameraName: _project.activeCamera,
                  clipName: clipNum,
                ),
              ],
              reel: targetReel,
              tcIn: prop.fileTcIn,
              tcOut: prop.fileTcOut,
              observations: notes.isNotEmpty ? notes : null,
              isMos: isMos,
            );
            records.add(newRecord);
          }

          final List<ShotRecord> finalRecords;
          if (_project.autoSortByClip) {
            finalRecords = BitacoraEditorTab.sortRecordsByClip(
              records,
              _project.activeCamera,
            );
          } else {
            finalRecords = records;
          }

          setState(() {
            _project = _project.copyWith(
              log: ShootingLog(
                metadata: _project.log.metadata,
                records: finalRecords,
              ),
            );
            _isDirty = true;
          });

          await _generatePreview();
        },
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _selectStudioClip(RenameProposal proposal) {
    _resetStudioZoom();
    _studioPositionNotifier.value = Duration.zero;
    setState(() {
      _selectedStudioClip = proposal;
      if (proposal.associatedRecord != null) {
        final rec = proposal.associatedRecord!;
        _studioChapterController.text = rec.chapter;
        _studioSceneController.text = rec.scene;
        _studioPlaneController.text = rec.plane ?? '';
        _studioTakeController.text = rec.take;
        final recReel = rec.reel.trim();
        _studioReelController.text = recReel.isNotEmpty
            ? recReel
            : (_lastSelectedReel ?? _project.defaultReel);
        _lastSelectedReel = _studioReelController.text;
        _studioNotesController.text = rec.observations ?? '';
        _studioIsMos = rec.isMos;
        _studioIsTf = rec.isTf;
      } else {
        _studioChapterController.text = '';
        _studioSceneController.text = '';
        _studioPlaneController.text = '';
        _studioTakeController.text = '1';
        _studioReelController.text = _lastSelectedReel ?? _project.defaultReel;
        _studioNotesController.text = '';
        _studioIsMos = false;
        _studioIsTf = false;
      }
    });

    _highlightMatchingConventionLine(proposal);

    _studioPlaybackErrorNotifier.value = null;

    final path = proposal.originalFilePath;
    if (path != null && _isPlayableVideo(path)) {
      _playStudioMedia(path);
    }
  }

  void _highlightMatchingConventionLine(RenameProposal proposal) {
    final text = _conventionEditorController.text;
    if (text.isEmpty) return;

    int? targetLineIndex;

    // 1. Check if line was mapped during live evaluation
    if (proposal.originalFilePath != null &&
        _livePastedLineNumbers.containsKey(proposal.originalFilePath)) {
      targetLineIndex = _livePastedLineNumbers[proposal.originalFilePath];
    }

    // 2. Fallback: Parse lines in editor to match clip number and reel
    if (targetLineIndex == null) {
      final rawLines = text.split(RegExp(r'\r?\n'));
      final clipNumStr = ClipMatcherService.extractClipNumber(
        proposal.originalFilePath ?? proposal.proposedFileName,
      );
      final clipNum = int.tryParse(clipNumStr);
      final reel = _getProposalReel(proposal).toUpperCase();

      if (clipNum != null) {
        for (int i = 0; i < rawLines.length; i++) {
          final trimmed = rawLines[i].trim();
          if (trimmed.isEmpty) continue;
          final parsed = QuickPasteConventionDialog.parsePastedLine(
            trimmed,
            i + 1,
          );
          if (parsed.hasExtractedClip && parsed.clipNumber == clipNum) {
            if (parsed.reel == null || parsed.reel!.toUpperCase() == reel) {
              targetLineIndex = i + 1;
              break;
            }
          }
        }
      }
    }

    if (targetLineIndex == null) return;

    // 3. Compute start and end character offsets of targetLineIndex
    int currentLine = 1;
    int lineStart = 0;

    while (lineStart < text.length) {
      int lineEnd = text.indexOf('\n', lineStart);
      if (lineEnd == -1) {
        lineEnd = text.length;
      }

      if (currentLine == targetLineIndex) {
        int cleanEnd = lineEnd;
        if (cleanEnd > lineStart && text[cleanEnd - 1] == '\r') {
          cleanEnd--;
        }
        _conventionEditorController.selection = TextSelection(
          baseOffset: lineStart,
          extentOffset: cleanEnd,
        );
        break;
      }

      lineStart = lineEnd + 1;
      currentLine++;
    }
  }

  bool _isStudioSlateModified(RenameProposal clip) {
    final rec = clip.associatedRecord;
    final currentCap = _studioChapterController.text.trim();
    final currentScene = _studioSceneController.text.trim();
    final currentPlane = _studioPlaneController.text.trim();
    final currentTake = _studioTakeController.text.trim();
    final currentNotes = _studioNotesController.text.trim();

    if (rec == null) {
      return currentCap.isNotEmpty ||
          currentScene.isNotEmpty ||
          (currentTake.isNotEmpty && currentTake != '1') ||
          _studioIsMos ||
          _studioIsTf;
    }

    return currentCap != rec.chapter.trim() ||
        currentScene != rec.scene.trim() ||
        currentPlane != (rec.plane ?? '').trim() ||
        currentTake != rec.take.trim() ||
        currentNotes != (rec.observations ?? '').trim() ||
        _studioIsMos != rec.isMos ||
        _studioIsTf != rec.isTf;
  }

  String _computeStudioProposedBanner(RenameProposal clip) {
    if (clip.associatedRecord == null &&
        !_isStudioSlateModified(clip) &&
        (clip.originalFilePath == null ||
            !_livePastedOverrides.containsKey(clip.originalFilePath))) {
      return 'Sin propuesta (ingresa datos en la claqueta o vincula una toma)';
    }
    if (!_isStudioSlateModified(clip) &&
        clip.originalFilePath != null &&
        _livePastedOverrides.containsKey(clip.originalFilePath)) {
      final override = _livePastedOverrides[clip.originalFilePath]!;
      final origExt = p.extension(clip.originalFilePath!);
      if (p.extension(override).isEmpty && origExt.isNotEmpty) {
        return '$override$origExt';
      }
      return override;
    }

    final origExt = clip.originalFilePath != null
        ? p.extension(clip.originalFilePath!)
        : '';
    final clipNum = ClipMatcherService.extractClipNumber(
      clip.originalFilePath ?? '',
    );
    final detectedCamera = clip.originalFilePath != null
        ? ClipMatcherService.extractCamera(
            clip.originalFilePath!,
            fallback: _project.activeCamera == 'ALL'
                ? 'A'
                : _project.activeCamera,
          )
        : (_project.activeCamera == 'ALL' ? 'A' : _project.activeCamera);

    final fileReel =
        clip.fileReel ??
        ClipMatcherService.extractReel(clip.originalFilePath ?? '');
    final defaultReel = _reelController.text.trim().isNotEmpty
        ? _reelController.text.trim()
        : (fileReel ?? clip.associatedRecord?.reel ?? '${detectedCamera}001');

    final capText = _studioChapterController.text.trim();
    final cap = _project.showChapter
        ? (capText.isNotEmpty
              ? capText
              : (clip.associatedRecord?.chapter.trim().isNotEmpty == true
                    ? clip.associatedRecord!.chapter.trim()
                    : '1'))
        : null;

    final sceneText = _studioSceneController.text.trim();
    final scene = sceneText.isNotEmpty
        ? sceneText
        : (clip.associatedRecord?.scene.trim().isNotEmpty == true
              ? clip.associatedRecord!.scene.trim()
              : '1');

    final planeText = _studioPlaneController.text.trim();
    final plane = _project.showPlane
        ? (planeText.isNotEmpty
              ? planeText
              : clip.associatedRecord?.plane?.trim())
        : null;

    final takeText = _studioTakeController.text.trim();
    var rawTake = takeText.isNotEmpty
        ? takeText
        : (clip.associatedRecord?.take.trim().isNotEmpty == true
              ? clip.associatedRecord!.take.trim()
              : '1');

    if (!_studioIsTf && rawTake.toUpperCase().startsWith('TF')) {
      rawTake = rawTake.substring(2);
      if (rawTake.isEmpty) rawTake = '1';
    } else if (!_studioIsTf && rawTake.toUpperCase().startsWith('T')) {
      rawTake = rawTake.substring(1);
      if (rawTake.isEmpty) rawTake = '1';
    } else if (_studioIsTf && rawTake.toUpperCase().startsWith('TF')) {
      rawTake = rawTake.substring(2);
      if (rawTake.isEmpty) rawTake = '1';
    } else if (_studioIsTf && rawTake.toUpperCase().startsWith('T')) {
      rawTake = rawTake.substring(1);
      if (rawTake.isEmpty) rawTake = '1';
    }

    final day = _project.log.metadata.day.trim().isNotEmpty
        ? _project.log.metadata.day.trim()
        : 'D01';

    final camType = _project.getCameraType(detectedCamera);
    final isDs = camType == CameraType.drivingShot;
    final isFf = camType == CameraType.freeFly;
    final isGpr = camType == CameraType.goPro;
    final isDr = camType == CameraType.drone;

    final unit = isDs
        ? 'DS'
        : (_project.log.metadata.unit.trim().isNotEmpty
              ? _project.log.metadata.unit.trim()
              : 'U1');

    final prod = _project.log.metadata.nomenclature.trim().isNotEmpty
        ? _project.log.metadata.nomenclature.trim()
        : (_project.log.metadata.production.trim().isNotEmpty
              ? _project.log.metadata.production.trim()
              : 'PROD');

    String? normalizedClip;
    final recClip = clip.associatedRecord?.cameras
        .where(
          (c) => c.cameraName.toUpperCase() == detectedCamera.toUpperCase(),
        )
        .firstOrNull
        ?.clipName;
    final candidateClip = (recClip != null && recClip.trim().isNotEmpty)
        ? recClip.trim()
        : clipNum;
    if (candidateClip.isNotEmpty) {
      final parsed = int.tryParse(candidateClip);
      normalizedClip = parsed != null
          ? parsed.toString().padLeft(2, '0')
          : candidateClip;
    }

    final reelText = _studioReelController.text.trim();
    final effectiveReel =
        fileReel ?? (reelText.isNotEmpty ? reelText : defaultReel);

    final base = ConventionNameGenerator.generate(
      nomenclature: prod,
      chapter: cap,
      date: _project.log.metadata.date.trim().isNotEmpty
          ? _project.log.metadata.date.trim()
          : '010126',
      scene: scene,
      plane: plane,
      take: rawTake,
      reel: ConventionGeneratorService.formatReelWithCamera(
        effectiveReel,
        detectedCamera,
      ),
      day: day,
      clipIndex: normalizedClip,
      unit: unit,
      activeCamera: detectedCamera,
      cameraType: camType,
      isTf: _studioIsTf,
      isDs: isDs,
      isFf: isFf,
      isGpr: isGpr,
      isDr: isDr,
    );

    return '$base$origExt';
  }

  void _onStudioSlateFieldChanged() {
    if (_selectedStudioClip == null || _report == null) return;
    final clip = _selectedStudioClip!;
    final clips = _studioMediaClips;
    final clipIndex =
        clips.indexWhere((c) => c.originalFilePath == clip.originalFilePath) +
        1;
    if (clipIndex <= 0) return;

    final chapter = _studioChapterController.text.trim();
    final scene = _studioSceneController.text.trim();
    final plane = _studioPlaneController.text.trim();
    final take = _studioTakeController.text.trim();
    final reel = _studioReelController.text.trim().isNotEmpty
        ? _studioReelController.text.trim()
        : _project.defaultReel;
    _lastSelectedReel = reel;
    final notes = _studioNotesController.text.trim();
    final camera = clip.originalFilePath != null
        ? ClipMatcherService.extractCamera(
            clip.originalFilePath!,
            fallback: _project.activeCamera == 'ALL'
                ? 'A'
                : _project.activeCamera,
          )
        : (_project.activeCamera == 'ALL' ? 'A' : _project.activeCamera);
    final fileReel =
        clip.fileReel ??
        ClipMatcherService.extractReel(clip.originalFilePath ?? '');
    final effectiveReel = fileReel ?? reel;
    final clipNum = ClipMatcherService.extractClipNumber(
      clip.originalFilePath ?? '',
    );

    // Update or create ShotRecord
    final records = List<ShotRecord>.from(_project.log.records);
    int existingIdx = -1;
    if (clip.associatedRecord != null) {
      existingIdx = records.indexWhere(
        (r) => r.id == clip.associatedRecord!.id,
      );
    }
    if (existingIdx == -1) {
      existingIdx = records.indexWhere(
        (r) => r.cameras.any(
          (c) => c.clipName == clipNum && c.cameraName == camera,
        ),
      );
    }

    if (existingIdx != -1) {
      final existing = records[existingIdx];
      final updatedCameras = List<CameraTakeRecord>.from(existing.cameras);
      final camIdx = updatedCameras.indexWhere((c) => c.cameraName == camera);
      if (camIdx != -1) {
        updatedCameras[camIdx] = updatedCameras[camIdx].copyWith(
          clipName: clipNum,
        );
      } else {
        updatedCameras.add(
          CameraTakeRecord(cameraName: camera, clipName: clipNum),
        );
      }

      records[existingIdx] = existing.copyWith(
        chapter: chapter.isNotEmpty ? chapter : existing.chapter,
        scene: scene.isNotEmpty ? scene : existing.scene,
        plane: plane.isNotEmpty ? plane : null,
        take: take.isNotEmpty ? take : existing.take,
        cameras: updatedCameras,
        reel: reel.isNotEmpty ? reel : existing.reel,
        observations: notes.isNotEmpty ? notes : existing.observations,
        isMos: _studioIsMos,
        isTf: _studioIsTf,
      );
    } else {
      final newRecord = ShotRecord(
        chapter: chapter,
        scene: scene,
        plane: plane.isNotEmpty ? plane : null,
        take: take.isNotEmpty ? take : '1',
        cameras: [CameraTakeRecord(cameraName: camera, clipName: clipNum)],
        reel: reel,
        tcIn: clip.fileTcIn,
        tcOut: clip.fileTcOut,
        observations: notes.isNotEmpty ? notes : null,
        isMos: _studioIsMos,
        isTf: _studioIsTf,
      );
      records.add(newRecord);
    }

    _project = _project.copyWith(log: _project.log.copyWith(records: records));
    _isDirty = true;

    // Generate updated convention name
    final newLine = ConventionGeneratorService.generateConventionName(
      project: _project,
      chapter: chapter,
      scene: scene,
      plane: plane.isNotEmpty ? plane : null,
      take: take,
      reel: effectiveReel,
      camera: camera,
      clipIndex: clipIndex,
    );

    final rawLines = _conventionEditorController.text.split(RegExp(r'\r?\n'));
    final lines = List<String>.from(rawLines);
    while (lines.length < clipIndex) {
      lines.add('');
    }
    lines[clipIndex - 1] = newLine;
    final updatedText = lines.join('\n');

    final oldSel = _conventionEditorController.selection;
    _conventionEditorController.text = updatedText;
    if (_conventionEditorFocusNode.hasFocus &&
        oldSel.isValid &&
        oldSel.end <= updatedText.length) {
      _conventionEditorController.selection = oldSel;
    }

    setState(() {
      _isStudioPendingSave = true;
    });

    _studioSaveDebounceTimer?.cancel();
    _studioSaveDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _saveStudioSlate(isAutoSave: true);
    });
  }

  Future<void> _saveStudioSlate({bool isAutoSave = false}) async {
    _studioSaveDebounceTimer?.cancel();
    if (_selectedStudioClip == null) return;
    final prop = _selectedStudioClip!;

    setState(() {
      _isStudioSaving = true;
      _isStudioPendingSave = false;
    });

    try {
      final chapter = _studioChapterController.text.trim();
      final scene = _studioSceneController.text.trim();
      final plane = _studioPlaneController.text.trim();
      final take = _studioTakeController.text.trim();
      final notes = _studioNotesController.text.trim();
      final isMos = _studioIsMos;
      final isTf = _studioIsTf;

      final clipNum = ClipMatcherService.extractClipNumber(
        prop.originalFilePath ?? '',
      );
      final fileReel =
          prop.fileReel ??
          ClipMatcherService.extractReel(prop.originalFilePath ?? '');
      final targetReel = _studioReelController.text.trim().isNotEmpty
          ? _studioReelController.text.trim()
          : (_reelController.text.trim().isNotEmpty
                ? _reelController.text.trim()
                : (fileReel ?? _project.defaultReel));
      _lastSelectedReel = targetReel;

      final effectiveCamera = prop.originalFilePath != null
          ? ClipMatcherService.extractCamera(
              prop.originalFilePath!,
              fallback: _project.activeCamera == 'ALL'
                  ? 'A'
                  : _project.activeCamera,
            )
          : (_project.activeCamera == 'ALL' ? 'A' : _project.activeCamera);

      final records = List<ShotRecord>.from(_project.log.records);
      final existingIdx = records.indexWhere(
        (r) =>
            (chapter.isEmpty || r.chapter.trim() == chapter) &&
            r.scene.trim() == scene &&
            (r.plane ?? '').trim() == plane &&
            r.take.trim() == take,
      );

      if (existingIdx != -1) {
        final existing = records[existingIdx];
        final updatedCameras = List<CameraTakeRecord>.from(existing.cameras);
        final camIdx = updatedCameras.indexWhere(
          (c) => c.cameraName.toUpperCase() == effectiveCamera.toUpperCase(),
        );
        if (camIdx != -1) {
          updatedCameras[camIdx] = updatedCameras[camIdx].copyWith(
            clipName: clipNum,
          );
        } else {
          updatedCameras.add(
            CameraTakeRecord(cameraName: effectiveCamera, clipName: clipNum),
          );
        }

        records[existingIdx] = existing.copyWith(
          chapter: chapter.isNotEmpty ? chapter : existing.chapter,
          cameras: updatedCameras,
          reel: targetReel.isNotEmpty ? targetReel : existing.reel,
          tcIn: prop.fileTcIn ?? existing.tcIn,
          tcOut: prop.fileTcOut ?? existing.tcOut,
          observations: notes.isNotEmpty ? notes : existing.observations,
          isMos: isMos,
          isTf: isTf,
        );
      } else {
        final newRecord = ShotRecord(
          chapter: chapter,
          scene: scene,
          plane: plane.isNotEmpty ? plane : null,
          take: take.isNotEmpty ? take : '1',
          cameras: [
            CameraTakeRecord(cameraName: effectiveCamera, clipName: clipNum),
          ],
          reel: targetReel,
          tcIn: prop.fileTcIn,
          tcOut: prop.fileTcOut,
          observations: notes.isNotEmpty ? notes : null,
          isMos: isMos,
          isTf: isTf,
        );
        records.add(newRecord);
      }

      final List<ShotRecord> finalRecords;
      if (_project.autoSortByClip) {
        finalRecords = BitacoraEditorTab.sortRecordsByClip(
          records,
          _project.activeCamera,
        );
      } else {
        finalRecords = records;
      }

      setState(() {
        _project = _project.copyWith(
          log: ShootingLog(
            metadata: _project.log.metadata,
            records: finalRecords,
          ),
        );
        _isDirty = true;
      });

      final clipIdx =
          _studioMediaClips.indexWhere(
            (c) => c.originalFilePath == prop.originalFilePath,
          ) +
          1;
      if (clipIdx > 0) {
        final convName = ConventionGeneratorService.generateConventionName(
          project: _project,
          chapter: chapter,
          scene: scene,
          plane: plane.isNotEmpty ? plane : null,
          take: take,
          reel: targetReel,
          camera: effectiveCamera,
          clipIndex: clipIdx,
        );
        if (prop.originalFilePath != null) {
          _livePastedOverrides.remove(prop.originalFilePath!);
          _livePastedLineNumbers.remove(prop.originalFilePath!);
        }
        final rawLines = _conventionEditorController.text.split(
          RegExp(r'\r?\n'),
        );
        final lines = List<String>.from(rawLines);
        while (lines.length < clipIdx) {
          lines.add('');
        }
        lines[clipIdx - 1] = convName;
        _conventionEditorController.text = lines.join('\n');
      }

      await _generatePreview();

      if (prop.originalFilePath != null) {
        if (_report != null) {
          final updated = _report!.proposals
              .where((p) => p.originalFilePath == prop.originalFilePath)
              .toList();
          if (updated.isNotEmpty) {
            setState(() {
              _selectedStudioClip = updated.first;
            });
          }
        }
        if (_selectedStudioClip != null && records.isNotEmpty) {
          final updatedRec = records.firstWhere(
            (r) =>
                (chapter.isEmpty || r.chapter.trim() == chapter) &&
                r.scene.trim() == scene &&
                (r.plane ?? '').trim() == plane &&
                r.take.trim() == take,
            orElse: () => records.last,
          );
          setState(() {
            _selectedStudioClip = _selectedStudioClip!.copyWith(
              associatedRecord: updatedRec,
            );
          });
        }
      }
      if (!isAutoSave) {
        _showNotification('Metadatos de claqueta actualizados');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStudioSaving = false;
          _isStudioPendingSave = false;
        });
      }
    }
  }

  Future<void> _unlinkStudioClip(
    RenameProposal clip,
    String detectedCamera,
  ) async {
    final clipPath = clip.originalFilePath;
    final clipNum = ClipMatcherService.extractClipNumber(clipPath ?? '');
    final records = List<ShotRecord>.from(_project.log.records);

    bool recordUpdated = false;
    for (int i = 0; i < records.length; i++) {
      final rec = records[i];
      final hadMatchingCam = rec.cameras.any(
        (c) =>
            c.clipName == clipNum &&
            c.cameraName.toUpperCase() == detectedCamera.toUpperCase(),
      );
      if (hadMatchingCam ||
          (clip.associatedRecord != null &&
              rec.id == clip.associatedRecord!.id)) {
        final updatedCameras = rec.cameras.where((c) {
          if (c.clipName == clipNum &&
              c.cameraName.toUpperCase() == detectedCamera.toUpperCase()) {
            return false;
          }
          if (clip.associatedRecord != null &&
              rec.id == clip.associatedRecord!.id &&
              c.cameraName.toUpperCase() == detectedCamera.toUpperCase()) {
            return false;
          }
          return true;
        }).toList();

        records[i] = rec.copyWith(cameras: updatedCameras);
        recordUpdated = true;
      }
    }

    if (clipPath != null) {
      _manualOverrides.remove(clipPath);
      _livePastedOverrides.remove(clipPath);
      _livePastedLineNumbers.remove(clipPath);
    }

    _studioChapterController.text = '';
    _studioSceneController.text = '';
    _studioPlaneController.text = '';
    _studioTakeController.text = '1';
    _studioReelController.text = _lastSelectedReel ?? _project.defaultReel;
    _studioNotesController.text = '';
    _studioIsMos = false;
    _studioIsTf = false;

    if (recordUpdated) {
      _project = _project.copyWith(
        log: ShootingLog(metadata: _project.log.metadata, records: records),
      );
      _isDirty = true;
    }

    await _generatePreview();

    if (_report != null && clipPath != null) {
      final updated = _report!.proposals
          .where((p) => p.originalFilePath == clipPath)
          .toList();
      if (updated.isNotEmpty) {
        setState(() {
          _selectedStudioClip = updated.first;
        });
      }
    }
    _showNotification('Toma desvinculada');
  }

  Future<void> _openTakeLinkerDialog(
    RenameProposal clip,
    String detectedCamera,
  ) async {
    final result = await TakeLinkerDialog.show(
      context,
      clip: clip,
      records: _project.log.records,
      activeCamera: detectedCamera,
      currentlyLinkedRecord: clip.associatedRecord,
    );

    if (result != null) {
      if (result.action == TakeLinkerAction.link && result.record != null) {
        await _linkStudioClipToRecord(clip, result.record!, detectedCamera);
      } else if (result.action == TakeLinkerAction.unlink) {
        await _unlinkStudioClip(clip, detectedCamera);
      }
    }
  }

  Future<void> _linkStudioClipToRecord(
    RenameProposal clip,
    ShotRecord targetRecord,
    String detectedCamera,
  ) async {
    final clipNum = ClipMatcherService.extractClipNumber(
      clip.originalFilePath ?? '',
    );
    final records = List<ShotRecord>.from(_project.log.records);
    final recIdx = records.indexWhere((r) => r.id == targetRecord.id);
    if (recIdx == -1) return;

    final existing = records[recIdx];
    final updatedCameras = List<CameraTakeRecord>.from(existing.cameras);
    final camIdx = updatedCameras.indexWhere(
      (c) => c.cameraName.toUpperCase() == detectedCamera.toUpperCase(),
    );
    if (camIdx != -1) {
      updatedCameras[camIdx] = updatedCameras[camIdx].copyWith(
        clipName: clipNum,
      );
    } else {
      updatedCameras.add(
        CameraTakeRecord(cameraName: detectedCamera, clipName: clipNum),
      );
    }

    final updatedRecord = existing.copyWith(
      cameras: updatedCameras,
      tcIn: existing.tcIn ?? clip.fileTcIn,
      tcOut: existing.tcOut ?? clip.fileTcOut,
    );
    records[recIdx] = updatedRecord;

    _studioChapterController.text = updatedRecord.chapter;
    _studioSceneController.text = updatedRecord.scene;
    _studioPlaneController.text = updatedRecord.plane ?? '';
    _studioTakeController.text = updatedRecord.take;
    _studioReelController.text = updatedRecord.reel;
    _lastSelectedReel = updatedRecord.reel;
    _studioNotesController.text = updatedRecord.observations ?? '';
    _studioIsMos = updatedRecord.isMos;
    _studioIsTf = updatedRecord.isTf;

    final List<ShotRecord> finalRecords;
    if (_project.autoSortByClip) {
      finalRecords = BitacoraEditorTab.sortRecordsByClip(
        records,
        _project.activeCamera,
      );
    } else {
      finalRecords = records;
    }

    setState(() {
      _project = _project.copyWith(
        log: ShootingLog(
          metadata: _project.log.metadata,
          records: finalRecords,
        ),
      );
      _isDirty = true;
    });

    final clips = _studioMediaClips;
    final clipIdx =
        clips.indexWhere((c) => c.originalFilePath == clip.originalFilePath) +
        1;
    if (clipIdx > 0) {
      final convName = ConventionGeneratorService.generateConventionName(
        project: _project,
        chapter: updatedRecord.chapter,
        scene: updatedRecord.scene,
        plane: updatedRecord.plane,
        take: updatedRecord.take,
        reel: updatedRecord.reel,
        camera: detectedCamera,
        clipIndex: clipIdx,
      );
      if (clip.originalFilePath != null) {
        _livePastedOverrides[clip.originalFilePath!] = convName;
        _livePastedLineNumbers[clip.originalFilePath!] = clipIdx;
      }
      final rawLines = _conventionEditorController.text.split(RegExp(r'\r?\n'));
      final lines = List<String>.from(rawLines);
      while (lines.length < clipIdx) {
        lines.add('');
      }
      lines[clipIdx - 1] = convName;
      _conventionEditorController.text = lines.join('\n');
    }

    await _generatePreview();

    if (_report != null && clip.originalFilePath != null) {
      final updated = _report!.proposals
          .where((p) => p.originalFilePath == clip.originalFilePath)
          .toList();
      if (updated.isNotEmpty) {
        setState(() {
          _selectedStudioClip = updated.first;
        });
      }
    }

    _showNotification('Clip vinculado a la toma de Cámara $detectedCamera');
  }

  Widget _buildCompactStatusBadge(RenameProposal proposal) {
    if (proposal.originalFilePath != null &&
        _duplicateClipConflicts.containsKey(proposal.originalFilePath)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Conflicto',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    if (proposal.status == ProposalStatus.alreadyRenamed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green.shade700,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Renombrado',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    if (_hasUnappliedTextOverride(proposal)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.purple.shade700,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          '✓ Texto',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    Color color = Colors.grey;
    String label = 'Pendiente';
    switch (proposal.status) {
      case ProposalStatus.ready:
        color = Colors.green;
        label = 'Listo';
        break;
      case ProposalStatus.missingFile:
        color = Colors.amber.shade800;
        label = 'Falta';
        break;
      case ProposalStatus.unmatchedClip:
        color = Colors.orange;
        label = 'No reg.';
        break;
      case ProposalStatus.conflict:
        color = Colors.red;
        label = 'Conflicto';
        break;
      case ProposalStatus.renamed:
      case ProposalStatus.alreadyRenamed:
        color = Colors.green.shade700;
        label = 'Renombrado';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String? _findCompanionXmlPath(RenameProposal clip) {
    if (clip.companionFilePath != null && clip.companionFilePath!.isNotEmpty) {
      return clip.companionFilePath;
    }
    if (_report == null || clip.originalFilePath == null) return null;
    final videoStem = p
        .basenameWithoutExtension(clip.originalFilePath!)
        .toUpperCase();
    for (final pItem in _report!.proposals) {
      if (pItem.isCompanionFile && pItem.originalFilePath != null) {
        final xmlStem = p
            .basenameWithoutExtension(pItem.originalFilePath!)
            .toUpperCase();
        if (xmlStem == videoStem ||
            xmlStem == '${videoStem}M01' ||
            videoStem == '${xmlStem}M01' ||
            pItem.companionFilePath == clip.originalFilePath) {
          return pItem.originalFilePath;
        }
      }
    }
    return null;
  }

  Widget _buildXmlBadge(RenameProposal clip, ThemeData theme, bool isDark) {
    final companionPath = _findCompanionXmlPath(clip);
    final hasXml = companionPath != null;
    final xmlBasename = hasXml ? p.basename(companionPath) : null;

    return Tooltip(
      message: hasXml
          ? 'Sidecar XML: $xmlBasename'
          : 'Sin archivo XML complementario',
      child: Container(
        key: ValueKey(
          'xml_badge_${clip.originalFilePath ?? clip.proposedFileName}',
        ),
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: hasXml
              ? (isDark
                    ? Colors.green.shade900.withValues(alpha: 0.35)
                    : Colors.green.shade50)
              : (isDark
                    ? Colors.grey.shade800.withValues(alpha: 0.3)
                    : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: hasXml
                ? (isDark ? Colors.green.shade600 : Colors.green.shade400)
                : (isDark ? Colors.grey.shade700 : Colors.grey.shade400),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 11,
              color: hasXml
                  ? (isDark ? Colors.green.shade300 : Colors.green.shade700)
                  : theme.hintColor,
            ),
            const SizedBox(width: 3),
            Text(
              hasXml ? 'XML' : 'Sin XML',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: hasXml
                    ? (isDark ? Colors.green.shade300 : Colors.green.shade700)
                    : theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanionBadges(
    RenameProposal clip,
    ThemeData theme,
    bool isDark,
  ) {
    final List<Widget> badges = [];

    // 1. XML badge (preserves original key and structure for existing tests)
    badges.add(_buildXmlBadge(clip, theme, isDark));

    // 2. Discover companion files
    if (_report != null && clip.originalFilePath != null) {
      final clipPath = clip.originalFilePath!;
      final companions = _report!.proposals
          .where((p) => p.isCompanionFile && (p.companionFilePath == clipPath))
          .toList();

      bool hasLrv = false;
      bool hasThm = false;
      int extraCount = 0;

      for (final comp in companions) {
        final ext = p
            .extension(comp.originalFilePath ?? comp.proposedFileName)
            .toLowerCase();
        if (ext == '.lrv') {
          hasLrv = true;
        } else if (ext == '.thm') {
          hasThm = true;
        } else if (ext != '.xml') {
          extraCount++;
        }
      }

      if (hasLrv) {
        badges.add(const SizedBox(width: 4));
        badges.add(
          Tooltip(
            message: 'Proxy de cámara vinculado (.LRV)',
            child: Container(
              key: ValueKey(
                'lrv_badge_${clip.originalFilePath ?? clip.proposedFileName}',
              ),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF064E3B).withValues(alpha: 0.4)
                    : const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF059669)
                      : const Color(0xFF10B981),
                  width: 0.8,
                ),
              ),
              child: Text(
                'LRV',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? const Color(0xFF34D399)
                      : const Color(0xFF047857),
                ),
              ),
            ),
          ),
        );
      }

      if (hasThm) {
        badges.add(const SizedBox(width: 4));
        badges.add(
          Tooltip(
            message: 'Miniatura de cámara vinculada (.THM)',
            child: Container(
              key: ValueKey(
                'thm_badge_${clip.originalFilePath ?? clip.proposedFileName}',
              ),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF78350F).withValues(alpha: 0.35)
                    : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFFD97706)
                      : const Color(0xFFF59E0B),
                  width: 0.8,
                ),
              ),
              child: Text(
                'THM',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? const Color(0xFFFBBF24)
                      : const Color(0xFFB45309),
                ),
              ),
            ),
          ),
        );
      }

      if (extraCount > 0) {
        badges.add(const SizedBox(width: 4));
        badges.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '+$extraCount',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        );
      }
    }

    return Row(mainAxisSize: MainAxisSize.min, children: badges);
  }

  Widget _buildStudioFileDetailsHeader(
    RenameProposal clip,
    ThemeData theme,
    bool isDark,
  ) {
    String folderName = '—';
    String folderPath = '—';
    String formattedSize = '—';
    String formattedDate = '—';

    if (clip.originalFilePath != null) {
      folderPath = p.dirname(clip.originalFilePath!);
      folderName = p.basename(folderPath);

      try {
        final file = File(clip.originalFilePath!);
        if (file.existsSync()) {
          final bytes = file.lengthSync();
          if (bytes >= 1024 * 1024 * 1024) {
            formattedSize =
                '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
          } else if (bytes >= 1024 * 1024) {
            formattedSize = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
          } else if (bytes >= 1024) {
            formattedSize = '${(bytes / 1024).toStringAsFixed(0)} KB';
          } else {
            formattedSize = '$bytes B';
          }

          final mod = file.lastModifiedSync();
          final d = mod.day.toString().padLeft(2, '0');
          final m = mod.month.toString().padLeft(2, '0');
          final y = mod.year.toString();
          final hh = mod.hour.toString().padLeft(2, '0');
          final mm = mod.minute.toString().padLeft(2, '0');
          formattedDate = '$d/$m/$y $hh:$mm';
        }
      } catch (_) {}
    }

    final companionPath = _findCompanionXmlPath(clip);
    final hasXml = companionPath != null;
    final xmlText = hasXml
        ? 'Sidecar: ${p.basename(companionPath)}'
        : 'Sin archivo XML';

    final textStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w500,
      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
    );

    return Container(
      key: const ValueKey('studio_file_details_header'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Tooltip(
            message: folderPath,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_open,
                  size: 13,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(folderName, style: textStyle),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storage, size: 13, color: theme.colorScheme.secondary),
              const SizedBox(width: 4),
              Text(formattedSize, style: textStyle),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today, size: 13, color: theme.hintColor),
              const SizedBox(width: 4),
              Text(formattedDate, style: textStyle),
            ],
          ),
          Tooltip(
            message: hasXml ? companionPath : 'Sin archivo XML complementario',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.integration_instructions,
                  size: 13,
                  color: hasXml ? Colors.green.shade600 : theme.hintColor,
                ),
                const SizedBox(width: 4),
                Text(
                  xmlText,
                  style: textStyle.copyWith(
                    color: hasXml
                        ? (isDark
                              ? Colors.green.shade300
                              : Colors.green.shade700)
                        : theme.hintColor,
                    fontWeight: hasXml ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAndSyncTimecodes(DryRunReport report) async {
    if (!mounted || _project.log.records.isEmpty) return;

    final tcProposals = report.proposals.where((p) {
      return !p.isCompanionFile &&
          p.associatedRecord != null &&
          p.fileTcIn != null &&
          p.fileTcIn!.trim().isNotEmpty;
    }).toList();

    if (tcProposals.isEmpty) return;

    final recordsMap = {for (final r in _project.log.records) r.id: r};
    final emptyTcRecordsToUpdate = <String, (String, String?)>{};
    final differingTcRecordsToUpdate = <String, (String, String?)>{};
    String? sampleDifferingTc;

    for (final prop in tcProposals) {
      final rec = recordsMap[prop.associatedRecord!.id];
      if (rec == null) continue;
      final fileIn = prop.fileTcIn!.trim();
      final fileOut = prop.fileTcOut?.trim();

      final recTcIn = (rec.tcIn ?? '').trim();
      if (recTcIn.isEmpty) {
        emptyTcRecordsToUpdate[rec.id] = (fileIn, fileOut);
      } else if (recTcIn != fileIn) {
        differingTcRecordsToUpdate[rec.id] = (fileIn, fileOut);
        sampleDifferingTc ??= fileIn;
      }
    }

    bool shouldUpdateDiffering = false;
    if (differingTcRecordsToUpdate.isNotEmpty && mounted) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Actualizar Timecodes desde Archivos'),
          content: Text(
            'Se detectaron timecodes en los archivos importados (ej. TC In: $sampleDifferingTc). '
            '¿Deseas actualizar la bitácora con los timecodes de los archivos de video?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No, mantener bitácora'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sí, actualizar timecodes'),
            ),
          ],
        ),
      );
      shouldUpdateDiffering = confirm == true;
    }

    bool updatedAny = false;
    final updatedRecords = _project.log.records.map((r) {
      if (emptyTcRecordsToUpdate.containsKey(r.id)) {
        final pair = emptyTcRecordsToUpdate[r.id]!;
        updatedAny = true;
        return r.copyWith(tcIn: pair.$1, tcOut: pair.$2 ?? r.tcOut);
      } else if (shouldUpdateDiffering &&
          differingTcRecordsToUpdate.containsKey(r.id)) {
        final pair = differingTcRecordsToUpdate[r.id]!;
        updatedAny = true;
        return r.copyWith(tcIn: pair.$1, tcOut: pair.$2 ?? r.tcOut);
      }
      return r;
    }).toList();

    if (updatedAny) {
      setState(() {
        _project = _project.copyWith(
          log: _project.log.copyWith(records: updatedRecords),
        );
        _isDirty = true;
      });
      await _generatePreview();
    }
  }

  Widget _buildStudioMediaList() {
    final mediaClips = _studioMediaClips;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasFocus = _studioMediaListFocusNode.hasFocus;

    return Focus(
      focusNode: _studioMediaListFocusNode,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: hasFocus
                ? theme.colorScheme.primary
                : theme.dividerColor.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.video_library_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Clips de Medios (${mediaClips.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: mediaClips.isEmpty
                  ? Center(
                      child: Text(
                        'Sin clips de video',
                        style: TextStyle(color: theme.hintColor, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      controller: _studioMediaListScrollController,
                      itemCount: mediaClips.length,
                      itemBuilder: (context, i) {
                        final clip = mediaClips[i];
                        final isSelected =
                            _selectedStudioClip?.originalFilePath ==
                            clip.originalFilePath;
                        final fileName = clip.originalFilePath != null
                            ? p.basename(clip.originalFilePath!)
                            : clip.proposedFileName;
                        final reel = _getProposalReel(clip);
                        final clipNum = ClipMatcherService.extractClipNumber(
                          fileName,
                        );
                        final isLiveMatched =
                            clip.originalFilePath != null &&
                            _livePastedOverrides.containsKey(
                              clip.originalFilePath,
                            ) &&
                            !_duplicateClipConflicts.containsKey(
                              clip.originalFilePath,
                            );
                        final isConflict =
                            clip.originalFilePath != null &&
                            _duplicateClipConflicts.containsKey(
                              clip.originalFilePath,
                            );

                        Color? rowBg;
                        if (isSelected) {
                          rowBg = theme.colorScheme.primary.withValues(
                            alpha: isDark ? 0.25 : 0.15,
                          );
                        } else if (isLiveMatched) {
                          rowBg = Colors.green.withValues(alpha: 0.08);
                        }

                        return InkWell(
                          key: ValueKey('studio_clip_$i'),
                          onTap: () {
                            _studioMediaListFocusNode.requestFocus();
                            _selectStudioClip(clip);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: rowBg,
                              border: Border(
                                bottom: BorderSide(
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                                left: isSelected
                                    ? BorderSide(
                                        color: theme.colorScheme.primary,
                                        width: 3,
                                      )
                                    : BorderSide.none,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isConflict
                                      ? Icons.warning_amber_rounded
                                      : (isLiveMatched
                                            ? Icons.check_circle
                                            : Icons.movie_outlined),
                                  size: 18,
                                  color: isConflict
                                      ? Colors.red
                                      : (isLiveMatched
                                            ? Colors.green
                                            : (isSelected
                                                  ? theme.colorScheme.primary
                                                  : theme.hintColor)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (_project.activeCamera
                                                  .toUpperCase() ==
                                              'ALL') ...[
                                            Container(
                                              margin: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 5,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.primary
                                                    .withValues(
                                                      alpha: isDark
                                                          ? 0.3
                                                          : 0.15,
                                                    ),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                border: Border.all(
                                                  color: theme
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.5),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(
                                                '[CAM ${ClipMatcherService.extractCamera(clip.originalFilePath ?? fileName)}]',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                          ],
                                          Expanded(
                                            child: Text(
                                              fileName,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                color: isSelected
                                                    ? theme.colorScheme.primary
                                                    : null,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          _buildCompanionBadges(
                                            clip,
                                            theme,
                                            isDark,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Reel: $reel | Clip: #$clipNum${clip.associatedRecord != null ? ' | Esc: ${clip.associatedRecord!.scene} T: ${clip.associatedRecord!.take}' : ''}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: theme.hintColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (clip.status ==
                                          ProposalStatus.alreadyRenamed) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          _getOriginalClipSubtitle(clip),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green.shade600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ] else if (clip.status ==
                                              ProposalStatus.ready &&
                                          clip.proposedFileName.toLowerCase() !=
                                              fileName.toLowerCase()) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          '➜ ${clip.proposedFileName}',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? theme.colorScheme.primary
                                                : Colors.green.shade700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                _buildCompactStatusBadge(clip),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildStudioBroadcastSlateMonitor(
    RenameProposal? clip,
    ThemeData theme,
    bool isDark, {
    bool isCanonRaw = false,
    bool isWav = false,
    String? playbackError,
  }) {
    if (clip == null) return const SizedBox.shrink();
    final originalPath = clip.originalFilePath;
    final originalName = originalPath != null
        ? p.basename(originalPath)
        : 'Clip';
    final ext = originalPath != null
        ? p.extension(originalPath).toUpperCase()
        : '';
    final formattedSize = _formatFileSize(originalPath);
    final tcIn = clip.fileTcIn ?? '?';
    final tcOut = clip.fileTcOut ?? '?';
    final posterFrame = MediaProxyUtils.findPosterFrame(originalPath);

    final bgColor = isDark ? const Color(0xFF0C0E14) : const Color(0xFFF8FAFC);
    final cardBorderColor = isDark
        ? const Color(0xFF1E2230)
        : const Color(0xFFE2E8F0);
    final cardBgColor = isDark ? const Color(0xFF121520) : Colors.white;

    final Key hudKey = isCanonRaw
        ? const ValueKey('studio_canon_raw_hud')
        : (isWav
              ? const ValueKey('studio_audio_raw_hud')
              : const ValueKey('studio_broadcast_slate_monitor'));

    final cardContent = Container(
      key: hudKey,
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
              : (isWav
                    ? (isDark
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                          : const Color(0xFF0284C7))
                    : cardBorderColor),
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
                color: isDark
                    ? Colors.amber.shade900.withValues(alpha: 0.35)
                    : const Color(0xFFFEF3C7),
                border: Border.all(
                  color: isDark
                      ? Colors.amber.shade500
                      : const Color(0xFFD97706),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.camera_alt_outlined,
                size: 46,
                color: isDark ? Colors.amber.shade300 : const Color(0xFFB45309),
              ),
            )
          else if (isWav)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF00E5FF).withValues(alpha: 0.12)
                    : const Color(0xFFE0F2FE),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                      : const Color(0xFF38BDF8),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.audiotrack_rounded,
                size: 46,
                color: Color(0xFF00E5FF),
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
                      key: const ValueKey('studio_canon_raw_badge'),
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
                      key: const ValueKey('studio_smpte_live_badge'),
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
                : (isWav
                      ? [
                          Container(
                            key: const ValueKey('studio_format_badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(
                                      0xFF00E5FF,
                                    ).withValues(alpha: 0.15)
                                  : const Color(0xFFE0F7FA),
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
                            child: const Text(
                              'BROADCAST WAV · BWF',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                                letterSpacing: 1.1,
                                color: Color(0xFF00E5FF),
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
                                  ? const Color(
                                      0xFF00E5FF,
                                    ).withValues(alpha: 0.12)
                                  : const Color(0xFFE0F7FA),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark
                                    ? const Color(
                                        0xFF00E5FF,
                                      ).withValues(alpha: 0.6)
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
                                    ? Colors.amber.shade500.withValues(
                                        alpha: 0.6,
                                      )
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
                        ]),
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
                height: 12,
                width: 1,
                color: isDark ? Colors.white24 : Colors.grey.shade400,
              ),
              const SizedBox(width: 12),
              Text(
                'Formato nativo: $ext',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF00E5FF).withValues(alpha: 0.08)
                  : const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF00E5FF).withValues(alpha: 0.3)
                    : const Color(0xFF86EFAC),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 14,
                  color: isDark
                      ? const Color(0xFF00E5FF)
                      : const Color(0xFF16A34A),
                ),
                const SizedBox(width: 6),
                Text(
                  'Timecode: $tcIn \u2192 $tcOut',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: isDark
                        ? const Color(0xFF00E5FF)
                        : const Color(0xFF15803D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              isCanonRaw
                  ? 'Reproduciendo audio nativo PCM (24-bit) y código de tiempo SMPTE sincronizado. El formato CRAW de sensor opera en modo claqueta de audio.'
                  : (isWav
                        ? 'Monitoreo de pistas multicanal PCM de audio de producción BWF con Timecode SMPTE sincronizado.'
                        : 'Metadatos y Timecode SMPTE sincronizados. El códec nativo no requiere decodificación visual para reconciliación y renombrado.'),
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (isCanonRaw) ...[
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: _studioIsPlayingNotifier,
              builder: (context, isPlaying, _) {
                return ValueListenableBuilder<Duration>(
                  valueListenable: _studioPositionNotifier,
                  builder: (context, position, _) {
                    return Container(
                      key: const ValueKey('studio_craw_audio_waveform'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF080C14)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isPlaying
                              ? const Color(0xFF00E5FF).withValues(alpha: 0.4)
                              : (isDark
                                    ? Colors.white12
                                    : const Color(0xFFCBD5E1)),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPlaying
                                ? Icons.graphic_eq
                                : Icons.volume_mute_outlined,
                            size: 15,
                            color: isPlaying
                                ? const Color(0xFF00E5FF)
                                : Colors.white38,
                          ),
                          const SizedBox(width: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(14, (i) {
                              final factor = isPlaying
                                  ? ((math.sin(
                                                  i * 0.7 +
                                                      (position.inMilliseconds /
                                                          180.0),
                                                ) *
                                                0.45 +
                                            0.55))
                                        .clamp(0.2, 1.0)
                                  : 0.18;
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1.5,
                                ),
                                width: 3,
                                height: (18 * factor).clamp(3.0, 18.0),
                                decoration: BoxDecoration(
                                  color: isPlaying
                                      ? const Color(0xFF00E5FF)
                                      : Colors.white24,
                                  borderRadius: BorderRadius.circular(1.5),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isPlaying
                                ? 'PCM 24-BIT EN REPRODUCCIÓN'
                                : 'AUDIO EN ESPERA',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: isPlaying
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
          if (isWav) ...[
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('studio_audio_waveform'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF080C14)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                ),
              ),
              child: ValueListenableBuilder<Duration>(
                valueListenable: _studioPositionNotifier,
                builder: (context, position, _) {
                  final liveSmpte = _computeLiveSmpte(
                    position,
                    clip.fileTcIn,
                    _project.log.metadata.frameRate,
                  );
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.graphic_eq,
                        size: 15,
                        color: Color(0xFF00E5FF),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'SMPTE: $liveSmpte',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        key: const ValueKey('studio_hud_volume'),
                        icon: const Icon(Icons.volume_up, size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {},
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('studio_audio_track_indicators'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark ? Colors.black45 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CH 1 [L]',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'CH 2 [R]',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!isCanonRaw &&
              !isWav &&
              playbackError != null &&
              playbackError.isNotEmpty) ...[
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
        key: hudKey,
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
            // Top-left floating EVF badges
            Positioned(
              top: 12,
              left: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    key: const ValueKey('studio_canon_raw_badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark
                            ? Colors.amber.shade500.withValues(alpha: 0.8)
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
                    key: const ValueKey('studio_smpte_live_badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF00E5FF).withValues(alpha: 0.7)
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
              bottom: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
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
      );
    }

    return Container(color: bgColor, child: slateBody);
  }

  Widget _buildStudioCenterInspector() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final clip = _selectedStudioClip;
    final hasFocus = _studioInspectorFocusNode.hasFocus;

    if (clip == null) {
      return Focus(
        focusNode: _studioInspectorFocusNode,
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: hasFocus
                  ? theme.colorScheme.primary
                  : theme.dividerColor.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.video_library_outlined,
                  size: 56,
                  color: theme.hintColor.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ningún clip seleccionado',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'Selecciona un archivo de la lista izquierda para previsualizarlo e inspeccionar su claqueta.',
                  style: TextStyle(color: theme.hintColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final originalName = clip.originalFilePath != null
        ? p.basename(clip.originalFilePath!)
        : '—';
    final proposedName = _computeStudioProposedBanner(clip);
    final tcIn = clip.fileTcIn ?? '00:00:00:00';
    final tcOut = clip.fileTcOut ?? '00:00:00:00';
    final originalPath = clip.originalFilePath;
    final isCrm =
        originalPath != null && MediaProxyUtils.isCanonRaw(originalPath);
    final isWav =
        originalPath != null && originalPath.toLowerCase().endsWith('.wav');
    final playbackError = _studioPlaybackErrorNotifier.value;
    final isDecoderErr = MediaProxyUtils.isRawDecoderError(playbackError);
    final proxyPath = _studioLinkedProxyPathNotifier.value;
    final hasLinkedProxy = proxyPath != null;
    final isPlayingProxy = hasLinkedProxy && _studioActiveIsProxyNotifier.value;
    final isCanonRawSlate =
        (isCrm && !isPlayingProxy) || (isDecoderErr && isCrm);
    final isSlateMonitor =
        isCanonRawSlate || isWav || (playbackError != null && !isDecoderErr);
    final hasVideo =
        originalPath != null &&
        _isPlayableVideo(originalPath) &&
        _studioVideoController != null &&
        !isSlateMonitor;

    final hasVisibleFlags = _project.showMos || _project.showTf;

    final detectedCamera = clip.originalFilePath != null
        ? ClipMatcherService.extractCamera(
            clip.originalFilePath!,
            fallback: _project.activeCamera,
          )
        : _project.activeCamera;

    final canStepFrame = _studioPlayer != null && !isSlateMonitor && !isCrm;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final isCompactVertical = availableHeight < 620;
        final isScrollableMode = availableHeight < 560;
        final cardPadding = isCompactVertical ? 8.0 : 12.0;
        final sectionSpacing = isCompactVertical ? 4.0 : 6.0;
        final fieldVerticalPadding = isCompactVertical ? 4.0 : 8.0;

        final List<Widget> dynamicSlateFields = [];
        for (final elem in _project.bitacoraElementOrder) {
          if (elem == 'capitulo' && _project.showChapter) {
            dynamicSlateFields.add(
              Expanded(
                flex: 2,
                child: TextField(
                  key: const ValueKey('studio_slate_chapter_field'),
                  controller: _studioChapterController,
                  focusNode: _studioChapterFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Cap',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: fieldVerticalPadding,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (_) => _onStudioSlateFieldChanged(),
                ),
              ),
            );
          } else if (elem == 'escena') {
            dynamicSlateFields.add(
              Expanded(
                flex: 2,
                child: TextField(
                  key: const ValueKey('studio_slate_scene_field'),
                  controller: _studioSceneController,
                  focusNode: _studioSceneFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Escena',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: fieldVerticalPadding,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (_) => _onStudioSlateFieldChanged(),
                ),
              ),
            );
          } else if (elem == 'plano' && _project.showPlane) {
            dynamicSlateFields.add(
              Expanded(
                flex: 2,
                child: TextField(
                  key: const ValueKey('studio_slate_plane_field'),
                  controller: _studioPlaneController,
                  focusNode: _studioPlaneFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Plano',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: fieldVerticalPadding,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (_) => _onStudioSlateFieldChanged(),
                ),
              ),
            );
          } else if (elem == 'toma') {
            dynamicSlateFields.add(
              Expanded(
                flex: 2,
                child: TextField(
                  key: const ValueKey('studio_slate_take_field'),
                  controller: _studioTakeController,
                  focusNode: _studioTakeFocusNode,
                  decoration: InputDecoration(
                    labelText: 'Toma',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: fieldVerticalPadding,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (_) => _onStudioSlateFieldChanged(),
                ),
              ),
            );
          }
        }

        dynamicSlateFields.add(
          Expanded(
            flex: 2,
            child: TextField(
              key: const ValueKey('studio_slate_reel_field'),
              controller: _studioReelController,
              focusNode: _studioReelFocusNode,
              decoration: InputDecoration(
                labelText: 'Reel',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: fieldVerticalPadding,
                ),
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (_) => _onStudioSlateFieldChanged(),
            ),
          ),
        );

        final videoPlayerContainer = Container(
          key: const ValueKey('studio_video_player_container'),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (isSlateMonitor)
                _buildStudioBroadcastSlateMonitor(
                  clip,
                  theme,
                  isDark,
                  isCanonRaw: isCanonRawSlate,
                  isWav: isWav,
                  playbackError: playbackError,
                )
              else ...[
                ClipRect(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        if (pointerSignal.scrollDelta.dy < 0) {
                          _studioZoomIn(
                            focalPoint: pointerSignal.localPosition,
                          );
                        } else if (pointerSignal.scrollDelta.dy > 0) {
                          _studioZoomOut(
                            focalPoint: pointerSignal.localPosition,
                          );
                        }
                      }
                    },
                    child: GestureDetector(
                      key: const ValueKey('studio_video_gesture_detector'),
                      onTap: () => _studioWorkspaceFocusNode.requestFocus(),
                      onDoubleTap: _resetStudioZoom,
                      child: MouseRegion(
                        cursor: _studioCurrentZoom > 1.05
                            ? SystemMouseCursors.grab
                            : SystemMouseCursors.basic,
                        onHover: (event) {
                          _studioHoveredPointerPosition = event.localPosition;
                        },
                        onExit: (_) {
                          _studioHoveredPointerPosition = null;
                        },
                        child: InteractiveViewer(
                          transformationController: _studioZoomController,
                          minScale: 1.0,
                          maxScale: 5.0,
                          panEnabled: true,
                          scaleEnabled: true,
                          trackpadScrollCausesScale: true,
                          boundaryMargin: const EdgeInsets.all(600),
                          clipBehavior: Clip.none,
                          child: Center(
                            child: hasVideo
                                ? Video(
                                    controller: _studioVideoController!,
                                    controls: NoVideoControls,
                                    fit: BoxFit.contain,
                                  )
                                : Container(
                                    color: Colors.black,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.movie_filter_rounded,
                                            size: 52,
                                            color: Colors.white38,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            originalName,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Timecode: $tcIn → $tcOut',
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              color: Colors.white54,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                if (isPlayingProxy)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      key: const ValueKey('studio_proxy_linked_badge'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF065F46),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF10B981),
                          width: 1.2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.link,
                            size: 12,
                            color: Color(0xFF34D399),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '[PROXY VINCULADO: ${p.basename(proxyPath)}]',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD1FAE5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Floating Magnifier HUD Overlay
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    key: const ValueKey('studio_magnifier_hud'),
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
                          key: const ValueKey('studio_zoom_out_button'),
                          icon: const Icon(
                            Icons.zoom_out,
                            size: 16,
                            color: Colors.white,
                          ),
                          tooltip: 'Alejar',
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: _studioCurrentZoom > 1.05
                              ? _studioZoomOut
                              : null,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${(_studioCurrentZoom * 100).round()}%',
                          key: const ValueKey('studio_zoom_text'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          key: const ValueKey('studio_zoom_in_button'),
                          icon: const Icon(
                            Icons.zoom_in,
                            size: 16,
                            color: Colors.white,
                          ),
                          tooltip: 'Acercar',
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: _studioCurrentZoom < 4.95
                              ? _studioZoomIn
                              : null,
                        ),
                        if (_studioCurrentZoom > 1.05) ...[
                          Container(
                            height: 16,
                            width: 1,
                            color: Colors.white24,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('studio_zoom_reset_button'),
                            icon: const Icon(
                              Icons.restart_alt,
                              size: 16,
                              color: Colors.white,
                            ),
                            tooltip: 'Restablecer 100%',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            onPressed: _resetStudioZoom,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Tactile Shutter Flash Overlay
                ValueListenableBuilder<bool>(
                  valueListenable: _studioShutterFlashNotifier,
                  builder: (context, flash, _) {
                    return IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: flash ? 0.35 : 0.0,
                        duration: const Duration(milliseconds: 120),
                        child: Container(color: Colors.white),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );

        final videoAreaWidget = isScrollableMode
            ? SizedBox(
                height: (availableHeight * 0.42).clamp(150.0, 260.0),
                child: videoPlayerContainer,
              )
            : Expanded(child: videoPlayerContainer);

        final mainColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Proposal Name Banner (Top of center pane, above video player)
            Container(
              key: const ValueKey('studio_proposed_banner'),
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: isCompactVertical ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.drive_file_rename_outline,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Propuesta: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      proposedName,
                      key: const ValueKey('studio_proposed_banner_text'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: sectionSpacing),
            _buildStudioFileDetailsHeader(clip, theme, isDark),
            SizedBox(height: sectionSpacing),

            // 2. Video Player Area
            videoAreaWidget,
            SizedBox(height: sectionSpacing),

            // Dedicated Studio Transport Bar
            Container(
              key: const ValueKey('studio_transport_bar'),
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: isCompactVertical ? 2 : 4,
              ),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF1E1E24)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Seek Scrubber Slider
                  ValueListenableBuilder<Duration>(
                    valueListenable: _studioDurationNotifier,
                    builder: (context, duration, _) {
                      return ValueListenableBuilder<Duration>(
                        valueListenable: _studioPositionNotifier,
                        builder: (context, position, _) {
                          final durationMs = duration.inMilliseconds;
                          final positionMs = position.inMilliseconds;
                          final sliderValue = _studioIsDraggingSlider
                              ? _studioDragSliderValue
                              : (durationMs > 0
                                    ? (positionMs / durationMs).clamp(
                                        0.0,
                                        1.0,
                                      )
                                    : 0.0);

                          return SliderTheme(
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
                              key: const ValueKey('studio_scrubber_slider'),
                              value: sliderValue,
                              onChanged: (val) {
                                setState(() {
                                  _studioIsDraggingSlider = true;
                                  _studioDragSliderValue = val;
                                });
                              },
                              onChangeEnd: (val) {
                                final targetMs = (val * durationMs).round();
                                final targetDuration = Duration(
                                  milliseconds: targetMs,
                                );
                                _studioPlayer?.seek(targetDuration);
                                setState(() {
                                  _studioIsDraggingSlider = false;
                                  _studioPositionNotifier.value =
                                      targetDuration;
                                });
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      // Cluster 1: Playback Transport Buttons
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Frame Step Back (,)
                          IconButton(
                            key: const ValueKey('studio_frame_back_button'),
                            icon: const Icon(Icons.chevron_left, size: 20),
                            tooltip: 'Fotograma anterior (,)',
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.all(4),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: canStepFrame
                                ? () => _stepStudioFrame(forward: false)
                                : null,
                          ),
                          const SizedBox(width: 2),
                          // Play / Pause
                          ValueListenableBuilder<bool>(
                            valueListenable: _studioIsPlayingNotifier,
                            builder: (context, isPlaying, _) {
                              return IconButton(
                                key: const ValueKey(
                                  'studio_play_pause_button',
                                ),
                                icon: Icon(
                                  isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_fill,
                                  size: 22,
                                  color: theme.colorScheme.primary,
                                ),
                                tooltip: isPlaying ? 'Pausar' : 'Reproducir',
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.all(4),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () {
                                  if (_studioPlayer != null) {
                                    _studioPlayer!.playOrPause();
                                  } else {
                                    _studioIsPlayingNotifier.value =
                                        !_studioIsPlayingNotifier.value;
                                  }
                                },
                              );
                            },
                          ),
                          const SizedBox(width: 2),
                          // Frame Step Forward (.)
                          IconButton(
                            key: const ValueKey('studio_frame_forward_button'),
                            icon: const Icon(Icons.chevron_right, size: 20),
                            tooltip: 'Fotograma siguiente (.)',
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.all(4),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: canStepFrame
                                ? () => _stepStudioFrame(forward: true)
                                : null,
                          ),
                          const SizedBox(width: 4),
                          // 5s jump back
                          IconButton(
                            key: const ValueKey('studio_replay_5_button'),
                            icon: const Icon(Icons.replay_5, size: 18),
                            tooltip: 'Retroceder 5s',
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.all(4),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              final target =
                                  _studioPositionNotifier.value -
                                  const Duration(seconds: 5);
                              final clamped = target < Duration.zero
                                  ? Duration.zero
                                  : target;
                              _studioPlayer?.seek(clamped);
                              _studioPositionNotifier.value = clamped;
                            },
                          ),
                          const SizedBox(width: 2),
                          // 5s jump forward
                          IconButton(
                            key: const ValueKey('studio_forward_5_button'),
                            icon: const Icon(Icons.forward_5, size: 18),
                            tooltip: 'Avanzar 5s',
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.all(4),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              final max = _studioDurationNotifier.value;
                              final target =
                                  _studioPositionNotifier.value +
                                  const Duration(seconds: 5);
                              final clamped =
                                  max > Duration.zero && target > max
                                  ? max
                                  : target;
                              _studioPlayer?.seek(clamped);
                              _studioPositionNotifier.value = clamped;
                            },
                          ),
                          const SizedBox(width: 6),
                          // Elapsed / Duration text
                          ValueListenableBuilder<Duration>(
                            valueListenable: _studioDurationNotifier,
                            builder: (context, duration, _) {
                              return ValueListenableBuilder<Duration>(
                                valueListenable: _studioPositionNotifier,
                                builder: (context, position, _) {
                                  return Text(
                                    '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                    key: const ValueKey(
                                      'studio_duration_text',
                                    ),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10.5,
                                      color: theme.hintColor,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      // Cluster 2: SMPTE, Still Capture, Proxy & Volume Controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Live Running SMPTE Timecode Badge
                          ValueListenableBuilder<Duration>(
                            valueListenable: _studioPositionNotifier,
                            builder: (context, position, _) {
                              final liveSmpte = _computeLiveSmpte(
                                position,
                                clip.fileTcIn,
                                _project.log.metadata.frameRate,
                              );
                              return Container(
                                key: const ValueKey(
                                  'studio_live_smpte_badge',
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.access_time_rounded,
                                      size: 11,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'SMPTE: $liveSmpte',
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontFamily: 'monospace',
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          // Still Capture Button
                          IconButton(
                            key: const ValueKey('studio_capture_still_button'),
                            icon: _isCapturingStill
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.camera_alt_outlined, size: 16),
                            tooltip: _isCapturingStill
                                ? 'Capturando fotograma...'
                                : 'Capturar fotograma (Guardar en Escritorio)',
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.all(4),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: _isCapturingStill || _studioPlayer == null
                                ? null
                                : _captureStudioStill,
                          ),
                        ],
                      ),
                      // Cluster 3: Proxy & Volume Controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder<String?>(
                            valueListenable: _studioLinkedProxyPathNotifier,
                            builder: (context, linkedProxy, _) {
                              if (linkedProxy == null) {
                                return const SizedBox.shrink();
                              }
                              return ValueListenableBuilder<bool>(
                                valueListenable: _studioActiveIsProxyNotifier,
                                builder: (context, activeIsProxy, _) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Tooltip(
                                      message: activeIsProxy
                                          ? 'Reproduciendo proxy vinculado (clic para original)'
                                          : 'Reproduciendo archivo maestro (clic para proxy)',
                                      child: InkWell(
                                        key: const ValueKey(
                                          'studio_proxy_toggle_button',
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          4,
                                        ),
                                        onTap: () {
                                          if (_selectedStudioClip
                                                  ?.originalFilePath !=
                                              null) {
                                            final pos =
                                                _studioPositionNotifier.value;
                                            _studioActiveIsProxyNotifier
                                                    .value =
                                                !activeIsProxy;
                                            _playStudioMedia(
                                              _selectedStudioClip!
                                                  .originalFilePath!,
                                              seekPosition: pos,
                                              forceDirectMaster:
                                                  !_studioActiveIsProxyNotifier
                                                      .value,
                                            );
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: activeIsProxy
                                                ? const Color(0xFF065F46)
                                                : const Color(0xFF1E293B),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                              color: activeIsProxy
                                                  ? const Color(0xFF10B981)
                                                  : Colors.white38,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                activeIsProxy
                                                    ? Icons
                                                          .high_quality_outlined
                                                    : Icons.videocam_outlined,
                                                size: 11,
                                                color: activeIsProxy
                                                    ? const Color(0xFF34D399)
                                                    : Colors.white70,
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                activeIsProxy
                                                    ? 'PROXY'
                                                    : 'ORIGINAL',
                                                style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: activeIsProxy
                                                      ? const Color(
                                                          0xFFD1FAE5,
                                                        )
                                                      : Colors.white70,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          // Volume toggle & compact slider
                          ValueListenableBuilder<bool>(
                            valueListenable: _studioIsMutedNotifier,
                            builder: (context, isMuted, _) {
                              return ValueListenableBuilder<double>(
                                valueListenable: _studioVolumeNotifier,
                                builder: (context, volume, _) {
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        key: const ValueKey(
                                          'studio_volume_button',
                                        ),
                                        icon: Icon(
                                          isMuted || volume <= 0.0
                                              ? Icons.volume_off
                                              : (volume < 50
                                                    ? Icons.volume_down
                                                    : Icons.volume_up),
                                          size: 16,
                                        ),
                                        tooltip: isMuted
                                            ? 'Activar sonido'
                                            : 'Silenciar',
                                        visualDensity: VisualDensity.compact,
                                        style: IconButton.styleFrom(
                                          minimumSize: Size.zero,
                                          padding: const EdgeInsets.all(4),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () {
                                          if (isMuted) {
                                            final target =
                                                _studioPreMuteVolume > 0
                                                ? _studioPreMuteVolume
                                                : 100.0;
                                            _studioPlayer?.setVolume(target);
                                            _studioVolumeNotifier.value =
                                                target;
                                            _studioIsMutedNotifier.value =
                                                false;
                                          } else {
                                            _studioPreMuteVolume = volume;
                                            _studioPlayer?.setVolume(0.0);
                                            _studioVolumeNotifier.value = 0.0;
                                            _studioIsMutedNotifier.value =
                                                true;
                                          }
                                        },
                                      ),
                                      SizedBox(
                                        width: 36,
                                        child: SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            trackHeight: 2,
                                            thumbShape:
                                                const RoundSliderThumbShape(
                                                  enabledThumbRadius: 3,
                                                ),
                                            overlayShape:
                                                const RoundSliderOverlayShape(
                                                  overlayRadius: 6,
                                                ),
                                          ),
                                          child: Slider(
                                            key: const ValueKey(
                                              'studio_volume_slider',
                                            ),
                                            value: volume.clamp(0.0, 100.0),
                                            min: 0.0,
                                            max: 100.0,
                                            onChanged: (val) {
                                              _studioPlayer?.setVolume(val);
                                              _studioVolumeNotifier.value =
                                                  val;
                                              _studioIsMutedNotifier.value =
                                                  val <= 0.0;
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  )
                ],
              ),
            ),
            SizedBox(height: sectionSpacing),

            // 3. Editable Slate Card (Intrinsic height, not Expanded)
            Container(
              padding: EdgeInsets.all(isCompactVertical ? 6 : 10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, slateConstraints) {
                      final showCompactHeader =
                          slateConstraints.maxWidth < 850;

                      final tcBadge = Container(
                        key: const ValueKey('studio_static_tc_badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                        child: Text(
                          'TC: $tcIn → $tcOut',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );

                      final cameraBadge = Container(
                        key: const ValueKey('studio_camera_badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer
                              .withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: theme.colorScheme.secondary.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: Text(
                          'Cámara $detectedCamera',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      );

                      final unlinkTakeButton = clip.associatedRecord != null
                          ? OutlinedButton.icon(
                              key: const ValueKey(
                                'studio_unlink_take_button',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(
                                  color: Colors.redAccent,
                                  width: 1,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                textStyle: const TextStyle(fontSize: 11),
                                minimumSize: Size.zero,
                              ),
                              icon: const Icon(Icons.link_off, size: 13),
                              label: const Text('Desvincular'),
                              onPressed: () =>
                                  _unlinkStudioClip(clip, detectedCamera),
                            )
                          : null;

                      final linkTakeButton = _project.log.records.isNotEmpty
                          ? InkWell(
                              key: const ValueKey('studio_link_take_button'),
                              borderRadius: BorderRadius.circular(4),
                              onTap: () =>
                                  _openTakeLinkerDialog(clip, detectedCamera),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: theme.dividerColor.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.link,
                                      size: 13,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      clip.associatedRecord != null
                                          ? 'Cambiar Toma'
                                          : 'Vincular Toma',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : null;

                      final isSavingNow = _isStudioSaving;
                      final saveButton = ElevatedButton.icon(
                        key: const ValueKey('studio_save_slate_button'),
                        icon: isSavingNow
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary,
                                ),
                              )
                            : const Icon(
                                Icons.check_circle_outline,
                                size: 14,
                                color: Colors.green,
                              ),
                        label: Text(
                          isSavingNow ? 'Guardando...' : 'Guardado',
                          style: TextStyle(
                            fontSize: 11,
                            color: isSavingNow ? null : Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          textStyle: const TextStyle(fontSize: 11),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () => _saveStudioSlate(isAutoSave: false),
                      );

                      if (showCompactHeader) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.movie_creation_outlined,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Claqueta y Bitácora',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                cameraBadge,
                                const SizedBox(width: 6),
                                Expanded(child: tcBadge),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                ?unlinkTakeButton,
                                ?linkTakeButton,
                                saveButton,
                              ],
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Icon(
                            Icons.movie_creation_outlined,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Claqueta y Bitácora',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                          cameraBadge,
                          const SizedBox(width: 6),
                          Flexible(child: tcBadge),
                          const SizedBox(width: 8),
                          const Spacer(),
                          Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              ?unlinkTakeButton,
                              ?linkTakeButton,
                              saveButton,
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: sectionSpacing),
                  FocusTraversalGroup(
                    policy: WidgetOrderTraversalPolicy(),
                    child: Row(
                      children: [
                        for (
                          int i = 0;
                          i < dynamicSlateFields.length;
                          i++
                        ) ...[
                          if (i > 0) const SizedBox(width: 6),
                          dynamicSlateFields[i],
                        ],
                      ],
                    ),
                  ),
                  if (hasVisibleFlags) ...[
                    SizedBox(height: sectionSpacing),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (_project.showMos)
                          _buildStudioFlagChip(
                            key: 'studio_flag_mos',
                            label: 'MOS',
                            selected: _studioIsMos,
                            onSelected: (val) {
                              setState(() => _studioIsMos = val);
                              _onStudioSlateFieldChanged();
                            },
                          ),
                        if (_project.showTf)
                          _buildStudioFlagChip(
                            key: 'studio_flag_tf',
                            label: 'TF (Toma Falsa)',
                            selected: _studioIsTf,
                            onSelected: (val) {
                              setState(() => _studioIsTf = val);
                              _onStudioSlateFieldChanged();
                            },
                          ),
                      ],
                    ),
                  ],
                  SizedBox(height: sectionSpacing),
                  TextField(
                    key: const ValueKey('studio_slate_notes_field'),
                    controller: _studioNotesController,
                    focusNode: _studioNotesFocusNode,
                    maxLines: 1,
                    decoration: InputDecoration(
                      labelText: 'Observaciones / Notas',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: fieldVerticalPadding,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (_) => _onStudioSlateFieldChanged(),
                  ),
                ],
              ),
            ),
          ],
        );

        return Focus(
          focusNode: _studioInspectorFocusNode,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: hasFocus
                    ? theme.colorScheme.primary
                    : theme.dividerColor.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(cardPadding),
              child: isScrollableMode
                  ? SingleChildScrollView(child: mainColumn)
                  : mainColumn,
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudioFlagChip({
    required String key,
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      key: ValueKey(key),
      label: Text(
        label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      selected: selected,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onSelected: onSelected,
    );
  }

  bool get _isTextFieldFocused {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    if (primary == _conventionEditorFocusNode ||
        primary == _studioChapterFocusNode ||
        primary == _studioSceneFocusNode ||
        primary == _studioPlaneFocusNode ||
        primary == _studioTakeFocusNode ||
        primary == _studioReelFocusNode ||
        primary == _studioNotesFocusNode) {
      return true;
    }
    final ctx = primary.context;
    if (ctx != null) {
      if (ctx.widget is EditableText ||
          ctx.findAncestorWidgetOfExactType<EditableText>() != null) {
        return true;
      }
    }
    return false;
  }

  void _toggleStudioPlay() {
    if (_studioPlayer != null) {
      _studioPlayer!.playOrPause();
    } else {
      _studioIsPlayingNotifier.value = !_studioIsPlayingNotifier.value;
    }
  }

  void _seekStudioRelative(int seconds) {
    final current = _studioPositionNotifier.value;
    final duration = _studioDurationNotifier.value;
    final delta = Duration(seconds: seconds);
    var target = current + delta;
    if (target < Duration.zero) {
      target = Duration.zero;
    } else if (duration > Duration.zero && target > duration) {
      target = duration;
    }
    _studioPlayer?.seek(target);
    _studioPositionNotifier.value = target;
  }

  List<RenameProposal> get _studioMediaClips {
    final list =
        _report?.proposals.where((p) {
          if (p.isCompanionFile) return false;
          if (p.status == ProposalStatus.missingFile) return false;
          if (p.originalFilePath == null) return false;
          return File(p.originalFilePath!).existsSync() ||
              p.originalFilePath!.startsWith('/media/');
        }).toList() ??
        [];
    list.sort((a, b) {
      final aNumStr = ClipMatcherService.extractClipNumber(
        a.originalFilePath ?? a.proposedFileName,
      );
      final bNumStr = ClipMatcherService.extractClipNumber(
        b.originalFilePath ?? b.proposedFileName,
      );
      final aNum = int.tryParse(aNumStr) ?? 999999;
      final bNum = int.tryParse(bNumStr) ?? 999999;
      final numComp = aNum.compareTo(bNum);
      if (numComp != 0) return numComp;
      return (a.originalFilePath ?? a.proposedFileName).compareTo(
        b.originalFilePath ?? b.proposedFileName,
      );
    });
    return list;
  }

  void _selectPreviousStudioClip() {
    final clips = _studioMediaClips;
    if (clips.isEmpty) return;
    if (_selectedStudioClip == null) {
      _selectStudioClip(clips.first);
      return;
    }
    final currentIndex = clips.indexWhere(
      (c) => c.originalFilePath == _selectedStudioClip!.originalFilePath,
    );
    if (currentIndex > 0) {
      final prevIndex = currentIndex - 1;
      _selectStudioClip(clips[prevIndex]);
      _scrollStudioClipIntoView(prevIndex);
    }
  }

  void _selectNextStudioClip() {
    final clips = _studioMediaClips;
    if (clips.isEmpty) return;
    if (_selectedStudioClip == null) {
      _selectStudioClip(clips.first);
      return;
    }
    final currentIndex = clips.indexWhere(
      (c) => c.originalFilePath == _selectedStudioClip!.originalFilePath,
    );
    if (currentIndex >= 0 && currentIndex < clips.length - 1) {
      final nextIndex = currentIndex + 1;
      _selectStudioClip(clips[nextIndex]);
      _scrollStudioClipIntoView(nextIndex);
    }
  }

  void _scrollStudioClipIntoView(int index) {
    if (!_studioMediaListScrollController.hasClients) return;
    final targetOffset = (index * 52.0).clamp(
      0.0,
      _studioMediaListScrollController.position.maxScrollExtent,
    );
    _studioMediaListScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  void _focusFirstVisibleSlateField() {
    if (_project.showChapter) {
      _studioChapterFocusNode.requestFocus();
    } else {
      _studioSceneFocusNode.requestFocus();
    }
  }

  Future<void> _stepStudioFrame({required bool forward}) async {
    final player = _studioPlayer;
    if (player == null) return;
    final fps =
        FrameStepUtils.fpsFromFrameRate(_project.log.metadata.frameRate);
    final fallbackTarget = await FrameStepUtils.step(
      player,
      forward: forward,
      position: _studioPositionNotifier.value,
      duration: _studioDurationNotifier.value,
      fps: fps,
    );
    _studioIsPlayingNotifier.value = false;
    if (fallbackTarget != null) {
      _studioPositionNotifier.value = fallbackTarget;
    }
  }

  Future<void> _captureStudioStill() async {
    final player = _studioPlayer;
    if (player == null || _isCapturingStill) return;

    setState(() {
      _isCapturingStill = true;
    });

    // Immediate tactile shutter flash feedback
    _studioShutterFlashNotifier.value = true;
    _studioShutterTimer?.cancel();
    _studioShutterTimer = Timer(const Duration(milliseconds: 80), () {
      if (mounted) {
        _studioShutterFlashNotifier.value = false;
      }
    });

    try {
      final clip = _selectedStudioClip;
      String baseName = 'fotograma';
      if (clip != null) {
        if (clip.proposedFileName.trim().isNotEmpty) {
          baseName = clip.proposedFileName.trim();
        } else if (clip.originalFilePath != null) {
          baseName = p.basenameWithoutExtension(clip.originalFilePath!);
        }
      }

      final stillsDir = StillCaptureService.getProjectStillsDirectory(
        projectName: _project.log.metadata.nomenclature,
        date: _project.log.metadata.date,
      );

      final savedFile = await StillCaptureService.captureStill(
        player: player,
        baseName: baseName,
        targetDir: stillsDir,
      );

      if (savedFile != null && mounted) {
        final fileName = p.basename(savedFile.path);
        final folderName = p.basename(stillsDir.path);
        _showNotification('Fotograma guardado: $fileName en $folderName');
      } else if (mounted) {
        _showNotification(
          'No se pudo capturar el fotograma del video',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Error al capturar fotograma: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingStill = false;
        });
        _studioShutterFlashNotifier.value = false;
        _studioShutterTimer?.cancel();
      }
    }
  }

  KeyEventResult _handleStudioWorkspaceKeyEvent(
    FocusNode node,
    KeyEvent event,
  ) {
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    final isAction = isDown || isRepeat;

    final isCtrlOrMeta =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Global Navigation Shortcuts (functional from any state)
    if (isDown && event.logicalKey == LogicalKeyboardKey.keyE && isCtrlOrMeta) {
      _conventionEditorFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (isDown && event.logicalKey == LogicalKeyboardKey.keyB && isCtrlOrMeta) {
      _focusFirstVisibleSlateField();
      return KeyEventResult.handled;
    }

    if (isDown && event.logicalKey == LogicalKeyboardKey.escape) {
      FocusManager.instance.primaryFocus?.unfocus();
      _studioWorkspaceFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    // If focus is in a textfield, do NOT intercept text typing or cursor navigation
    if (_isTextFieldFocused) {
      return KeyEventResult.ignored;
    }

    // Workspace / Playback Shortcuts
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (isDown) {
        _toggleStudioPlay();
      }
      return KeyEventResult.handled;
    }

    if (isDown && event.logicalKey == LogicalKeyboardKey.tab) {
      _focusFirstVisibleSlateField();
      return KeyEventResult.handled;
    }

    if (isAction && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _seekStudioRelative(-2);
      return KeyEventResult.handled;
    }

    if (isAction && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _seekStudioRelative(2);
      return KeyEventResult.handled;
    }

    if (isAction && event.logicalKey == LogicalKeyboardKey.period) {
      _stepStudioFrame(forward: true);
      return KeyEventResult.handled;
    }

    if (isAction && event.logicalKey == LogicalKeyboardKey.comma) {
      _stepStudioFrame(forward: false);
      return KeyEventResult.handled;
    }

    if (isAction && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _selectPreviousStudioClip();
      return KeyEventResult.handled;
    }

    if (isAction && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _selectNextStudioClip();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _buildStudioWorkspace() {
    return Focus(
      focusNode: _studioWorkspaceFocusNode,
      autofocus: true,
      onKeyEvent: _handleStudioWorkspaceKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final isMediaRight = _appSettings.renamerPaneLayout == 'media_right';

          final widths = calculateStudioPaneWidths(totalWidth);
          final mediaWidth = (_userStudioMediaWidth ?? widths.mediaWidth).clamp(
            220.0,
            650.0,
          );
          final conventionWidth =
              (_userStudioConventionWidth ?? widths.conventionWidth).clamp(
                340.0,
                650.0,
              );

          final mediaWidget = SizedBox(
            width: mediaWidth,
            child: _buildStudioMediaList(),
          );
          final conventionWidget = _buildConventionEditorPane(
            width: conventionWidth,
          );
          final centerWidget = Expanded(child: _buildStudioCenterInspector());

          final mediaSplitter = _StudioSplitterDivider(
            onDragUpdate: (details) {
              setState(() {
                final current = _userStudioMediaWidth ?? mediaWidth;
                final delta = isMediaRight
                    ? -details.delta.dx
                    : details.delta.dx;
                _userStudioMediaWidth = (current + delta).clamp(220.0, 650.0);
              });
            },
            onReset: () {
              setState(() {
                _userStudioMediaWidth = null;
              });
            },
          );

          final conventionSplitter = _StudioSplitterDivider(
            onDragUpdate: (details) {
              setState(() {
                final current = _userStudioConventionWidth ?? conventionWidth;
                final delta = isMediaRight
                    ? details.delta.dx
                    : -details.delta.dx;
                _userStudioConventionWidth = (current + delta).clamp(
                  340.0,
                  650.0,
                );
              });
            },
            onReset: () {
              setState(() {
                _userStudioConventionWidth = null;
              });
            },
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: isMediaRight
                ? [
                    conventionWidget,
                    conventionSplitter,
                    centerWidget,
                    mediaSplitter,
                    mediaWidget,
                  ]
                : [
                    mediaWidget,
                    mediaSplitter,
                    centerWidget,
                    conventionSplitter,
                    conventionWidget,
                  ],
          );
        },
      ),
    );
  }

  Future<void> _undoRename() async {
    if (_mediaFolderPath == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Deshacer último renombrado?'),
        content: const Text(
          'Se restaurarán los nombres originales de los archivos procesados en este lote.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar y Deshacer'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await RenameService.undoRename(_mediaFolderPath!);
      await _generatePreview();
      if (mounted) {
        _showNotification('Renombrado deshecho con éxito');
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Error al deshacer: $e', isError: true);
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportReport() async {
    if (_report == null || _mediaFolderPath == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await ReportExportService.exportReport(
        mediaFolderPath: _mediaFolderPath!,
        log: _project.log,
        report: _report!,
        activeCamera: _project.activeCamera,
      );
      if (mounted) {
        _showNotification('Reporte exportado exitosamente');
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Error al exportar reporte: $e', isError: true);
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String projectTitle = _projectPath != null
        ? _projectPath!.split(Platform.pathSeparator).last
        : 'Proyecto Sin Título';
    if (_isDirty) projectTitle += ' *';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Renombrata - $projectTitle',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          backgroundColor: isDark ? const Color(0xFF16161A) : Colors.white,
          foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
          elevation: 0,
          scrolledUnderElevation: 0,
          shape: Border(
            bottom: BorderSide(
              color: isDark ? const Color(0xFF282832) : const Color(0xFFCBD5E1),
              width: 1,
            ),
          ),
          actions: [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, currentMode, child) {
                final isCurrentDark = currentMode == ThemeMode.dark;
                return IconButton(
                  icon: Icon(
                    isCurrentDark ? Icons.light_mode : Icons.dark_mode,
                  ),
                  tooltip: 'Cambiar modo oscuro / claro',
                  onPressed: () async {
                    final newMode = isCurrentDark
                        ? ThemeMode.light
                        : ThemeMode.dark;
                    themeNotifier.value = newMode;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('is_dark_mode', !isCurrentDark);
                  },
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Configuración',
              onPressed: _openSettingsDialog,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar Medios y Bitácora',
              onPressed: () {
                _generatePreview();
              },
            ),
            IconButton(
              icon: const Icon(Icons.note_add),
              tooltip: 'Nuevo Proyecto',
              onPressed: _newProject,
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Abrir Proyecto',
              onPressed: _openProject,
            ),
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Guardar',
              onPressed: _saveProject,
            ),
            IconButton(
              icon: const Icon(Icons.save_as),
              tooltip: 'Guardar como',
              onPressed: _saveProjectAs,
            ),
            const SizedBox(width: 16),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF6366F1),
            labelColor: isDark ? Colors.white : const Color(0xFF4F46E5),
            unselectedLabelColor: isDark
                ? const Color(0xFF8E8E9F)
                : const Color(0xFF64748B),
            onTap: (index) {
              if (index == 0 && _appSettings.pauseVideoOnTabSwitch) {
                _studioPlayer?.pause();
                _studioIsPlayingNotifier.value = false;
              }
            },
            tabs: const [
              Tab(icon: Icon(Icons.edit_document), text: 'Bitácora Digital'),
              Tab(icon: Icon(Icons.sync), text: 'Renombrador de Medios'),
            ],
          ),
        ),
        body: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
              if (_isTextFieldFocused) {
                final primary = FocusManager.instance.primaryFocus;
                if (primary?.context != null) {
                  Actions.maybeInvoke(
                    primary!.context!,
                    const UndoTextIntent(SelectionChangedCause.keyboard),
                  );
                }
                return;
              }
              if (_previousReportBeforePaste != null) {
                _undoPastedMatches();
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () {
              if (_isTextFieldFocused) {
                final primary = FocusManager.instance.primaryFocus;
                if (primary?.context != null) {
                  Actions.maybeInvoke(
                    primary!.context!,
                    const UndoTextIntent(SelectionChangedCause.keyboard),
                  );
                }
                return;
              }
              if (_previousReportBeforePaste != null) {
                _undoPastedMatches();
              }
            },
          },
          child: Focus(
            autofocus: true,
            child: DropTarget(
              onDragEntered: (details) => setState(() => _isDragging = true),
              onDragExited: (details) => setState(() => _isDragging = false),
              onDragDone: (details) {
                setState(() => _isDragging = false);
                _handleDroppedFiles(details.files);
              },
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildNotificationBanner(),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // Tab 1: Editor
                            BitacoraEditorTab(
                              project: _project,
                              settings: _appSettings,
                              onProjectChanged: _updateProject,
                              onSettingsChanged: (newSettings) {
                                setState(() {
                                  _appSettings = newSettings;
                                });
                              },
                              onSaveProject: _saveProject,
                            ),
                            // Tab 2: Conciliación
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildControlsBar(),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    child: _isStudioMode
                                        ? _buildStudioWorkspace()
                                        : (_showConventionEditorPane
                                              ? Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children:
                                                      _appSettings
                                                              .renamerPaneLayout ==
                                                          'media_right'
                                                      ? [
                                                          _buildConventionEditorPane(),
                                                          const SizedBox(
                                                            width: 16,
                                                          ),
                                                          Expanded(
                                                            child:
                                                                _buildPreviewTable(),
                                                          ),
                                                        ]
                                                      : [
                                                          Expanded(
                                                            child:
                                                                _buildPreviewTable(),
                                                          ),
                                                          const SizedBox(
                                                            width: 16,
                                                          ),
                                                          _buildConventionEditorPane(),
                                                        ],
                                                )
                                              : _buildPreviewTable()),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildFooter(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_isDragging) _buildDragDropOverlay(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlsBar() {
    final playablePlaylist =
        _report?.proposals
            .where(
              (p) =>
                  p.originalFilePath != null &&
                  _isPlayableVideo(p.originalFilePath),
            )
            .toList() ??
        [];

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _pickBitacora,
              icon: const Icon(Icons.description),
              label: const Text('Importar Excel'),
            ),
            DropdownButton<String>(
              key: const ValueKey('camera_selector_dropdown'),
              value: _project.activeCamera.toUpperCase() == 'ALL'
                  ? 'ALL'
                  : (_project.cameraNames.contains(_project.activeCamera)
                        ? _project.activeCamera
                        : (_project.cameraNames.isNotEmpty
                              ? _project.cameraNames.first
                              : null)),
              items: [
                const DropdownMenuItem(
                  value: 'ALL',
                  child: Text('Todas las Cámaras'),
                ),
                ...(_project.cameraNames.isEmpty
                    ? [
                        const DropdownMenuItem(
                          value: 'A',
                          child: Text('Cámara A'),
                        ),
                      ]
                    : _project.cameraNames.map(
                        (cam) => DropdownMenuItem(
                          value: cam,
                          child: Text('Cámara $cam'),
                        ),
                      )),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    String oldCamera = _project.activeCamera;
                    _project = _project.copyWith(activeCamera: val);

                    if (val != 'ALL') {
                      if (_reelController.text.isEmpty) {
                        _reelController.text = _computeDefaultReel(
                          _project.activeCamera,
                        );
                      } else {
                        String currentText = _reelController.text.trim();
                        final letterMatch = RegExp(
                          r'^([A-Za-z])(\d+.*)$',
                        ).firstMatch(currentText);
                        final numericMatch = RegExp(
                          r'^(\d+.*)$',
                        ).firstMatch(currentText);

                        if (letterMatch != null &&
                            letterMatch.group(1)!.toUpperCase() == oldCamera) {
                          _reelController.text =
                              '${_project.activeCamera}${letterMatch.group(2)}';
                        } else if (numericMatch != null) {
                          _reelController.text =
                              '${_project.activeCamera}$currentText';
                        }
                      }
                    }
                  });
                  _generatePreview();
                }
              },
            ),
            SizedBox(
              width: 130,
              child: TextField(
                controller: _reelController,
                decoration: InputDecoration(
                  labelText: 'Reel activo',
                  hintText: _computeDefaultReel(_project.activeCamera),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  isDense: true,
                ),
                onChanged: (val) {
                  _generatePreview();
                },
              ),
            ),
            ElevatedButton.icon(
              onPressed: _pickMediaFolder,
              icon: const Icon(Icons.folder),
              label: const Text('Selector de Carpeta de Medios'),
            ),
            Tooltip(
              message:
                  'Alternar entre vista de tabla y modo estudio de 3 paneles',
              child: OutlinedButton.icon(
                icon: Icon(
                  _isStudioMode
                      ? Icons.dashboard_customize_rounded
                      : Icons.video_settings_rounded,
                ),
                label: Text(_isStudioMode ? 'Vista Tabla' : 'Modo Estudio'),
                onPressed: () {
                  setState(() {
                    _isStudioMode = !_isStudioMode;
                    if (_isStudioMode && _selectedStudioClip == null) {
                      final clips =
                          _report?.proposals
                              .where((p) => !p.isCompanionFile)
                              .toList() ??
                          [];
                      if (clips.isNotEmpty) {
                        _selectStudioClip(clips.first);
                      }
                    }
                  });
                },
              ),
            ),
            Tooltip(
              message:
                  'Mostrar/ocultar el panel de edición y pegado de convención',
              child: OutlinedButton.icon(
                icon: Icon(
                  _showConventionEditorPane
                      ? Icons.view_sidebar_rounded
                      : Icons.view_sidebar_outlined,
                ),
                label: Text(
                  _showConventionEditorPane
                      ? 'Ocultar Editor'
                      : 'Editor de Texto',
                ),
                onPressed: () {
                  setState(() {
                    _showConventionEditorPane = !_showConventionEditorPane;
                  });
                },
              ),
            ),
            if (playablePlaylist.isNotEmpty)
              OutlinedButton.icon(
                icon: const Icon(Icons.movie_filter),
                label: Text('Inspeccionar Lote (${playablePlaylist.length})'),
                onPressed: () => _openMediaPreview(playablePlaylist.first),
              ),
            if (_mediaFolderPath != null)
              Chip(
                avatar: const Icon(
                  Icons.check_circle,
                  size: 16,
                  color: Colors.green,
                ),
                label: Text(
                  _mediaFolderPath!.split(Platform.pathSeparator).last,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () {
                  setState(() {
                    _mediaFolderPath = null;
                    _report = null;
                    _renameHistory = [];
                    _selectedReelFilter = null;
                  });
                },
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: _renameMetadata,
                  onChanged: (val) {
                    setState(() {
                      _renameMetadata = val;
                    });
                  },
                ),
                const SizedBox(width: 4),
                const Text('Renombrar metadatos (.XML)'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationBanner() {
    if (_notificationMessage == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 4.0),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: _isNotificationError
            ? Colors.red.shade100
            : Colors.green.shade100,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Icon(
                _isNotificationError
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                color: _isNotificationError
                    ? Colors.red.shade900
                    : Colors.green.shade900,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _notificationMessage!,
                  style: TextStyle(
                    color: _isNotificationError
                        ? Colors.red.shade900
                        : Colors.green.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearNotification,
                color: _isNotificationError
                    ? Colors.red.shade900
                    : Colors.green.shade900,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewTable() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_report == null) {
      if (_project.log.records.isNotEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open,
                size: 52,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 12),
              Text(
                'Bitácora activa con ${_project.log.records.length} tomas registradas',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Haz clic en "Selector de Carpeta de Medios" para conciliar los clips con la Cámara ${_project.activeCamera}.',
                style: TextStyle(
                  color: Theme.of(context).hintColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 52,
              color: Theme.of(context).hintColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'Bienvenido al Renombrador de Medios',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Puedes seleccionar una Carpeta de Medios o Importar un Excel para comenzar.',
              style: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final mediaClips = _report!.proposals
        .where((p) => !p.isCompanionFile)
        .toList();
    if (mediaClips.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.find_in_page_outlined,
              size: 48,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(height: 12),
            Text(
              'No se detectaron archivos de video para la Cámara ${_project.activeCamera} en esta carpeta.',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Verifica que la carpeta contenga clips con el prefijo "${_project.activeCamera}" o selecciona otra carpeta.',
              style: TextStyle(
                color: Theme.of(context).hintColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final reelCounts = <String, int>{};
    for (final p in mediaClips) {
      final reel = _getProposalReel(p);
      reelCounts[reel] = (reelCounts[reel] ?? 0) + 1;
    }

    if (_selectedReelFilter != null &&
        !reelCounts.containsKey(_selectedReelFilter)) {
      _selectedReelFilter = null;
    }

    List<RenameProposal> displayProposals = _report!.proposals;
    if (!_renameMetadata) {
      displayProposals = displayProposals
          .where((p) => !p.isCompanionFile)
          .toList();
    }

    if (_selectedReelFilter != null) {
      displayProposals = displayProposals
          .where((p) => _getProposalReel(p) == _selectedReelFilter)
          .toList();
    }

    if (_filterOnlyConventionMatches) {
      displayProposals = displayProposals
          .where(
            (p) =>
                p.originalFilePath != null &&
                _livePastedOverrides.containsKey(p.originalFilePath),
          )
          .toList();
    }

    final hasReelChips = reelCounts.keys.length > 1;
    final hasMatchChip = _livePastedOverrides.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasReelChips || hasMatchChip)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (hasReelChips) ...[
                    FilterChip(
                      label: Text('Todos (${mediaClips.length})'),
                      selected: _selectedReelFilter == null,
                      onSelected: (_) {
                        setState(() {
                          _selectedReelFilter = null;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ...reelCounts.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text('${entry.key} (${entry.value})'),
                          selected: _selectedReelFilter == entry.key,
                          onSelected: (selected) {
                            setState(() {
                              _selectedReelFilter = selected ? entry.key : null;
                            });
                          },
                        ),
                      );
                    }),
                  ],
                  if (hasReelChips && hasMatchChip) ...[
                    const SizedBox(width: 8),
                    Container(
                      height: 24,
                      width: 1,
                      color: Theme.of(context).dividerColor,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (hasMatchChip)
                    FilterChip(
                      avatar: const Icon(
                        Icons.check,
                        size: 14,
                        color: Colors.green,
                      ),
                      label: Text(
                        'Solo coincidentes (${_livePastedOverrides.length})',
                      ),
                      selected: _filterOnlyConventionMatches,
                      onSelected: (sel) =>
                          setState(() => _filterOnlyConventionMatches = sel),
                    ),
                ],
              ),
            ),
          ),
        if (_project.log.records.isEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.amber.shade700.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.amber.shade800,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Se detectaron ${displayProposals.length} archivos en la carpeta de medios. La bitácora aún no tiene tomas registradas; importa un Excel o usa la pestaña "Bitácora Digital" para asignar nombres propuestos.',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.amber.shade200
                          : Colors.amber.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Card(
            child: SingleChildScrollView(
              controller: _verticalTableScrollController,
              scrollDirection: Axis.vertical,
              child: Scrollbar(
                controller: _horizontalTableScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _horizontalTableScrollController,
                  scrollDirection: Axis.horizontal,
                  child: Builder(
                    builder: (context) {
                      final isMediaRight =
                          _appSettings.renamerPaneLayout == 'media_right';

                      return DataTable(
                        columnSpacing: 24,
                        headingTextStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                        columns: isMediaRight
                            ? const [
                                DataColumn(label: Text('Nombre Propuesto')),
                                DataColumn(label: Text('Escena / Toma')),
                                DataColumn(label: Text('Archivo Original')),
                                DataColumn(
                                  label: Text('TC Archivo (In → Out)'),
                                ),
                                DataColumn(label: Text('Estado')),
                              ]
                            : const [
                                DataColumn(label: Text('Archivo Original')),
                                DataColumn(
                                  label: Text('TC Archivo (In → Out)'),
                                ),
                                DataColumn(label: Text('Nombre Propuesto')),
                                DataColumn(label: Text('Escena / Toma')),
                                DataColumn(label: Text('Estado')),
                              ],
                        rows: displayProposals.map((proposal) {
                          String original = proposal.originalFilePath != null
                              ? p.basename(proposal.originalFilePath!)
                              : '—';
                          String proposed = proposal.proposedFileName;
                          if (proposal.originalFilePath != null &&
                              _livePastedOverrides.containsKey(
                                proposal.originalFilePath,
                              )) {
                            final liveName =
                                _livePastedOverrides[proposal
                                    .originalFilePath]!;
                            final origExt = p.extension(
                              proposal.originalFilePath!,
                            );
                            if (p.extension(liveName).isEmpty &&
                                origExt.isNotEmpty) {
                              proposed = '$liveName$origExt';
                            } else {
                              proposed = liveName;
                            }
                          } else if (proposal.status ==
                              ProposalStatus.unmatchedClip) {
                            proposed = '—';
                          }

                          String sceneTake = '—';
                          if (proposal.associatedRecord != null) {
                            String takeStr = proposal.associatedRecord!.take;
                            String displayTake =
                                takeStr.toUpperCase().startsWith('T')
                                ? takeStr
                                : 'T$takeStr';
                            sceneTake =
                                'Esc. ${proposal.associatedRecord!.scene} - $displayTake';
                          }

                          final logTc = proposal.associatedRecord?.tcIn;
                          final fileTc = proposal.fileTcIn;
                          final hasLogTc =
                              logTc != null && logTc.trim().isNotEmpty;
                          final hasFileTc =
                              fileTc != null && fileTc.trim().isNotEmpty;
                          final isMatched = proposal.isTimecodeMatched;

                          final isPlayable = _isPlayableVideo(
                            proposal.originalFilePath,
                          );

                          // Archivo Original cell
                          final cellOriginal = DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isPlayable) ...[
                                  InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _openMediaPreview(proposal),
                                    child: Tooltip(
                                      message:
                                          'Reproducir e inspeccionar video',
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6.0,
                                        ),
                                        child: Icon(
                                          Icons.play_circle_outline,
                                          size: 16,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                Text(original),
                              ],
                            ),
                            onDoubleTap: isPlayable
                                ? () => _openMediaPreview(proposal)
                                : null,
                          );

                          // TC Archivo cell
                          final cellTc = DataCell(
                            proposal.fileTcIn != null
                                ? Text(
                                    proposal.fileTcOut != null
                                        ? '${proposal.fileTcIn} → ${proposal.fileTcOut}'
                                        : proposal.fileTcIn!,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : Text(
                                    '—',
                                    style: TextStyle(
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ),
                          );

                          // Nombre Propuesto cell
                          final isLiveMatched =
                              proposal.originalFilePath != null &&
                              _livePastedOverrides.containsKey(
                                proposal.originalFilePath,
                              ) &&
                              !_duplicateClipConflicts.containsKey(
                                proposal.originalFilePath,
                              );

                          final cellProposed = DataCell(
                            isLiveMatched
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.check_circle_outline,
                                        size: 14,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        proposed,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(proposed),
                          );

                          // Escena / Toma cell
                          final cellSceneTake = DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(sceneTake),
                                if (proposal.hasReelDiscrepancy) ...[
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message:
                                        'El reel del archivo (${proposal.fileReel ?? "—"}) no coincide con el registrado en bitácora (${proposal.associatedRecord?.reel ?? "—"})',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.amber),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.warning_amber_rounded,
                                            size: 12,
                                            color: Colors.amber,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Reel: ${proposal.associatedRecord?.reel ?? '—'} ≠ ${proposal.fileReel}',
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                if (isMatched) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.check_circle,
                                          size: 12,
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          proposal.timecodeDeltaSeconds !=
                                                      null &&
                                                  proposal.timecodeDeltaSeconds! >
                                                      0
                                              ? 'TC Coincide (±${proposal.timecodeDeltaSeconds}s)'
                                              : 'TC Coincide',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (hasLogTc &&
                                    hasFileTc &&
                                    !isMatched) ...[
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message:
                                        'El timecode del archivo ($fileTc) no coincide con el registrado en bitácora ($logTc)',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(
                                          alpha: 0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.amber),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.warning_amber_rounded,
                                            size: 12,
                                            color: Colors.amber,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'TC Diferente',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );

                          // Estado cell
                          final hasDuplicateConflict =
                              proposal.originalFilePath != null &&
                              _duplicateClipConflicts.containsKey(
                                proposal.originalFilePath,
                              );
                          final hasStandardConflict =
                              proposal.status == ProposalStatus.conflict;

                          final cellStatus = DataCell(
                            hasDuplicateConflict || hasStandardConflict
                                ? Tooltip(
                                    message:
                                        'Haz clic para resolver este conflicto',
                                    child: InkWell(
                                      onTap: _openConflictResolver,
                                      borderRadius: BorderRadius.circular(12),
                                      child: _buildStatusBadge(
                                        ProposalStatus.conflict,
                                        conflictReason: hasDuplicateConflict
                                            ? _duplicateClipConflicts[proposal
                                                  .originalFilePath]
                                            : null,
                                      ),
                                    ),
                                  )
                                : isLiveMatched
                                ? _buildStatusBadge(
                                    ProposalStatus.ready,
                                    customText:
                                        _livePastedLineNumbers[proposal
                                                .originalFilePath] !=
                                            null
                                        ? '✓ Texto (Línea ${_livePastedLineNumbers[proposal.originalFilePath]})'
                                        : '✓ Coincide con texto',
                                  )
                                : _buildStatusBadge(proposal.status),
                          );

                          return DataRow(
                            color: WidgetStateProperty.resolveWith<Color?>(
                              (states) => isLiveMatched
                                  ? Colors.green.withValues(alpha: 0.12)
                                  : null,
                            ),
                            cells: isMediaRight
                                ? [
                                    cellProposed,
                                    cellSceneTake,
                                    cellOriginal,
                                    cellTc,
                                    cellStatus,
                                  ]
                                : [
                                    cellOriginal,
                                    cellTc,
                                    cellProposed,
                                    cellSceneTake,
                                    cellStatus,
                                  ],
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(
    ProposalStatus status, {
    String? conflictReason,
    String? customText,
  }) {
    Color bgColor;
    String text;

    if (customText != null) {
      bgColor = Colors.green;
      text = customText;
    } else {
      switch (status) {
        case ProposalStatus.ready:
          bgColor = Colors.green;
          text = 'Listo para renombrar';
          break;
        case ProposalStatus.missingFile:
          bgColor = Colors.amber;
          text = 'Falta archivo en disco';
          break;
        case ProposalStatus.unmatchedClip:
          bgColor = Colors.orange;
          text = 'Clip no registrado';
          break;
        case ProposalStatus.conflict:
          bgColor = Colors.red;
          text = conflictReason ?? 'Conflicto';
          break;
        case ProposalStatus.renamed:
          bgColor = Colors.blue;
          text = 'Renombrado exitoso';
          break;
        case ProposalStatus.alreadyRenamed:
          bgColor = Colors.blue;
          text = 'Ya renombrado';
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    int listos = _report?.totalMatched ?? 0;
    int faltantes = _report?.totalMissing ?? 0;
    int noRegistrados = _report?.totalUnmatched ?? 0;

    int readyToRename =
        _report?.proposals.where((p) {
          if (p.status != ProposalStatus.ready) return false;
          if (!_renameMetadata && p.isCompanionFile) return false;
          return true;
        }).length ??
        0;

    int totalDuplicateConflicts = _duplicateClipConflicts.length;
    int standardConflictCount =
        _report?.proposals
            .where(
              (p) => p.status == ProposalStatus.conflict && !p.isCompanionFile,
            )
            .length ??
        0;
    int conflictCount = standardConflictCount + totalDuplicateConflicts;
    bool hasConflicts =
        (_report?.proposals.any((p) => p.status == ProposalStatus.conflict) ??
            false) ||
        _duplicateClipConflicts.isNotEmpty;

    final summaryText =
        '$listos listos | $faltantes faltantes en disco | $noRegistrados no registrados';

    final actionButtons = <Widget>[
      if (hasConflicts)
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade800,
            foregroundColor: Colors.white,
          ),
          onPressed: _handleFooterConflictResolution,
          icon: const Icon(Icons.warning_amber, size: 18),
          label: Text('Resolver conflictos ($conflictCount)'),
        )
      else if (_manualOverrides.isNotEmpty)
        OutlinedButton.icon(
          icon: const Icon(Icons.tune, size: 18),
          label: Text('Editar resoluciones (${_manualOverrides.length})'),
          onPressed: _openConflictResolver,
        ),
      if (_report != null && _report!.proposals.isNotEmpty)
        OutlinedButton.icon(
          onPressed: _exportReport,
          icon: const Icon(Icons.file_download),
          label: const Text('Exportar Reporte'),
        ),
      if (_renameHistory.isNotEmpty)
        OutlinedButton(
          onPressed: _undoRename,
          child: const Text('Deshacer renombrado'),
        ),
      ElevatedButton(
        onPressed: (readyToRename > 0 && !hasConflicts) ? _executeRename : null,
        style: ElevatedButton.styleFrom(
          disabledBackgroundColor: Colors.grey.shade300,
        ),
        child: const Text('Renombrar archivos'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1050) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                summaryText,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actionButtons,
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                summaryText,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < actionButtons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actionButtons[i],
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleDroppedFiles(List<dynamic> files) async {
    if (files.isEmpty) return;

    final List<String> droppedPaths = [];
    for (final item in files) {
      final String path = (item.path as String?)?.trim() ?? '';
      if (path.isNotEmpty) {
        droppedPaths.add(path);
      }
    }
    if (droppedPaths.isEmpty) return;

    bool anyHandled = false;
    for (final path in droppedPaths) {
      // 1. Directory -> Media Folder
      if (Directory(path).existsSync()) {
        final scannedFiles = MediaScannerService.scanDirectory(
          path,
          searchSubdirectories: true,
        );
        if (!mounted) return;
        final result = await FolderIngestionDialog.show(
          context: context,
          folderPath: path,
          project: _project,
          scannedFiles: scannedFiles,
        );
        if (result == null || !mounted) return;

        await _applyFolderIngestionResult(path, result);
        anyHandled = true;
        continue;
      }

      final lower = path.toLowerCase();

      // 2. Excel File -> Bitácora (.xlsx, .xls)
      if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
        setState(() {
          _isLoading = true;
        });
        try {
          final file = File(path);
          final log = BitacoraParserService.parse(file);
          setState(() {
            _project = _project.copyWith(log: log);
            _isDirty = true;
            _reelController.text = _computeDefaultReel(_project.activeCamera);
            _manualOverrides = {};
            _baseReport = null;
          });
          await _generatePreview();
          if (_report != null) {
            await _checkAndSyncTimecodes(_report!);
          }
          anyHandled = true;
          if (mounted) {
            _showNotification(
              'Bitácora importada: ${p.basename(path)} (${log.records.length} tomas registradas)',
            );
          }
        } catch (e) {
          if (mounted) {
            _showNotification(
              'Error al leer la bitácora: Verifique que sea un archivo Excel válido',
              isError: true,
            );
          }
        } finally {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
        continue;
      }

      // 3. RTF / Plain Text File -> (.rtf, .txt)
      if (lower.endsWith('.rtf') || lower.endsWith('.txt')) {
        final handled = await _handleRtfOrTxtFile(path);
        if (handled) anyHandled = true;
        continue;
      }

      // 4. Apple Pages File -> (.pages)
      if (lower.endsWith('.pages')) {
        final handled = await _handlePagesFile(path);
        if (handled) anyHandled = true;
        continue;
      }

      // 5. Project File -> (.renombrata, .json)
      if (lower.endsWith('.renombrata') || lower.endsWith('.json')) {
        final confirm = await _checkUnsavedChanges();
        if (!confirm) return;

        try {
          final project = await ProjectService.loadProject(path);
          setState(() {
            _project = project;
            _projectPath = path;
            _isDirty = false;
            _reelController.text = _project.defaultReel;
            _manualOverrides = {};
            _baseReport = null;
          });
          await _generatePreview();
          if (_report != null) {
            await _checkAndSyncTimecodes(_report!);
          }
          anyHandled = true;
          if (mounted) {
            _showNotification('Proyecto cargado: ${p.basename(path)}');
          }
        } catch (e) {
          if (mounted) {
            _showNotification('Error al cargar proyecto: $e', isError: true);
          }
        }
        continue;
      }
    }

    // 6. Direct File Drag & Drop (Individual Media Files)
    if (!anyHandled) {
      final mediaExtensions = {
        '.mp4',
        '.mov',
        '.mxf',
        '.crm',
        '.wav',
        '.aif',
        '.aiff',
        '.lrv',
        '.xml',
        '.mp3',
        '.m4a',
        '.aac',
      };
      final mediaFiles = droppedPaths.where((path) {
        if (Directory(path).existsSync()) return false;
        final ext = p.extension(path).toLowerCase();
        return mediaExtensions.contains(ext);
      }).toList();

      if (mediaFiles.isNotEmpty) {
        final parentDir = p.dirname(mediaFiles.first);
        final explicitFiles =
            mediaFiles.map((path) => ScannedFile(path)).toList();
        final droppedSet = mediaFiles.toSet();

        try {
          final dir = Directory(parentDir);
          if (dir.existsSync()) {
            for (final f in dir.listSync(followLinks: false).whereType<File>()) {
              final ext = p.extension(f.path).toLowerCase();
              if ((ext == '.xml' || ext == '.lrv') &&
                  !droppedSet.contains(f.path)) {
                explicitFiles.add(ScannedFile(f.path));
              }
            }
          }
        } catch (_) {}

        setState(() {
          _mediaFolderPath = parentDir;
          _explicitScannedFiles = explicitFiles;
          _manualOverrides = {};
          _baseReport = null;
        });

        await _generatePreview();
        if (_report != null) {
          await _checkAndSyncTimecodes(_report!);
        }
        anyHandled = true;
        if (mounted) {
          final count = _report?.proposals
                  .where((p) => !p.isCompanionFile)
                  .length ??
              explicitFiles
                  .where((f) => f.isPrimaryVideo || f.isAudio)
                  .length;
          _showNotification(
            'Archivos multimedia cargados: $count clip(s) detectado(s)',
          );
        }
      }
    }

    if (!anyHandled && mounted) {
      final firstFileName = p.basename(droppedPaths.first);
      _showNotification(
        'Archivo no soportado: "$firstFileName". Formatos aceptados: carpetas de medios, archivos de video/audio, Excel (.xlsx, .xls), bitácoras de texto (.rtf, .txt), Apple Pages (.pages) o proyectos (.renombrata).',
        isError: true,
      );
    }
  }

  Future<bool> _handleRtfOrTxtFile(String path) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();
      String rawContent;
      try {
        rawContent = utf8.decode(bytes);
      } catch (_) {
        rawContent = latin1.decode(bytes);
      }

      final plainText = RtfBitacoraParserService.extractPlainText(rawContent);
      setState(() {
        _conventionEditorController.text = plainText;
      });
      _evaluateConventionMatches();

      final entries = RtfBitacoraParserService.parseLines(plainText);

      if (entries.isEmpty) {
        if (mounted) {
          _showNotification(
            'No se encontraron nomenclaturas de tomas válidas en: ${p.basename(path)}',
            isError: true,
          );
        }
        return false;
      }

      final reels = RtfBitacoraParserService.segmentByReel(entries);
      final log = RtfBitacoraParserService.toShootingLog(entries);

      setState(() {
        _project = _project.copyWith(log: log);
        _isDirty = true;
        _reelController.text = _computeDefaultReel(_project.activeCamera);
        _manualOverrides = {};
        _baseReport = null;
      });
      await _generatePreview();
      _evaluateConventionMatches();
      if (mounted) {
        _showNotification(
          'Bitácora importada: ${p.basename(path)} (${entries.length} tomas registradas en ${reels.length} reels)',
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        _showNotification(
          'Error al leer la bitácora de texto: $e',
          isError: true,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _handlePagesFile(String path) async {
    if (Platform.isMacOS) {
      setState(() {
        _isLoading = true;
      });
      try {
        final xlsxPath = await PagesConverterService.convertPagesToXlsx(path);
        if (xlsxPath != null && File(xlsxPath).existsSync()) {
          final file = File(xlsxPath);
          final log = BitacoraParserService.parse(file);
          try {
            file.deleteSync();
          } catch (_) {}

          setState(() {
            _project = _project.copyWith(log: log);
            _isDirty = true;
            _reelController.text = _computeDefaultReel(_project.activeCamera);
            _manualOverrides = {};
            _baseReport = null;
          });
          await _generatePreview();
          if (mounted) {
            _showNotification(
              'Bitácora de Apple Pages importada: ${p.basename(path)} (${log.records.length} tomas registradas)',
            );
          }
          return true;
        } else {
          if (mounted) {
            _showNotification(
              'No se pudo convertir el archivo de Apple Pages. Verifique que la aplicación Pages esté instalada.',
              isError: true,
            );
          }
          return false;
        }
      } catch (e) {
        if (mounted) {
          _showNotification(
            'Error al convertir archivo de Pages: $e',
            isError: true,
          );
        }
        return false;
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      // Platform is Windows or other non-macOS
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Archivo Apple Pages (.pages)'),
            content: const Text(
              'Los archivos de Apple Pages (.pages) se procesan automáticamente en macOS usando la aplicación nativa de Pages.\n\nEn Windows, por favor abre el archivo en Pages o en iCloud.com y expórtalo como archivo Excel (.xlsx) para importarlo en Renombrata.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
      return true;
    }
  }

  Widget _buildDragDropOverlay() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: isDark ? Colors.black54 : Colors.white70,
          child: Center(
            child: CustomPaint(
              painter: _DashedBorderPainter(
                color: primaryColor,
                strokeWidth: 2.5,
                dash: 8.0,
                gap: 5.0,
                radius: 20.0,
              ),
              child: Container(
                width: 540,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 36,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E26).withValues(alpha: 0.95)
                      : Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.file_download_outlined,
                        size: 52,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Suelta tus archivos aquí',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Suelta aquí carpetas de medios, archivos Excel (.xlsx), bitácoras de texto (.rtf, .txt) o proyectos (.renombrata)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildOverlayBadge(
                          Icons.folder_outlined,
                          'Carpeta de Medios',
                          primaryColor,
                        ),
                        _buildOverlayBadge(
                          Icons.table_chart_outlined,
                          'Bitácora (.xlsx, .rtf, .txt, .pages)',
                          Colors.green.shade600,
                        ),
                        _buildOverlayBadge(
                          Icons.description_outlined,
                          'Proyecto (.renombrata)',
                          Colors.purple.shade400,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayBadge(IconData icon, String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDark ? color : color.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;
  final double radius;

  _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 2.0,
    this.dash = 6.0,
    this.gap = 4.0,
    this.radius = 16.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double length = (distance + dash <= metric.length)
            ? dash
            : metric.length - distance;
        final extractPath = metric.extractPath(distance, distance + length);
        canvas.drawPath(extractPath, paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
}

class _StudioSplitterDivider extends StatefulWidget {
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onReset;

  const _StudioSplitterDivider({
    required this.onDragUpdate,
    required this.onReset,
  });

  @override
  State<_StudioSplitterDivider> createState() => _StudioSplitterDividerState();
}

class _StudioSplitterDividerState extends State<_StudioSplitterDivider> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.colorScheme.primary;
    final defaultColor = theme.dividerColor.withValues(alpha: 0.25);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: widget.onDragUpdate,
        onDoubleTap: widget.onReset,
        child: SizedBox(
          width: 12,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _isHovered ? 3.0 : 1.5,
              height: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: _isHovered ? accentColor : defaultColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
