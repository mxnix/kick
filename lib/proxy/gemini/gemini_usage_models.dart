import '../model_catalog.dart';

enum GeminiUsageBucketHealth { healthy, low, critical }

class GeminiUsageBucket {
  const GeminiUsageBucket({
    required this.modelId,
    required this.remainingFraction,
    this.resetAt,
    this.tokenType = '',
    this.currentUsage,
    this.usageLimit,
    this.unit = '',
  });

  final String modelId;
  final double remainingFraction;
  final DateTime? resetAt;
  final String tokenType;
  final double? currentUsage;
  final double? usageLimit;
  final String unit;

  double get usedPercent => (1 - remainingFraction).clamp(0, 1) * 100;

  double get remainingPercent => remainingFraction * 100;

  bool get hasAbsoluteUsage => currentUsage != null && usageLimit != null && usageLimit! > 0;

  GeminiUsageBucketHealth get health {
    if (remainingFraction <= 0.10) {
      return GeminiUsageBucketHealth.critical;
    }
    if (remainingFraction <= 0.25) {
      return GeminiUsageBucketHealth.low;
    }
    return GeminiUsageBucketHealth.healthy;
  }

  static GeminiUsageBucket fromApi(Map<String, Object?> json) {
    return GeminiUsageBucket(
      modelId: ModelCatalog.normalizeModel(_readString(json['modelId'])),
      remainingFraction: _readFraction(json['remainingFraction']),
      resetAt: _readDateTime(json['resetTime']),
      tokenType: _readString(json['tokenType']).toUpperCase(),
    );
  }

  static GeminiUsageBucket fromKiroUsageBreakdown(
    Map<String, Object?> json, {
    DateTime? defaultResetAt,
  }) {
    final currentUsage = _readNumber(
      _firstPresent(json, const ['currentUsageWithPrecision', 'currentUsage']),
    );
    final usageLimit = _readNumber(
      _firstPresent(json, const ['usageLimitWithPrecision', 'usageLimit']),
    );
    final unit = _readString(json['unit']);
    final resourceType = _readString(json['resourceType']);
    final displayName = _firstNonEmpty(
      _readString(json['displayName']),
      _readString(json['displayNamePlural']),
      resourceType,
      'Kiro usage',
    );

    return GeminiUsageBucket(
      modelId: displayName,
      remainingFraction: _remainingFractionFromUsage(currentUsage, usageLimit),
      resetAt: _readUnixSeconds(json['nextDateReset']) ?? defaultResetAt,
      tokenType: _firstNonEmpty(unit, resourceType).toUpperCase(),
      currentUsage: currentUsage,
      usageLimit: usageLimit,
      unit: unit,
    );
  }

  static String _readString(Object? value) => value?.toString().trim() ?? '';

  static double _readFraction(Object? value) {
    final numeric = switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text),
      _ => null,
    };

    if (numeric == null || !numeric.isFinite) {
      return 0;
    }

    return numeric.clamp(0, 1);
  }

  static double? _readNumber(Object? value) {
    final numeric = switch (value) {
      final num number => number.toDouble(),
      final String text => double.tryParse(text.trim()),
      _ => null,
    };
    if (numeric == null || !numeric.isFinite) {
      return null;
    }
    return numeric;
  }

  static DateTime? _readDateTime(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text)?.toLocal();
  }

  static DateTime? _readUnixSeconds(Object? value) {
    final seconds = _readNumber(value);
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true).toLocal();
  }

  static Object? _firstPresent(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key)) {
        return json[key];
      }
    }
    return null;
  }

  static String _firstNonEmpty(String first, [String? second, String? third, String? fallback]) {
    for (final candidate in [first, second, third, fallback]) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  static double _remainingFractionFromUsage(double? currentUsage, double? usageLimit) {
    if (currentUsage == null || usageLimit == null || usageLimit <= 0) {
      return 0;
    }
    return ((usageLimit - currentUsage) / usageLimit).clamp(0, 1);
  }
}

class GeminiUsageSnapshot {
  const GeminiUsageSnapshot({
    required this.fetchedAt,
    required this.subscriptionTitle,
    required this.buckets,
    this.resolvedEmail,
  });

  final DateTime fetchedAt;
  final String subscriptionTitle;
  final List<GeminiUsageBucket> buckets;
  final String? resolvedEmail;

  double get totalUsed => buckets.fold(0, (sum, bucket) => sum + bucket.usedPercent);

  double get totalLimit => buckets.isEmpty ? 0 : buckets.length * 100;

  double get totalPercent => totalLimit == 0 ? 0 : (totalUsed / totalLimit) * 100;

  int get lowQuotaBucketCount =>
      buckets.where((bucket) => bucket.health != GeminiUsageBucketHealth.healthy).length;

  int get criticalBucketCount =>
      buckets.where((bucket) => bucket.health == GeminiUsageBucketHealth.critical).length;

  int get healthyBucketCount => buckets.length - lowQuotaBucketCount;

  DateTime? get nextResetAt {
    for (final bucket in buckets) {
      if (bucket.resetAt != null) {
        return bucket.resetAt;
      }
    }
    return null;
  }

  GeminiUsageBucket? get mostConstrainedBucket {
    if (buckets.isEmpty) {
      return null;
    }

    GeminiUsageBucket current = buckets.first;
    for (final bucket in buckets.skip(1)) {
      if (bucket.remainingFraction < current.remainingFraction) {
        current = bucket;
        continue;
      }
      if (bucket.remainingFraction == current.remainingFraction &&
          bucket.resetAt != null &&
          current.resetAt != null &&
          bucket.resetAt!.isBefore(current.resetAt!)) {
        current = bucket;
      }
    }
    return current;
  }

  static GeminiUsageSnapshot fromApi(Map<String, Object?> json, {DateTime? fetchedAt}) {
    final rawBuckets = (json['buckets'] as List?) ?? const [];
    final buckets = rawBuckets
        .whereType<Map>()
        .map((item) => GeminiUsageBucket.fromApi(item.cast<String, Object?>()))
        .where((bucket) => bucket.modelId.isNotEmpty)
        .toList();

    buckets.sort(_compareBuckets);

    return GeminiUsageSnapshot(
      fetchedAt: fetchedAt?.toLocal() ?? DateTime.now(),
      subscriptionTitle: 'Gemini CLI OAuth',
      buckets: List.unmodifiable(buckets),
    );
  }

  static GeminiUsageSnapshot fromKiroApi(Map<String, Object?> json, {DateTime? fetchedAt}) {
    final subscriptionInfo = ((json['subscriptionInfo'] as Map?) ?? const <String, Object?>{})
        .cast<String, Object?>();
    final defaultResetAt = GeminiUsageBucket._readUnixSeconds(json['nextDateReset']);
    final rawBreakdowns = (json['usageBreakdownList'] as List?) ?? const [];
    final buckets = rawBreakdowns
        .whereType<Map>()
        .map(
          (item) => GeminiUsageBucket.fromKiroUsageBreakdown(
            item.cast<String, Object?>(),
            defaultResetAt: defaultResetAt,
          ),
        )
        .where((bucket) => bucket.modelId.isNotEmpty)
        .toList();

    if (buckets.isEmpty) {
      final currentUsage = GeminiUsageBucket._readNumber(
        GeminiUsageBucket._firstPresent(json, const ['usedCount', 'currentUsage']),
      );
      final usageLimit = GeminiUsageBucket._readNumber(
        GeminiUsageBucket._firstPresent(json, const ['limitCount', 'usageLimit']),
      );
      if (currentUsage != null || usageLimit != null) {
        buckets.add(
          GeminiUsageBucket(
            modelId: 'CREDIT',
            remainingFraction: GeminiUsageBucket._remainingFractionFromUsage(
              currentUsage,
              usageLimit,
            ),
            resetAt: defaultResetAt,
            tokenType: 'CREDITS',
            currentUsage: currentUsage,
            usageLimit: usageLimit,
            unit: 'credits',
          ),
        );
      }
    }

    buckets.sort(_compareBuckets);

    final subscriptionTitle = GeminiUsageBucket._firstNonEmpty(
      GeminiUsageBucket._readString(subscriptionInfo['subscriptionTitle']),
      GeminiUsageBucket._readString(subscriptionInfo['type']),
      'Kiro',
    );

    final userInfo = ((json['userInfo'] as Map?) ?? const <String, Object?>{})
        .cast<String, Object?>();
    final email = GeminiUsageBucket._readString(userInfo['email']);

    return GeminiUsageSnapshot(
      fetchedAt: fetchedAt?.toLocal() ?? DateTime.now(),
      subscriptionTitle: subscriptionTitle,
      buckets: List.unmodifiable(buckets),
      resolvedEmail: email.isNotEmpty ? email : null,
    );
  }

  static int _compareBuckets(GeminiUsageBucket left, GeminiUsageBucket right) {
    return left.modelId.compareTo(right.modelId);
  }
}
