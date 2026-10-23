class AppSettings {
  final bool usePagesStyleLayout;
  final bool autoSortByClip;

  const AppSettings({
    this.usePagesStyleLayout = true,
    this.autoSortByClip = true,
  });

  factory AppSettings.defaults() => const AppSettings();

  AppSettings copyWith({
    bool? usePagesStyleLayout,
    bool? autoSortByClip,
  }) {
    return AppSettings(
      usePagesStyleLayout: usePagesStyleLayout ?? this.usePagesStyleLayout,
      autoSortByClip: autoSortByClip ?? this.autoSortByClip,
    );
  }

  Map<String, dynamic> toJson() => {
    'usePagesStyleLayout': usePagesStyleLayout,
    'autoSortByClip': autoSortByClip,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      usePagesStyleLayout: json['usePagesStyleLayout'] as bool? ?? true,
      autoSortByClip: json['autoSortByClip'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          usePagesStyleLayout == other.usePagesStyleLayout &&
          autoSortByClip == other.autoSortByClip;

  @override
  int get hashCode => Object.hash(usePagesStyleLayout, autoSortByClip);
}
