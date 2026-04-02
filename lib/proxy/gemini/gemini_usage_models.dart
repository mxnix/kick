import '../model_catalog.dart';

enum GeminiUsageBucketHealth { healthy, low, critical }

class GeminiUsageBucket {
  const GeminiUsageBucket({
    required this.modelId,
    required this.remainingFraction,
    this.resetAt,
    this.tokenType = '',
  });

  final String modelId;
  final double remainingFraction;
  final DateTime? resetAt;
  final String tokenType;

  double get usedPercent => (1 - remainingFraction).clamp(0, 1) * 100;

  double get remainingPercent => remainingFraction * 100;

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

  static String _readString(Object? value) => value?.toString().trim() ?? '';

  static double _readFraction(Object? value) {
    final numeric = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };

    if (numeric == null || !numeric.isFinite) {
      return 0;
    }

    return numeric.clamp(0, 1);
  }

  static DateTime? _readDateTime(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text)?.toLocal();
  }
}

class GeminiUsageSnapshot {
  const GeminiUsageSnapshot({
    required this.fetchedAt,
    required this.subscriptionTitle,
    required this.buckets,
  });

  final DateTime fetchedAt;
  final String subscriptionTitle;
  final List<GeminiUsageBucket> buckets;

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

  static int _compareBuckets(GeminiUsageBucket left, GeminiUsageBucket right) {
    final leftIndex = _bundledModelOrderIndex(left.modelId);
    final rightIndex = _bundledModelOrderIndex(right.modelId);
    final leftKnown = leftIndex != -1;
    final rightKnown = rightIndex != -1;

    if (leftKnown && rightKnown && leftIndex != rightIndex) {
      return leftIndex.compareTo(rightIndex);
    }
    if (leftKnown != rightKnown) {
      return leftKnown ? -1 : 1;
    }
    return left.modelId.compareTo(right.modelId);
  }

  static int _bundledModelOrderIndex(String modelId) {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) {
      return -1;
    }

    final direct = ModelCatalog.bundledModels.indexOf(trimmed);
    if (direct != -1) {
      return direct;
    }

    final previewVariant = trimmed.endsWith('-preview')
        ? trimmed.substring(0, trimmed.length - '-preview'.length)
        : '$trimmed-preview';
    return ModelCatalog.bundledModels.indexOf(previewVariant);
  }
}
