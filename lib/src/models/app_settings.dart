import 'package:flutter/foundation.dart';

class AppSettings {
  final bool usePagesStyleLayout;
  final bool autoSortByClip;
  final String renamerPaneLayout;
  final Map<String, String> shortcuts;
  final bool pauseVideoOnTabSwitch;
  final String? customStillsDirectoryPath;

  static const Map<String, String> defaultShortcuts = {
    'new_take': 'Ctrl+N',
    'duplicate_take': 'Ctrl+D',
    'stamp_cut': 'Ctrl+K',
    'undo_delete': 'Ctrl+Z',
    'save_project': 'Ctrl+S',
  };

  const AppSettings({
    this.usePagesStyleLayout = true,
    this.autoSortByClip = true,
    this.renamerPaneLayout = 'media_left',
    this.shortcuts = defaultShortcuts,
    this.pauseVideoOnTabSwitch = true,
    this.customStillsDirectoryPath,
  });

  factory AppSettings.defaults() => const AppSettings();

  AppSettings copyWith({
    bool? usePagesStyleLayout,
    bool? autoSortByClip,
    String? renamerPaneLayout,
    Map<String, String>? shortcuts,
    bool? pauseVideoOnTabSwitch,
    String? customStillsDirectoryPath,
    bool clearCustomStillsDirectoryPath = false,
  }) {
    return AppSettings(
      usePagesStyleLayout: usePagesStyleLayout ?? this.usePagesStyleLayout,
      autoSortByClip: autoSortByClip ?? this.autoSortByClip,
      renamerPaneLayout: renamerPaneLayout ?? this.renamerPaneLayout,
      shortcuts: shortcuts != null ? Map<String, String>.unmodifiable(shortcuts) : this.shortcuts,
      pauseVideoOnTabSwitch: pauseVideoOnTabSwitch ?? this.pauseVideoOnTabSwitch,
      customStillsDirectoryPath: clearCustomStillsDirectoryPath
          ? null
          : (customStillsDirectoryPath ?? this.customStillsDirectoryPath),
    );
  }

  Map<String, dynamic> toJson() => {
    'usePagesStyleLayout': usePagesStyleLayout,
    'autoSortByClip': autoSortByClip,
    'renamerPaneLayout': renamerPaneLayout,
    'shortcuts': shortcuts,
    'pauseVideoOnTabSwitch': pauseVideoOnTabSwitch,
    'customStillsDirectoryPath': customStillsDirectoryPath,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    Map<String, String> loadedShortcuts = defaultShortcuts;
    if (json['shortcuts'] is Map) {
      loadedShortcuts = {
        ...defaultShortcuts,
        ...(json['shortcuts'] as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      };
    }
    return AppSettings(
      usePagesStyleLayout: json['usePagesStyleLayout'] as bool? ?? true,
      autoSortByClip: json['autoSortByClip'] as bool? ?? true,
      renamerPaneLayout: json['renamerPaneLayout'] as String? ?? 'media_left',
      shortcuts: loadedShortcuts,
      pauseVideoOnTabSwitch: json['pauseVideoOnTabSwitch'] as bool? ?? true,
      customStillsDirectoryPath: json['customStillsDirectoryPath'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          usePagesStyleLayout == other.usePagesStyleLayout &&
          autoSortByClip == other.autoSortByClip &&
          renamerPaneLayout == other.renamerPaneLayout &&
          pauseVideoOnTabSwitch == other.pauseVideoOnTabSwitch &&
          customStillsDirectoryPath == other.customStillsDirectoryPath &&
          mapEquals(shortcuts, other.shortcuts);

  @override
  int get hashCode => Object.hash(
        usePagesStyleLayout,
        autoSortByClip,
        renamerPaneLayout,
        pauseVideoOnTabSwitch,
        customStillsDirectoryPath,
        Object.hashAll(shortcuts.entries),
      );
}
