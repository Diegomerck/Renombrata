import 'package:flutter/foundation.dart';

class AppSettings {
  final bool usePagesStyleLayout;
  final bool autoSortByClip;
  final String renamerPaneLayout;
  final Map<String, String> shortcuts;

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
  });

  factory AppSettings.defaults() => const AppSettings();

  AppSettings copyWith({
    bool? usePagesStyleLayout,
    bool? autoSortByClip,
    String? renamerPaneLayout,
    Map<String, String>? shortcuts,
  }) {
    return AppSettings(
      usePagesStyleLayout: usePagesStyleLayout ?? this.usePagesStyleLayout,
      autoSortByClip: autoSortByClip ?? this.autoSortByClip,
      renamerPaneLayout: renamerPaneLayout ?? this.renamerPaneLayout,
      shortcuts: shortcuts != null ? Map<String, String>.unmodifiable(shortcuts) : this.shortcuts,
    );
  }

  Map<String, dynamic> toJson() => {
    'usePagesStyleLayout': usePagesStyleLayout,
    'autoSortByClip': autoSortByClip,
    'renamerPaneLayout': renamerPaneLayout,
    'shortcuts': shortcuts,
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
          mapEquals(shortcuts, other.shortcuts);

  @override
  int get hashCode => Object.hash(
        usePagesStyleLayout,
        autoSortByClip,
        renamerPaneLayout,
        Object.hashAll(shortcuts.entries),
      );
}
