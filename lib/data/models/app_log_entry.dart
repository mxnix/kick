enum AppLogLevel { info, warning, error }

class AppLogEntry {
  const AppLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.route,
    required this.message,
    required this.maskedPayload,
    this.rawPayload,
  });

  final String id;
  final DateTime timestamp;
  final AppLogLevel level;
  final String category;
  final String? route;
  final String message;
  final String? maskedPayload;
  final String? rawPayload;

  Map<String, Object?> toDatabaseMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'category': category,
      'route': route,
      'message': message,
      'masked_payload': maskedPayload,
      'raw_payload': rawPayload,
    };
  }

  factory AppLogEntry.fromDatabaseMap(Map<String, Object?> map) {
    final route = map['route'] as String?;
    final maskedPayload = map['masked_payload'] as String?;
    final rawPayload = map['raw_payload'] as String?;
    return AppLogEntry(
      id: map['id'] as String? ?? '',
      timestamp:
          DateTime.tryParse(map['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      level: AppLogLevel.values.firstWhere(
        (value) => value.name == map['level'],
        orElse: () => AppLogLevel.info,
      ),
      category: map['category'] as String? ?? 'proxy',
      route: route == null || route.isEmpty ? null : route,
      message: map['message'] as String? ?? '',
      maskedPayload: maskedPayload == null || maskedPayload.isEmpty ? null : maskedPayload,
      rawPayload: rawPayload == null || rawPayload.isEmpty ? null : rawPayload,
    );
  }
}
