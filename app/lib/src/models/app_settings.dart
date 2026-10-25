/// `settings/app`. Defaults match the backend's.
class AppSettings {
  const AppSettings({
    this.lateTime = '08:00',
    this.timezone = 'Asia/Manila',
    this.duplicateWindowSeconds = 120,
    this.tagUrlBase = '',
    this.workDays = const [1, 2, 3, 4, 5],
  });

  factory AppSettings.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const AppSettings();
    const def = AppSettings();
    return AppSettings(
      lateTime: d['lateTime'] as String? ?? def.lateTime,
      timezone: d['timezone'] as String? ?? def.timezone,
      duplicateWindowSeconds:
          (d['duplicateWindowSeconds'] as num?)?.toInt() ??
          def.duplicateWindowSeconds,
      tagUrlBase: d['tagUrlBase'] as String? ?? def.tagUrlBase,
      workDays:
          (d['workDays'] as List?)
              ?.whereType<num>()
              .map((n) => n.toInt())
              .toList() ??
          def.workDays,
    );
  }

  final String lateTime;
  final String timezone;
  final int duplicateWindowSeconds;

  /// e.g. https://attendance.example.com/tag/ ; empty until the domain is set.
  final String tagUrlBase;

  /// ISO weekdays, 1 = Monday.
  final List<int> workDays;

  Map<String, dynamic> toMap() => {
    'lateTime': lateTime,
    'timezone': timezone,
    'duplicateWindowSeconds': duplicateWindowSeconds,
    'tagUrlBase': tagUrlBase,
    'workDays': workDays,
  };

  AppSettings copyWith({
    String? lateTime,
    String? timezone,
    int? duplicateWindowSeconds,
    String? tagUrlBase,
    List<int>? workDays,
  }) => AppSettings(
    lateTime: lateTime ?? this.lateTime,
    timezone: timezone ?? this.timezone,
    duplicateWindowSeconds:
        duplicateWindowSeconds ?? this.duplicateWindowSeconds,
    tagUrlBase: tagUrlBase ?? this.tagUrlBase,
    workDays: workDays ?? this.workDays,
  );
}
