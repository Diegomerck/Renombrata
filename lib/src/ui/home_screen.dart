import 'dart:io';
import 'dart:async';
import 'dart:convert';
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
import 'package:renombrata/src/services/convention_name_generator.dart';
import 'package:renombrata/src/services/settings_service.dart';
import 'package:renombrata/src/ui/settings_dialog.dart';
import 'package:renombrata/src/ui/bitacora_editor_tab.dart';
import 'package:renombrata/src/ui/conflict_resolver_dialog.dart';
import 'package:renombrata/src/ui/media_preview_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter/gestures.dart';
import 'package:renombrata/src/utils/timecode_formatter.dart';
import 'package:renombrata/src/services/pages_converter_service.dart';
import 'package:renombrata/src/ui/quick_paste_convention_dialog.dart';
import '../../main.dart';

class HomeScreen extends StatefulWidget {
  final RenombrataProject? initialProject;
  final DryRunReport? initialReport;
  final Player? customStudioPlayer;
  final VideoController? customStudioVideoController;

  const HomeScreen({
    super.key,
    this.initialProject,
    this.initialReport,
    this.customStudioPlayer,
    this.customStudioVideoController,
  });

  static String computeLiveSmpte(Duration position, String? baseTcIn, String frameRate) {
    final fps = TimecodeUtils.getFpsInt(frameRate);
    int baseFrames = 0;
    if (baseTcIn != null && baseTcIn.trim().isNotEmpty) {
      final parts = baseTcIn.trim().split(':').map((p) => int.tryParse(p) ?? 0).toList();
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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  RenombrataProject _project = RenombrataProject(
    log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
    defaultReel: '001',
    activeCamera: 'A',
  );

  AppSettings _appSettings = AppSettings.defaults();

  @visibleForTesting
  RenombrataProject get project => _project;

  String? _projectPath;
  bool _isDirty = false;
  
  String? _mediaFolderPath;
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

  bool _isStudioMode = false;
  RenameProposal? _selectedStudioClip;
  Player? _studioPlayer;
  VideoController? _studioVideoController;
  final ValueNotifier<bool> _studioIsPlayingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> _studioPositionNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> _studioDurationNotifier = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<double> _studioVolumeNotifier = ValueNotifier<double>(100.0);
  final ValueNotifier<bool> _studioIsMutedNotifier = ValueNotifier<bool>(false);
  double _studioPreMuteVolume = 100.0;
  bool _studioIsDraggingSlider = false;
  double _studioDragSliderValue = 0.0;

  final TransformationController _studioZoomController = TransformationController();
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

  final TextEditingController _studioChapterController = TextEditingController();
  final TextEditingController _studioSceneController = TextEditingController();
  final TextEditingController _studioPlaneController = TextEditingController();
  final TextEditingController _studioTakeController = TextEditingController();
  final TextEditingController _studioNotesController = TextEditingController();
  bool _studioIsMos = false;
  bool _studioIsTf = false;
  bool _studioIsDs = false;
  bool _studioIsFf = false;
  bool _studioIsGpr = false;
  bool _studioIsDr = false;

  final FocusNode _conventionEditorFocusNode = FocusNode(debugLabel: 'conventionEditor');
  final FocusNode _studioChapterFocusNode = FocusNode(debugLabel: 'studioChapter');
  final FocusNode _studioSceneFocusNode = FocusNode(debugLabel: 'studioScene');
  final FocusNode _studioTakeFocusNode = FocusNode(debugLabel: 'studioTake');
  final FocusNode _studioPlaneFocusNode = FocusNode(debugLabel: 'studioPlane');
  final FocusNode _studioNotesFocusNode = FocusNode(debugLabel: 'studioNotes');
  final FocusNode _studioWorkspaceFocusNode = FocusNode(debugLabel: 'studioWorkspace');
  final FocusNode _studioMediaListFocusNode = FocusNode(debugLabel: 'studioMediaList');
  final FocusNode _studioInspectorFocusNode = FocusNode(debugLabel: 'studioInspector');
  final FocusNode _conventionEditorPanelFocusNode = FocusNode(debugLabel: 'conventionEditorPanel');

  @visibleForTesting
  FocusNode get studioWorkspaceFocusNode => _studioWorkspaceFocusNode;

  @visibleForTesting
  FocusNode get studioMediaListFocusNode => _studioMediaListFocusNode;

  @visibleForTesting
  FocusNode get studioInspectorFocusNode => _studioInspectorFocusNode;

  @visibleForTesting
  FocusNode get conventionEditorPanelFocusNode => _conventionEditorPanelFocusNode;

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
  ({double mediaWidth, double conventionWidth}) calculateStudioPaneWidths(double totalWidth) {
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
  DryRunReport? get previousReportBeforePaste => _previousReportBeforePaste;

  @visibleForTesting
  set previousReportBeforePaste(DryRunReport? value) => _previousReportBeforePaste = value;

  @visibleForTesting
  DryRunReport? get report => _report;

  @visibleForTesting
  bool get studioIsMos => _studioIsMos;

  @visibleForTesting
  bool get studioIsTf => _studioIsTf;

  @visibleForTesting
  bool get studioIsDs => _studioIsDs;

  @visibleForTesting
  bool get studioIsFf => _studioIsFf;

  @visibleForTesting
  bool get studioIsGpr => _studioIsGpr;

  @visibleForTesting
  bool get studioIsDr => _studioIsDr;

  @visibleForTesting
  TextEditingController get studioChapterController => _studioChapterController;

  @visibleForTesting
  TextEditingController get studioSceneController => _studioSceneController;

  @visibleForTesting
  TextEditingController get studioPlaneController => _studioPlaneController;

  @visibleForTesting
  TextEditingController get studioTakeController => _studioTakeController;

  @visibleForTesting
  TextEditingController get studioNotesController => _studioNotesController;

  @visibleForTesting
  TextEditingController get conventionEditorController => _conventionEditorController;

  @visibleForTesting
  UndoHistoryController get conventionEditorUndoController => _conventionEditorUndoController;

  @visibleForTesting
  void onConventionTextChanged(String text) => _onConventionTextChanged(text);

  final TextEditingController _reelController = TextEditingController(text: '001');
  final ScrollController _horizontalTableScrollController = ScrollController();
  final ScrollController _verticalTableScrollController = ScrollController();
  final ScrollController _studioMediaListScrollController = ScrollController();
  final ScrollController _conventionLineStatusScrollController = ScrollController();
  bool _showConventionEditorPane = false;
  final TextEditingController _conventionEditorController = TextEditingController();
  final UndoHistoryController _conventionEditorUndoController = UndoHistoryController();
  Map<String, String> _livePastedOverrides = {};
  Map<String, int> _livePastedLineNumbers = {};
  Map<String, String> _duplicateClipConflicts = {};
  final Set<String> _resolvedConflictPaths = {};
  bool _filterOnlyConventionMatches = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialProject != null) {
      _project = widget.initialProject!;
    }
    if (widget.initialReport != null) {
      _report = widget.initialReport;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _evaluateConventionMatches();
      });
    }
    _reelController.text = _project.defaultReel;
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0) {
        _disposeStudioPlayer();
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
      if (mounted) {
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
    final currentTranslationOffset = Offset(currentTranslation.x, currentTranslation.y);

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
    _studioZoomTo(currentScale * 1.3, focalPoint: focalPoint ?? _studioHoveredPointerPosition);
  }

  void _studioZoomOut({Offset? focalPoint}) {
    final currentScale = _studioZoomController.value.getMaxScaleOnAxis();
    _studioZoomTo(currentScale / 1.3, focalPoint: focalPoint ?? _studioHoveredPointerPosition);
  }

  String _computeLiveSmpte(Duration position, String? baseTcIn, String frameRate) =>
      HomeScreen.computeLiveSmpte(position, baseTcIn, frameRate);

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
      _studioPlayer?.pause();
      _studioVideoController = null;
      _studioPlayer?.dispose();
      _studioPlayer = null;
    } catch (e) {
      debugPrint('Error disposing studio player: $e');
    }
  }

  @override
  void dispose() {
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
    _studioChapterController.dispose();
    _studioSceneController.dispose();
    _studioPlaneController.dispose();
    _studioTakeController.dispose();
    _studioNotesController.dispose();
    _notificationTimer?.cancel();
    super.dispose();
  }

  String _computeDefaultReel(String camera) {
    if (_project.log.records.isEmpty) return '${camera}001';
    
    String baseReel = '';
    for (var r in _project.log.records) {
      if (r.reel.trim().isNotEmpty) {
        baseReel = r.reel.trim();
        break;
      }
    }
    
    if (baseReel.isEmpty) return '${camera}001';

    final letterMatch = RegExp(r'^([A-Za-z])(\d+.*)$').firstMatch(baseReel);
    if (letterMatch != null) {
      return '$camera${letterMatch.group(2)}';
    } else {
      final numericMatch = RegExp(r'^(\d+.*)$').firstMatch(baseReel);
      if (numericMatch != null) {
        return '$camera$baseReel';
      }
    }
    return baseReel;
  }

  void _updateProject(RenombrataProject newProject) {
    setState(() {
      _project = newProject;
      _isDirty = true;
      if (_reelController.text != newProject.defaultReel) {
        _reelController.text = newProject.defaultReel;
      }
    });
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
      String outputFile = '$outputDir${Platform.pathSeparator}proyecto.renombrata';
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
        content: const Text('¿Desea continuar y perder los cambios no guardados?'),
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
        _generatePreview();
        if (mounted) {
          _showNotification('Bitácora importada correctamente.');
        }
      } catch (e) {
        setState(() {
          _report = null;
        });
        if (mounted) {
          _showNotification('Error al leer la bitácora: Verifique que sea un archivo Excel válido', isError: true);
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
        setState(() {
          _mediaFolderPath = selectedDirectory;
          _manualOverrides = {};
        });
        await _generatePreview();
        if (mounted) {
          final folderName = selectedDirectory.split(Platform.pathSeparator).last;
          final totalScanned = _report?.proposals.length ?? 0;
          if (_project.log.records.isEmpty) {
            _showNotification('Carpeta "$folderName" seleccionada ($totalScanned clips detectados). Importa un Excel o crea tomas en la Bitácora Digital para generar propuestas.');
          } else {
            _showNotification('Carpeta "$folderName" cargada correctamente ($totalScanned clips analizados).');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showNotification('Error al abrir selector de carpeta: $e', isError: true);
      }
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
      final scannedFiles = MediaScannerService.scanDirectory(
        _mediaFolderPath!,
        searchSubdirectories: true,
      );

      final baseReport = await ClipMatcherService.matchFilesAsync(
        scannedFiles: scannedFiles,
        log: _project.log,
        targetCamera: _project.activeCamera,
        reelOverride: _reelController.text.trim().isNotEmpty ? _reelController.text.trim() : null,
        renameHistory: history,
        manualOverrides: const {},
      );

      final report = _manualOverrides.isEmpty
          ? baseReport
          : await ClipMatcherService.matchFilesAsync(
              scannedFiles: scannedFiles,
              log: _project.log,
              targetCamera: _project.activeCamera,
              reelOverride: _reelController.text.trim().isNotEmpty ? _reelController.text.trim() : null,
              renameHistory: history,
              manualOverrides: _manualOverrides,
            );

      setState(() {
        _baseReport = baseReport;
        _report = report;
        _renameHistory = history;
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
      extraWarning = '\n\nAviso: Existen archivos faltantes o no registrados en esta carpeta. Solo se renombrarán los $readyCount archivos listos coincidentes.';
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Confirmar renombrado de archivos?'),
        content: Text('Se renombrarán $readyCount archivos en el disco. Esta acción modificará los nombres originales.$extraWarning'),
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
        _showNotification('Error durante el renombrado: $e', isError: true);
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

          final idx = updatedProposals.indexWhere((p) => p.originalFilePath == filePath);
          if (idx == -1) continue;

          final prop = updatedProposals[idx];
          final origExt = p.extension(filePath);
          final fn = p.basename(filePath);
          final reel = _getProposalReel(prop).toUpperCase();
          final clipNum = int.tryParse(ClipMatcherService.extractClipNumber(fn)) ?? 0;
          final conventionLine = _findConventionNameForClip(reel, clipNum);

          if (assignment == null) {
            updatedProposals[idx] = prop.copyWith(status: ProposalStatus.unmatchedClip);
          } else if (assignment == '__PRIMARY__' || (_project.log.records.any((r) => r.id == assignment))) {
            String targetName = conventionLine ?? prop.proposedFileName;
            if (p.extension(targetName).isEmpty && origExt.isNotEmpty) {
              targetName = '$targetName$origExt';
            }
            updatedProposals[idx] = prop.copyWith(
              proposedFileName: targetName,
              status: ProposalStatus.ready,
            );
            _updateCompanionProposals(updatedProposals, filePath, targetName);
          } else if (assignment == '__ALT__' || assignment.startsWith('__ALT__:')) {
            String baseName = conventionLine != null && conventionLine.isNotEmpty
                ? p.basenameWithoutExtension(conventionLine)
                : p.basenameWithoutExtension(prop.proposedFileName.isNotEmpty ? prop.proposedFileName : filePath);
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
    if (p.associatedRecord?.reel != null && p.associatedRecord!.reel.trim().isNotEmpty) {
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
    _evaluateConventionMatches();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      _conventionEditorController.text = data.text!;
      _evaluateConventionMatches();
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
      if (trimmed.isNotEmpty) {
        parsedLines.add(QuickPasteConventionDialog.parsePastedLine(trimmed, i + 1));
      }
    }

    // Check duplicate clip lines in pasted text
    final pastedByKey = <String, List<PastedLineItem>>{};
    for (final line in parsedLines) {
      if (line.hasExtractedClip && line.clipNumber != null) {
        final reelKey = line.reel?.toUpperCase() ?? 'ALL';
        final key = '${reelKey}_${line.clipNumber}';
        pastedByKey.putIfAbsent(key, () => []).add(line);
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
        final clipNum = int.tryParse(ClipMatcherService.extractClipNumber(
          p.basename(firstClip.originalFilePath!),
        )) ?? 0;
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
        if (prop.originalFilePath != null && newDuplicateClipConflicts.containsKey(prop.originalFilePath)) {
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
    final hasAnyExtractedClip = parsedLines.any((l) => l.hasExtractedClip);

    if (!hasAnyExtractedClip) {
      // Sequential fallback
      for (int i = 0; i < mediaClips.length; i++) {
        final clip = mediaClips[i];
        final path = clip.originalFilePath!;
        if (newDuplicateClipConflicts.containsKey(path)) continue;
        if (_resolvedConflictPaths.contains(path)) continue;

        if (i < parsedLines.length) {
          newLiveOverrides[path] = parsedLines[i].rawLine;
          newLiveLineNumbers[path] = parsedLines[i].lineNumber;
        }
      }
    } else {
      // Intelligent matching by (Reel, ClipNumber)
      for (final clip in mediaClips) {
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

          if (line.reel != null) {
            if (line.reel!.toUpperCase() == reel) {
              candidates.add(line);
            }
          } else {
            candidates.add(line);
          }
        }

        if (candidates.length == 1) {
          final matchedLine = candidates.first;
          final lineKey = '${matchedLine.reel?.toUpperCase() ?? 'ALL'}_${matchedLine.clipNumber}';
          if (!duplicatePastedKeys.contains(lineKey)) {
            newLiveOverrides[path] = matchedLine.rawLine;
            newLiveLineNumbers[path] = matchedLine.lineNumber;
          }
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
      displayProposals = displayProposals.where((p) => !p.isCompanionFile).toList();
    }
    if (_selectedReelFilter != null) {
      displayProposals = displayProposals.where((p) => _getProposalReel(p) == _selectedReelFilter).toList();
    }
    if (_filterOnlyConventionMatches) {
      displayProposals = displayProposals
          .where((p) => p.originalFilePath != null && _livePastedOverrides.containsKey(p.originalFilePath))
          .toList();
    }
    final index = displayProposals.indexWhere((p) => p.originalFilePath == originalFilePath);
    if (index != -1) {
      const rowHeight = 48.0;
      final targetOffset = (index * rowHeight).clamp(0.0, _verticalTableScrollController.position.maxScrollExtent);
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
      final parsed = QuickPasteConventionDialog.parsePastedLine(trimmed, lineIndex);

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
        statuses.add(_ConventionLineStatus(
          lineNumber: lineIndex,
          text: 'Línea $lineIndex: $originalFileName',
          icon: Icons.check_circle,
          color: Colors.green,
          targetFilePath: matchedPath,
        ));
        continue;
      }

      // 2. Check if the line could not be parsed
      if (!parsed.hasExtractedClip || parsed.clipNumber == null) {
        statuses.add(_ConventionLineStatus(
          lineNumber: lineIndex,
          text: 'Línea $lineIndex: Formato de convención no reconocido',
          icon: Icons.help_outline,
          color: Colors.grey,
        ));
        continue;
      }

      // 3. Extracted clip number: check disk files
      final clipNum = parsed.clipNumber!;
      final clipNumDisplay = clipNum.toString().padLeft(2, '0');
      final lineReel = parsed.reel?.toUpperCase();

      final matchingClipsOnDisk = mediaClips.where((c) {
        final fn = p.basename(c.originalFilePath!);
        final cn = int.tryParse(ClipMatcherService.extractClipNumber(fn));
        final r = _getProposalReel(c).toUpperCase();
        return cn == clipNum && (lineReel == null || r == lineReel);
      }).toList();

      if (matchingClipsOnDisk.length > 1) {
        // Duplicate clip conflict on disk
        statuses.add(_ConventionLineStatus(
          lineNumber: lineIndex,
          text: 'Línea $lineIndex: Conflicto en disco (Clip #$clipNumDisplay duplicado)',
          icon: Icons.warning_amber_rounded,
          color: Colors.red,
          targetFilePath: matchingClipsOnDisk.first.originalFilePath,
        ));
      } else if (matchingClipsOnDisk.isEmpty) {
        // No matching file on disk
        statuses.add(_ConventionLineStatus(
          lineNumber: lineIndex,
          text: 'Línea $lineIndex: Sin archivo en disco (Clip #$clipNumDisplay)',
          icon: Icons.info_outline,
          color: Colors.amber,
        ));
      } else {
        // Single file on disk, but conflict in text or not matched
        statuses.add(_ConventionLineStatus(
          lineNumber: lineIndex,
          text: 'Línea $lineIndex: Conflicto en texto (Clip #$clipNumDisplay duplicado)',
          icon: Icons.warning_amber_rounded,
          color: Colors.red,
          targetFilePath: matchingClipsOnDisk.first.originalFilePath,
        ));
      }
    }

    return statuses;
  }

  String? _findConventionNameForClip(String reel, int clipNumber) {
    final lines = _conventionEditorController.text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (int i = 0; i < lines.length; i++) {
      final parsed = QuickPasteConventionDialog.parsePastedLine(lines[i], i + 1);
      if (parsed.hasExtractedClip && parsed.clipNumber == clipNumber) {
        if (parsed.reel != null) {
          if (parsed.reel!.toUpperCase() == reel.toUpperCase()) {
            return parsed.rawLine;
          }
        } else {
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
        if (compBase == origBase) {
          final compExt = p.extension(comp.originalFilePath!);
          proposals[j] = comp.copyWith(
            proposedFileName: '$newProposedBase$compExt',
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
      if (proposal.isCompanionFile || proposal.originalFilePath == null) continue;

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

  Widget _buildConventionEditorPane({double width = 380}) {
    final lines = _conventionEditorController.text
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final lineCount = lines.length;
    final mediaClips = _report?.proposals.where((p) => !p.isCompanionFile).toList() ?? [];
    final totalClips = mediaClips.length;
    final matchedCount = _livePastedOverrides.keys
        .where((k) => !_duplicateClipConflicts.containsKey(k))
        .length;

    final theme = Theme.of(context);
    final hasFocus = _conventionEditorPanelFocusNode.hasFocus || _conventionEditorFocusNode.hasFocus;

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
                  Icon(Icons.edit_note_rounded, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Convención de Texto',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
              // Text Editor
              Expanded(
                child: TextField(
                  key: const ValueKey('studio_convention_editor_field'),
                  controller: _conventionEditorController,
                  undoController: _conventionEditorUndoController,
                  focusNode: _conventionEditorFocusNode,
                  enableInteractiveSelection: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Pega o escribe aquí la lista de convenciones...\n\nEjemplo:\nA001C001_260608_R1_P1.MP4\nA001C002_260608_R1_P1.MP4',
                    hintStyle: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: theme.hintColor.withValues(alpha: 0.6),
                    ),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(12),
                  ),
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
                                color: theme.dividerColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Scrollbar(
                              controller: _conventionLineStatusScrollController,
                              thumbVisibility: true,
                              child: ListView.builder(
                                controller: _conventionLineStatusScrollController,
                                primary: false,
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                                itemCount: lineStatuses.length,
                                itemBuilder: (context, i) {
                                  final item = lineStatuses[i];
                                  final isSelectedClipLine = item.targetFilePath != null &&
                                      item.targetFilePath == _selectedStudioClip?.originalFilePath;

                                  return InkWell(
                                    onTap: item.targetFilePath != null
                                        ? () {
                                            _scrollToClip(item.targetFilePath!);
                                            if (_isStudioMode && _report != null) {
                                              final matches = _report!.proposals
                                                  .where((p) => p.originalFilePath == item.targetFilePath)
                                                  .toList();
                                              if (matches.isNotEmpty) {
                                                _selectStudioClip(matches.first);
                                              }
                                            }
                                          }
                                        : null,
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 3.0, horizontal: 4.0),
                                      decoration: BoxDecoration(
                                        color: isSelectedClipLine
                                            ? theme.colorScheme.primary.withValues(alpha: theme.brightness == Brightness.dark ? 0.3 : 0.15)
                                            : null,
                                        borderRadius: BorderRadius.circular(4),
                                        border: isSelectedClipLine
                                            ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(item.icon, size: 14, color: item.color),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              item.text,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isSelectedClipLine ? FontWeight.bold : FontWeight.w500,
                                                color: isSelectedClipLine ? theme.colorScheme.primary : item.color,
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
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check, size: 16),
                          label: Text('Aplicar Coincidencias ($matchedCount)'),
                          onPressed: matchedCount > 0 ? _applyNonBlockingMatches : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.undo, size: 16),
                        label: const Text('Deshacer'),
                        onPressed: _previousReportBeforePaste != null ? _undoPastedMatches : null,
                      ),
                    ],
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
    return ['.mp4', '.mov', '.mxf'].contains(ext);
  }

  void _openMediaPreview(RenameProposal proposal) {
    if (_report == null) return;
    final playlist = _report!.proposals
        .where((p) => p.originalFilePath != null && _isPlayableVideo(p.originalFilePath))
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
        reelOverride: _reelController.text.trim().isNotEmpty ? _reelController.text.trim() : null,
        autoSortByClip: _project.autoSortByClip,
        onAutoSortChanged: (val) {
          setState(() {
            _project = _project.copyWith(autoSortByClip: val);
            _isDirty = true;
          });
        },
        onSaveTake: (prop, chapter, scene, plane, take, isMos, notes) async {
          final clipNum = ClipMatcherService.extractClipNumber(prop.originalFilePath ?? '');
          final fileReel = prop.fileReel ?? ClipMatcherService.extractReel(prop.originalFilePath ?? '');
          final targetReel = _reelController.text.trim().isNotEmpty
              ? _reelController.text.trim()
              : (fileReel ?? _project.defaultReel);

          final records = List<ShotRecord>.from(_project.log.records);
          final existingIdx = records.indexWhere((r) =>
              (chapter.isEmpty || r.chapter.trim() == chapter.trim()) &&
              r.scene.trim() == scene.trim() &&
              (r.plane ?? '').trim() == plane.trim() &&
              r.take.trim() == take.trim());

          if (existingIdx != -1) {
            final existing = records[existingIdx];
            final updatedCameras = List<CameraTakeRecord>.from(existing.cameras);
            final camIdx = updatedCameras.indexWhere((c) => c.cameraName == _project.activeCamera);
            if (camIdx != -1) {
              updatedCameras[camIdx] = updatedCameras[camIdx].copyWith(clipName: clipNum);
            } else {
              updatedCameras.add(CameraTakeRecord(cameraName: _project.activeCamera, clipName: clipNum));
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
                CameraTakeRecord(cameraName: _project.activeCamera, clipName: clipNum),
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
            finalRecords = BitacoraEditorTab.sortRecordsByClip(records, _project.activeCamera);
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
        _studioNotesController.text = rec.observations ?? '';
        _studioIsMos = rec.isMos;
        _studioIsTf = rec.isTf;
        _studioIsDs = rec.isDs;
        _studioIsFf = rec.isFf;
        _studioIsGpr = rec.isGpr;
        _studioIsDr = rec.isDr;
      } else {
        _studioChapterController.text = '';
        _studioSceneController.text = '';
        _studioPlaneController.text = '';
        _studioTakeController.text = '1';
        _studioNotesController.text = '';
        _studioIsMos = false;
        _studioIsTf = false;
        _studioIsDs = false;
        _studioIsFf = false;
        _studioIsGpr = false;
        _studioIsDr = false;
      }
    });

    _highlightMatchingConventionLine(proposal);

    final path = proposal.originalFilePath;
    if (path != null && _isPlayableVideo(path)) {
      if (_studioPlayer == null) {
        _initStudioPlayer();
      }
      try {
        _studioPlayer?.open(Media(path));
      } catch (e) {
        debugPrint('Error playing studio media: $e');
      }
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
          final parsed = QuickPasteConventionDialog.parsePastedLine(trimmed, i + 1);
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
      return currentScene.isNotEmpty || (currentTake.isNotEmpty && currentTake != '1');
    }

    return currentCap != rec.chapter.trim() ||
        currentScene != rec.scene.trim() ||
        currentPlane != (rec.plane ?? '').trim() ||
        currentTake != rec.take.trim() ||
        currentNotes != (rec.observations ?? '').trim() ||
        _studioIsMos != rec.isMos ||
        _studioIsTf != rec.isTf ||
        _studioIsDs != rec.isDs ||
        _studioIsFf != rec.isFf ||
        _studioIsGpr != rec.isGpr ||
        _studioIsDr != rec.isDr;
  }

  String _computeStudioProposedBanner(RenameProposal clip) {
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

    final origExt = clip.originalFilePath != null ? p.extension(clip.originalFilePath!) : '';
    final clipNum = ClipMatcherService.extractClipNumber(clip.originalFilePath ?? '');
    final fileReel = clip.fileReel ?? ClipMatcherService.extractReel(clip.originalFilePath ?? '');
    final defaultReel = _reelController.text.trim().isNotEmpty
        ? _reelController.text.trim()
        : (fileReel ?? clip.associatedRecord?.reel ?? '${_project.activeCamera}001');

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

    final unit = _studioIsDs
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
        .where((c) => c.cameraName == _project.activeCamera)
        .firstOrNull
        ?.clipName;
    final candidateClip = (recClip != null && recClip.trim().isNotEmpty)
        ? recClip.trim()
        : clipNum;
    if (candidateClip.isNotEmpty) {
      final parsed = int.tryParse(candidateClip);
      normalizedClip = parsed != null ? parsed.toString().padLeft(2, '0') : candidateClip;
    }

    final base = ConventionNameGenerator.generate(
      nomenclature: prod,
      chapter: cap,
      date: _project.log.metadata.date.trim().isNotEmpty ? _project.log.metadata.date.trim() : '010126',
      scene: scene,
      plane: plane,
      take: rawTake,
      reel: defaultReel,
      day: day,
      clipIndex: normalizedClip,
      unit: unit,
      activeCamera: _project.activeCamera,
      isTf: _studioIsTf,
      isDs: _studioIsDs,
      isFf: _studioIsFf,
      isGpr: _studioIsGpr,
      isDr: _studioIsDr,
    );

    return '$base$origExt';
  }

  Future<void> _saveStudioSlate() async {
    if (_selectedStudioClip == null) return;
    final prop = _selectedStudioClip!;

    final chapter = _studioChapterController.text.trim();
    final scene = _studioSceneController.text.trim();
    final plane = _studioPlaneController.text.trim();
    final take = _studioTakeController.text.trim();
    final notes = _studioNotesController.text.trim();
    final isMos = _studioIsMos;
    final isTf = _studioIsTf;
    final isDs = _studioIsDs;
    final isFf = _studioIsFf;
    final isGpr = _studioIsGpr;
    final isDr = _studioIsDr;

    final clipNum = ClipMatcherService.extractClipNumber(prop.originalFilePath ?? '');
    final fileReel = prop.fileReel ?? ClipMatcherService.extractReel(prop.originalFilePath ?? '');
    final targetReel = _reelController.text.trim().isNotEmpty
        ? _reelController.text.trim()
        : (fileReel ?? _project.defaultReel);

    final records = List<ShotRecord>.from(_project.log.records);
    final existingIdx = records.indexWhere((r) =>
        (chapter.isEmpty || r.chapter.trim() == chapter) &&
        r.scene.trim() == scene &&
        (r.plane ?? '').trim() == plane &&
        r.take.trim() == take);

    if (existingIdx != -1) {
      final existing = records[existingIdx];
      final updatedCameras = List<CameraTakeRecord>.from(existing.cameras);
      final camIdx = updatedCameras.indexWhere((c) => c.cameraName == _project.activeCamera);
      if (camIdx != -1) {
        updatedCameras[camIdx] = updatedCameras[camIdx].copyWith(clipName: clipNum);
      } else {
        updatedCameras.add(CameraTakeRecord(cameraName: _project.activeCamera, clipName: clipNum));
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
        isDs: isDs,
        isFf: isFf,
        isGpr: isGpr,
        isDr: isDr,
      );
    } else {
      final newRecord = ShotRecord(
        chapter: chapter,
        scene: scene,
        plane: plane.isNotEmpty ? plane : null,
        take: take.isNotEmpty ? take : '1',
        cameras: [
          CameraTakeRecord(cameraName: _project.activeCamera, clipName: clipNum),
        ],
        reel: targetReel,
        tcIn: prop.fileTcIn,
        tcOut: prop.fileTcOut,
        observations: notes.isNotEmpty ? notes : null,
        isMos: isMos,
        isTf: isTf,
        isDs: isDs,
        isFf: isFf,
        isGpr: isGpr,
        isDr: isDr,
      );
      records.add(newRecord);
    }

    final List<ShotRecord> finalRecords;
    if (_project.autoSortByClip) {
      finalRecords = BitacoraEditorTab.sortRecordsByClip(records, _project.activeCamera);
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

    if (prop.originalFilePath != null) {
      _livePastedOverrides.remove(prop.originalFilePath);
      _livePastedLineNumbers.remove(prop.originalFilePath);
    }

    await _generatePreview();

    if (_report != null && prop.originalFilePath != null) {
      final updated = _report!.proposals.where((p) => p.originalFilePath == prop.originalFilePath).toList();
      if (updated.isNotEmpty) {
        setState(() {
          _selectedStudioClip = updated.first;
        });
      }
    }
    _showNotification('Metadatos de claqueta actualizados');
  }

  Widget _buildCompactStatusBadge(RenameProposal proposal) {
    if (proposal.originalFilePath != null && _duplicateClipConflicts.containsKey(proposal.originalFilePath)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('Conflicto', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
      );
    }
    if (proposal.originalFilePath != null && _livePastedOverrides.containsKey(proposal.originalFilePath)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green.shade700,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('✓ Texto', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
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
        color = Colors.blue;
        label = 'OK';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStudioMediaList() {
    final mediaClips = _report?.proposals.where((p) => !p.isCompanionFile).toList() ?? [];
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
                Icon(Icons.video_library_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Clips de Medios (${mediaClips.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                      final isSelected = _selectedStudioClip?.originalFilePath == clip.originalFilePath;
                      final fileName = clip.originalFilePath != null
                          ? p.basename(clip.originalFilePath!)
                          : clip.proposedFileName;
                      final reel = _getProposalReel(clip);
                      final clipNum = ClipMatcherService.extractClipNumber(fileName);
                      final isLiveMatched = clip.originalFilePath != null &&
                          _livePastedOverrides.containsKey(clip.originalFilePath) &&
                          !_duplicateClipConflicts.containsKey(clip.originalFilePath);
                      final isConflict = clip.originalFilePath != null &&
                          _duplicateClipConflicts.containsKey(clip.originalFilePath);

                      Color? rowBg;
                      if (isSelected) {
                        rowBg = theme.colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.15);
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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: rowBg,
                            border: Border(
                              bottom: BorderSide(
                                color: theme.dividerColor.withValues(alpha: 0.15),
                              ),
                              left: isSelected
                                  ? BorderSide(color: theme.colorScheme.primary, width: 3)
                                  : BorderSide.none,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isConflict
                                    ? Icons.warning_amber_rounded
                                    : (isLiveMatched ? Icons.check_circle : Icons.movie_outlined),
                                size: 18,
                                color: isConflict
                                    ? Colors.red
                                    : (isLiveMatched
                                        ? Colors.green
                                        : (isSelected ? theme.colorScheme.primary : theme.hintColor)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fileName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected ? theme.colorScheme.primary : null,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Reel: $reel | Clip: #$clipNum${clip.associatedRecord != null ? ' | Esc: ${clip.associatedRecord!.scene} T: ${clip.associatedRecord!.take}' : ''}',
                                      style: TextStyle(fontSize: 10, color: theme.hintColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
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

  Widget _buildStudioCenterInspector() {
    final theme = Theme.of(context);
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
                Icon(Icons.video_library_outlined, size: 56, color: theme.hintColor.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                const Text('Ningún clip seleccionado', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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

    final originalName = clip.originalFilePath != null ? p.basename(clip.originalFilePath!) : '—';
    final proposedName = _computeStudioProposedBanner(clip);
    final tcIn = clip.fileTcIn ?? '00:00:00:00';
    final tcOut = clip.fileTcOut ?? '00:00:00:00';
    final hasVideo = clip.originalFilePath != null &&
        _isPlayableVideo(clip.originalFilePath) &&
        _studioVideoController != null;

    final hasVisibleFlags = _project.showMos ||
        _project.showTf ||
        _project.showDs ||
        _project.showFf ||
        _project.showGpr ||
        _project.showDr;

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
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Proposal Name Banner (Top of center pane, above video player)
            Container(
              key: const ValueKey('studio_proposed_banner'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.drive_file_rename_outline, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  const Text('Propuesta: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  Expanded(
                    child: Text(
                      proposedName,
                      key: const ValueKey('studio_proposed_banner_text'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 2. Video Player Area (Expanded to consume all remaining vertical space)
            Expanded(
              child: Container(
                key: const ValueKey('studio_video_player_container'),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRect(
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerSignal: (pointerSignal) {
                          if (pointerSignal is PointerScrollEvent) {
                            if (pointerSignal.scrollDelta.dy < 0) {
                              _studioZoomIn(focalPoint: pointerSignal.localPosition);
                            } else if (pointerSignal.scrollDelta.dy > 0) {
                              _studioZoomOut(focalPoint: pointerSignal.localPosition);
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
                                              const Icon(Icons.movie_filter_rounded, size: 52, color: Colors.white38),
                                              const SizedBox(height: 8),
                                              Text(
                                                originalName,
                                                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Timecode: $tcIn → $tcOut',
                                                style: const TextStyle(fontFamily: 'monospace', color: Colors.white54, fontSize: 11),
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

                    // Floating Magnifier HUD Overlay
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        key: const ValueKey('studio_magnifier_hud'),
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
                              key: const ValueKey('studio_zoom_out_button'),
                              icon: const Icon(Icons.zoom_out, size: 16, color: Colors.white),
                              tooltip: 'Alejar',
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: _studioCurrentZoom > 1.05 ? _studioZoomOut : null,
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
                              icon: const Icon(Icons.zoom_in, size: 16, color: Colors.white),
                              tooltip: 'Acercar',
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: _studioCurrentZoom < 4.95 ? _studioZoomIn : null,
                            ),
                            if (_studioCurrentZoom > 1.05) ...[
                              Container(
                                height: 16,
                                width: 1,
                                color: Colors.white24,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                              ),
                              IconButton(
                                key: const ValueKey('studio_zoom_reset_button'),
                                icon: const Icon(Icons.restart_alt, size: 16, color: Colors.white),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Dedicated Studio Transport Bar
            Container(
              key: const ValueKey('studio_transport_bar'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? const Color(0xFF1E1E24) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
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
                              : (durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0);

                          return SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
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
                                final targetDuration = Duration(milliseconds: targetMs);
                                _studioPlayer?.seek(targetDuration);
                                setState(() {
                                  _studioIsDraggingSlider = false;
                                  _studioPositionNotifier.value = targetDuration;
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
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Play / Pause
                          ValueListenableBuilder<bool>(
                            valueListenable: _studioIsPlayingNotifier,
                            builder: (context, isPlaying, _) {
                              return IconButton(
                                key: const ValueKey('studio_play_pause_button'),
                                icon: Icon(
                                  isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                  size: 22,
                                  color: theme.colorScheme.primary,
                                ),
                                tooltip: isPlaying ? 'Pausar' : 'Reproducir',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  if (_studioPlayer != null) {
                                    _studioPlayer!.playOrPause();
                                  } else {
                                    _studioIsPlayingNotifier.value = !_studioIsPlayingNotifier.value;
                                  }
                                },
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          // 5s jump back
                          IconButton(
                            key: const ValueKey('studio_replay_5_button'),
                            icon: const Icon(Icons.replay_5, size: 18),
                            tooltip: 'Retroceder 5s',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              final target = _studioPositionNotifier.value - const Duration(seconds: 5);
                              final clamped = target < Duration.zero ? Duration.zero : target;
                              _studioPlayer?.seek(clamped);
                              _studioPositionNotifier.value = clamped;
                            },
                          ),
                          const SizedBox(width: 4),
                          // 5s jump forward
                          IconButton(
                            key: const ValueKey('studio_forward_5_button'),
                            icon: const Icon(Icons.forward_5, size: 18),
                            tooltip: 'Avanzar 5s',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              final max = _studioDurationNotifier.value;
                              final target = _studioPositionNotifier.value + const Duration(seconds: 5);
                              final clamped = max > Duration.zero && target > max ? max : target;
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
                                    key: const ValueKey('studio_duration_text'),
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
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Live Running SMPTE Timecode Badge
                          ValueListenableBuilder<Duration>(
                            valueListenable: _studioPositionNotifier,
                            builder: (context, position, _) {
                              final liveSmpte = _computeLiveSmpte(position, clip.fileTcIn, _project.log.metadata.frameRate);
                              return Container(
                                key: const ValueKey('studio_live_smpte_badge'),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.access_time_rounded, size: 11, color: theme.colorScheme.primary),
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
                          const SizedBox(width: 6),
                          // Volume toggle & slider
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
                                        key: const ValueKey('studio_volume_button'),
                                        icon: Icon(
                                          isMuted || volume <= 0.0
                                              ? Icons.volume_off
                                              : (volume < 50 ? Icons.volume_down : Icons.volume_up),
                                          size: 16,
                                        ),
                                        tooltip: isMuted ? 'Activar sonido' : 'Silenciar',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () {
                                          if (isMuted) {
                                            final target = _studioPreMuteVolume > 0 ? _studioPreMuteVolume : 100.0;
                                            _studioPlayer?.setVolume(target);
                                            _studioVolumeNotifier.value = target;
                                            _studioIsMutedNotifier.value = false;
                                          } else {
                                            _studioPreMuteVolume = volume;
                                            _studioPlayer?.setVolume(0.0);
                                            _studioVolumeNotifier.value = 0.0;
                                            _studioIsMutedNotifier.value = true;
                                          }
                                        },
                                      ),
                                      SizedBox(
                                        width: 48,
                                        child: SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            trackHeight: 2,
                                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3),
                                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 6),
                                          ),
                                          child: Slider(
                                            key: const ValueKey('studio_volume_slider'),
                                            value: volume.clamp(0.0, 100.0),
                                            min: 0.0,
                                            max: 100.0,
                                            onChanged: (val) {
                                              _studioPlayer?.setVolume(val);
                                              _studioVolumeNotifier.value = val;
                                              _studioIsMutedNotifier.value = val <= 0.0;
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
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 3. Editable Slate Card (Intrinsic height, not Expanded)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.movie_creation_outlined, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      const Text(
                        'Claqueta y Bitácora',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          key: const ValueKey('studio_static_tc_badge'),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
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
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save, size: 14),
                        label: const Text('Guardar'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          textStyle: const TextStyle(fontSize: 11),
                          minimumSize: Size.zero,
                        ),
                        onPressed: _saveStudioSlate,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_project.showChapter) ...[
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _studioChapterController,
                            focusNode: _studioChapterFocusNode,
                            decoration: const InputDecoration(
                              labelText: 'Cap',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(fontSize: 12),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _studioSceneController,
                          focusNode: _studioSceneFocusNode,
                          decoration: const InputDecoration(
                            labelText: 'Escena',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          style: const TextStyle(fontSize: 12),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _studioTakeController,
                          focusNode: _studioTakeFocusNode,
                          decoration: const InputDecoration(
                            labelText: 'Toma',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          style: const TextStyle(fontSize: 12),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (_project.showPlane) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _studioPlaneController,
                            focusNode: _studioPlaneFocusNode,
                            decoration: const InputDecoration(
                              labelText: 'Plano',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(fontSize: 12),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (hasVisibleFlags) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (_project.showMos)
                          _buildStudioFlagChip(
                            key: 'studio_flag_mos',
                            label: 'MOS',
                            selected: _studioIsMos,
                            onSelected: (val) => setState(() => _studioIsMos = val),
                          ),
                        if (_project.showTf)
                          _buildStudioFlagChip(
                            key: 'studio_flag_tf',
                            label: 'TF (Toma Falsa)',
                            selected: _studioIsTf,
                            onSelected: (val) => setState(() => _studioIsTf = val),
                          ),
                        if (_project.showDs)
                          _buildStudioFlagChip(
                            key: 'studio_flag_ds',
                            label: 'DS (Driving Shot)',
                            selected: _studioIsDs,
                            onSelected: (val) => setState(() => _studioIsDs = val),
                          ),
                        if (_project.showFf)
                          _buildStudioFlagChip(
                            key: 'studio_flag_ff',
                            label: 'FF (Free Fly)',
                            selected: _studioIsFf,
                            onSelected: (val) => setState(() => _studioIsFf = val),
                          ),
                        if (_project.showGpr)
                          _buildStudioFlagChip(
                            key: 'studio_flag_gpr',
                            label: 'GPR (GoPro)',
                            selected: _studioIsGpr,
                            onSelected: (val) => setState(() => _studioIsGpr = val),
                          ),
                        if (_project.showDr)
                          _buildStudioFlagChip(
                            key: 'studio_flag_dr',
                            label: 'DR (Drone)',
                            selected: _studioIsDr,
                            onSelected: (val) => setState(() => _studioIsDr = val),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: _studioNotesController,
                    focusNode: _studioNotesFocusNode,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones / Notas',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
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
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
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

  List<RenameProposal> get _studioMediaClips =>
      _report?.proposals.where((p) => !p.isCompanionFile).toList() ?? [];

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

  KeyEventResult _handleStudioWorkspaceKeyEvent(FocusNode node, KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isRepeat = event is KeyRepeatEvent;
    final isAction = isDown || isRepeat;

    final isCtrlOrMeta = HardwareKeyboard.instance.isControlPressed ||
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
          final mediaWidth = widths.mediaWidth;
          final conventionWidth = widths.conventionWidth;

          final mediaWidget = SizedBox(
            width: mediaWidth,
            child: _buildStudioMediaList(),
          );
          final conventionWidget = _buildConventionEditorPane(
            width: conventionWidth,
          );
          final centerWidget = Expanded(
            child: _buildStudioCenterInspector(),
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: isMediaRight
                ? [
                    conventionWidget,
                    const SizedBox(width: 12),
                    centerWidget,
                    const SizedBox(width: 12),
                    mediaWidget,
                  ]
                : [
                    mediaWidget,
                    const SizedBox(width: 12),
                    centerWidget,
                    const SizedBox(width: 12),
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
        content: const Text('Se restaurarán los nombres originales de los archivos procesados en este lote.'),
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
                  icon: Icon(isCurrentDark ? Icons.light_mode : Icons.dark_mode),
                  tooltip: 'Cambiar modo oscuro / claro',
                  onPressed: () async {
                    final newMode = isCurrentDark ? ThemeMode.light : ThemeMode.dark;
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
            unselectedLabelColor: isDark ? const Color(0xFF8E8E9F) : const Color(0xFF64748B),
            onTap: (index) {
              if (index == 0) {
                _disposeStudioPlayer();
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
                  Actions.maybeInvoke(primary!.context!, const UndoTextIntent(SelectionChangedCause.keyboard));
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
                  Actions.maybeInvoke(primary!.context!, const UndoTextIntent(SelectionChangedCause.keyboard));
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
                                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                                children: _appSettings.renamerPaneLayout == 'media_right'
                                                    ? [
                                                        _buildConventionEditorPane(),
                                                        const SizedBox(width: 16),
                                                        Expanded(child: _buildPreviewTable()),
                                                      ]
                                                    : [
                                                        Expanded(child: _buildPreviewTable()),
                                                        const SizedBox(width: 16),
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
    final playablePlaylist = _report?.proposals
            .where((p) => p.originalFilePath != null && _isPlayableVideo(p.originalFilePath))
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
              value: _project.cameraNames.contains(_project.activeCamera) 
                  ? _project.activeCamera 
                  : (_project.cameraNames.isNotEmpty ? _project.cameraNames.first : null),
              items: _project.cameraNames.isEmpty 
                  ? [const DropdownMenuItem(value: 'A', child: Text('Cámara A'))]
                  : _project.cameraNames.map((cam) => DropdownMenuItem(value: cam, child: Text('Cámara $cam'))).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    String oldCamera = _project.activeCamera;
                    _project = _project.copyWith(activeCamera: val);
                    
                    if (_reelController.text.isEmpty) {
                      _reelController.text = _computeDefaultReel(_project.activeCamera);
                    } else {
                      String currentText = _reelController.text.trim();
                      final letterMatch = RegExp(r'^([A-Za-z])(\d+.*)$').firstMatch(currentText);
                      final numericMatch = RegExp(r'^(\d+.*)$').firstMatch(currentText);
                      
                      if (letterMatch != null && letterMatch.group(1)!.toUpperCase() == oldCamera) {
                        _reelController.text = '${_project.activeCamera}${letterMatch.group(2)}';
                      } else if (numericMatch != null) {
                        _reelController.text = '${_project.activeCamera}$currentText';
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
              message: 'Alternar entre vista de tabla y modo estudio de 3 paneles',
              child: OutlinedButton.icon(
                icon: Icon(
                  _isStudioMode
                      ? Icons.dashboard_customize_rounded
                      : Icons.video_settings_rounded,
                ),
                label: Text(
                  _isStudioMode ? 'Vista Tabla' : 'Modo Estudio',
                ),
                onPressed: () {
                  setState(() {
                    _isStudioMode = !_isStudioMode;
                    if (_isStudioMode && _selectedStudioClip == null) {
                      final clips = _report?.proposals.where((p) => !p.isCompanionFile).toList() ?? [];
                      if (clips.isNotEmpty) {
                        _selectStudioClip(clips.first);
                      }
                    }
                  });
                },
              ),
            ),
            Tooltip(
              message: 'Mostrar/ocultar el panel de edición y pegado de convención',
              child: OutlinedButton.icon(
                icon: Icon(
                  _showConventionEditorPane
                      ? Icons.view_sidebar_rounded
                      : Icons.view_sidebar_outlined,
                ),
                label: Text(
                  _showConventionEditorPane ? 'Ocultar Editor' : 'Editor de Texto',
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
                avatar: const Icon(Icons.check_circle, size: 16, color: Colors.green),
                label: Text(
                  _mediaFolderPath!.split(Platform.pathSeparator).last,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
        color: _isNotificationError ? Colors.red.shade100 : Colors.green.shade100,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Icon(
                _isNotificationError ? Icons.error_outline : Icons.check_circle_outline,
                color: _isNotificationError ? Colors.red.shade900 : Colors.green.shade900,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _notificationMessage!,
                  style: TextStyle(
                    color: _isNotificationError ? Colors.red.shade900 : Colors.green.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearNotification,
                color: _isNotificationError ? Colors.red.shade900 : Colors.green.shade900,
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
              Icon(Icons.folder_open, size: 52, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
              const SizedBox(height: 12),
              Text(
                'Bitácora activa con ${_project.log.records.length} tomas registradas',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Haz clic en "Selector de Carpeta de Medios" para conciliar los clips con la Cámara ${_project.activeCamera}.',
                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined, size: 52, color: Theme.of(context).hintColor.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            const Text(
              'Bienvenido al Renombrador de Medios',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Puedes seleccionar una Carpeta de Medios o Importar un Excel para comenzar.',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final mediaClips = _report!.proposals.where((p) => !p.isCompanionFile).toList();
    if (mediaClips.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.find_in_page_outlined, size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(
              'No se detectaron archivos de video para la Cámara ${_project.activeCamera} en esta carpeta.',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Verifica que la carpeta contenga clips con el prefijo "${_project.activeCamera}" o selecciona otra carpeta.',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
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

    if (_selectedReelFilter != null && !reelCounts.containsKey(_selectedReelFilter)) {
      _selectedReelFilter = null;
    }

    List<RenameProposal> displayProposals = _report!.proposals;
    if (!_renameMetadata) {
      displayProposals = displayProposals.where((p) => !p.isCompanionFile).toList();
    }

    if (_selectedReelFilter != null) {
      displayProposals = displayProposals.where((p) => _getProposalReel(p) == _selectedReelFilter).toList();
    }

    if (_filterOnlyConventionMatches) {
      displayProposals = displayProposals
          .where((p) => p.originalFilePath != null && _livePastedOverrides.containsKey(p.originalFilePath))
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
                      avatar: const Icon(Icons.check, size: 14, color: Colors.green),
                      label: Text('Solo coincidentes (${_livePastedOverrides.length})'),
                      selected: _filterOnlyConventionMatches,
                      onSelected: (sel) => setState(() => _filterOnlyConventionMatches = sel),
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
              border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Se detectaron ${displayProposals.length} archivos en la carpeta de medios. La bitácora aún no tiene tomas registradas; importa un Excel o usa la pestaña "Bitácora Digital" para asignar nombres propuestos.',
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.amber.shade200 : Colors.amber.shade900,
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
                      final isMediaRight = _appSettings.renamerPaneLayout == 'media_right';

                      return DataTable(
                        columnSpacing: 24,
                        headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                        columns: isMediaRight
                            ? const [
                                DataColumn(label: Text('Nombre Propuesto')),
                                DataColumn(label: Text('Escena / Toma')),
                                DataColumn(label: Text('Archivo Original')),
                                DataColumn(label: Text('TC Archivo (In → Out)')),
                                DataColumn(label: Text('Estado')),
                              ]
                            : const [
                                DataColumn(label: Text('Archivo Original')),
                                DataColumn(label: Text('TC Archivo (In → Out)')),
                                DataColumn(label: Text('Nombre Propuesto')),
                                DataColumn(label: Text('Escena / Toma')),
                                DataColumn(label: Text('Estado')),
                              ],
                        rows: displayProposals.map((proposal) {
                          String original = proposal.originalFilePath != null ? p.basename(proposal.originalFilePath!) : '—';
                          String proposed = proposal.proposedFileName;
                          if (proposal.originalFilePath != null && _livePastedOverrides.containsKey(proposal.originalFilePath)) {
                            final liveName = _livePastedOverrides[proposal.originalFilePath]!;
                            final origExt = p.extension(proposal.originalFilePath!);
                            if (p.extension(liveName).isEmpty && origExt.isNotEmpty) {
                              proposed = '$liveName$origExt';
                            } else {
                              proposed = liveName;
                            }
                          } else if (proposal.status == ProposalStatus.unmatchedClip) {
                            proposed = '—';
                          }

                          String sceneTake = '—';
                          if (proposal.associatedRecord != null) {
                            String takeStr = proposal.associatedRecord!.take;
                            String displayTake = takeStr.toUpperCase().startsWith('T') ? takeStr : 'T$takeStr';
                            sceneTake = 'Esc. ${proposal.associatedRecord!.scene} - $displayTake';
                          }

                          final logTc = proposal.associatedRecord?.tcIn;
                          final fileTc = proposal.fileTcIn;
                          final hasLogTc = logTc != null && logTc.trim().isNotEmpty;
                          final hasFileTc = fileTc != null && fileTc.trim().isNotEmpty;
                          final isMatched = proposal.isTimecodeMatched;

                          final isPlayable = _isPlayableVideo(proposal.originalFilePath);

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
                                      message: 'Reproducir e inspeccionar video',
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 6.0),
                                        child: Icon(
                                          Icons.play_circle_outline,
                                          size: 16,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                Text(original),
                              ],
                            ),
                            onDoubleTap: isPlayable ? () => _openMediaPreview(proposal) : null,
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
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : Text('—', style: TextStyle(color: Theme.of(context).hintColor)),
                          );

                          // Nombre Propuesto cell
                          final isLiveMatched = proposal.originalFilePath != null &&
                              _livePastedOverrides.containsKey(proposal.originalFilePath) &&
                              !_duplicateClipConflicts.containsKey(proposal.originalFilePath);

                          final cellProposed = DataCell(
                            isLiveMatched
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
                                      const SizedBox(width: 6),
                                      Text(
                                        proposed,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
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
                                    message: 'El reel del archivo (${proposal.fileReel ?? "—"}) no coincide con el registrado en bitácora (${proposal.associatedRecord?.reel ?? "—"})',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.amber),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Reel: ${proposal.associatedRecord?.reel ?? '—'} ≠ ${proposal.fileReel}',
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                if (isMatched) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.green),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.check_circle, size: 12, color: Colors.green),
                                        const SizedBox(width: 4),
                                        Text(
                                          proposal.timecodeDeltaSeconds != null && proposal.timecodeDeltaSeconds! > 0
                                              ? 'TC Coincide (±${proposal.timecodeDeltaSeconds}s)'
                                              : 'TC Coincide',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (hasLogTc && hasFileTc && !isMatched) ...[
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: 'El timecode del archivo ($fileTc) no coincide con el registrado en bitácora ($logTc)',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: Colors.amber),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.warning_amber_rounded, size: 12, color: Colors.amber),
                                          SizedBox(width: 4),
                                          Text(
                                            'TC Diferente',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
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
                          final hasDuplicateConflict = proposal.originalFilePath != null &&
                              _duplicateClipConflicts.containsKey(proposal.originalFilePath);
                          final hasStandardConflict = proposal.status == ProposalStatus.conflict;

                          final cellStatus = DataCell(
                            hasDuplicateConflict || hasStandardConflict
                                ? Tooltip(
                                    message: 'Haz clic para resolver este conflicto',
                                    child: InkWell(
                                      onTap: _openConflictResolver,
                                      borderRadius: BorderRadius.circular(12),
                                      child: _buildStatusBadge(
                                        ProposalStatus.conflict,
                                        conflictReason: hasDuplicateConflict
                                            ? _duplicateClipConflicts[proposal.originalFilePath]
                                            : null,
                                      ),
                                    ),
                                  )
                                    : isLiveMatched
                                        ? _buildStatusBadge(
                                            ProposalStatus.ready,
                                            customText: _livePastedLineNumbers[proposal.originalFilePath] != null
                                                ? '✓ Texto (Línea ${_livePastedLineNumbers[proposal.originalFilePath]})'
                                                : '✓ Coincide con texto',
                                          )
                                        : _buildStatusBadge(proposal.status),
                          );

                          return DataRow(
                            color: WidgetStateProperty.resolveWith<Color?>(
                              (states) => isLiveMatched ? Colors.green.withValues(alpha: 0.12) : null,
                            ),
                            cells: isMediaRight
                                ? [cellProposed, cellSceneTake, cellOriginal, cellTc, cellStatus]
                                : [cellOriginal, cellTc, cellProposed, cellSceneTake, cellStatus],
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

  Widget _buildStatusBadge(ProposalStatus status, {String? conflictReason, String? customText}) {
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
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildFooter() {
    int listos = _report?.totalMatched ?? 0;
    int faltantes = _report?.totalMissing ?? 0;
    int noRegistrados = _report?.totalUnmatched ?? 0;

    int readyToRename = _report?.proposals.where((p) {
      if (p.status != ProposalStatus.ready) return false;
      if (!_renameMetadata && p.isCompanionFile) return false;
      return true;
    }).length ?? 0;

    int totalDuplicateConflicts = _duplicateClipConflicts.length;
    int standardConflictCount = _report?.proposals.where((p) => p.status == ProposalStatus.conflict && !p.isCompanionFile).length ?? 0;
    int conflictCount = standardConflictCount + totalDuplicateConflicts;
    bool hasConflicts = (_report?.proposals.any((p) => p.status == ProposalStatus.conflict) ?? false) ||
        _duplicateClipConflicts.isNotEmpty;

    final summaryText = '$listos listos | $faltantes faltantes en disco | $noRegistrados no registrados';

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

    bool anyHandled = false;
    for (final item in files) {
      final String path = item.path as String;
      if (path.isEmpty) continue;

      // 1. Directory -> Media Folder
      if (Directory(path).existsSync()) {
        setState(() {
          _mediaFolderPath = path;
          _manualOverrides = {};
          _baseReport = null;
        });
        await _generatePreview();
        anyHandled = true;
        if (mounted) {
          _showNotification('Carpeta de medios cargada: ${p.basename(path)} (${_report?.proposals.length ?? 0} clips detectados)');
        }
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
          anyHandled = true;
          if (mounted) {
            _showNotification('Bitácora importada: ${p.basename(path)} (${log.records.length} tomas registradas)');
          }
        } catch (e) {
          if (mounted) {
            _showNotification('Error al leer la bitácora: Verifique que sea un archivo Excel válido', isError: true);
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

    if (!anyHandled && mounted) {
      final firstFileName = p.basename(files.first.path as String);
      _showNotification(
        'Archivo no soportado: "$firstFileName". Formatos aceptados: carpetas de medios, Excel (.xlsx, .xls), bitácoras de texto (.rtf, .txt), Apple Pages (.pages) o proyectos (.renombrata).',
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
        _showNotification('Error al leer la bitácora de texto: $e', isError: true);
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
            _showNotification('Bitácora de Apple Pages importada: ${p.basename(path)} (${log.records.length} tomas registradas)');
          }
          return true;
        } else {
          if (mounted) {
            _showNotification('No se pudo convertir el archivo de Apple Pages. Verifique que la aplicación Pages esté instalada.', isError: true);
          }
          return false;
        }
      } catch (e) {
        if (mounted) {
          _showNotification('Error al convertir archivo de Pages: $e', isError: true);
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
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
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
                        _buildOverlayBadge(Icons.folder_outlined, 'Carpeta de Medios', primaryColor),
                        _buildOverlayBadge(Icons.table_chart_outlined, 'Bitácora (.xlsx, .rtf, .txt, .pages)', Colors.green.shade600),
                        _buildOverlayBadge(Icons.description_outlined, 'Proyecto (.renombrata)', Colors.purple.shade400),
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
        final double length = (distance + dash <= metric.length) ? dash : metric.length - distance;
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
