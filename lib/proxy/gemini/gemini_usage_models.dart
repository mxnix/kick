import '../model_catalog.dart';

class GeminiUsageBucket {
  const GeminiUsageBucket({required this.modelId, required this.remainingFraction, this.resetAt});

  final String modelId;
  final double remainingFraction;
  final DateTime? resetAt;

  double get usedPercent => (1 - remainingFraction).clamp(0, 1) * 100;

  static GeminiUsageBucket fromApi(Map<String, Object?> json) {
    return GeminiUsageBucket(
      modelId: ModelCatalog.normalizeModel(_readString(json['modelId'])),
      remainingFraction: _readFraction(json['remainingFraction']),
      resetAt: _readDateTime(json['resetTime']),
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

  DateTime? get nextResetAt {
    for (final bucket in buckets) {
      if (bucket.resetAt != null) {
        return bucket.resetAt;
      }
    }
    return null;
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
    final leftIndex = ModelCatalog.bundledModels.indexOf(left.modelId);
    final rightIndex = ModelCatalog.bundledModels.indexOf(right.modelId);
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
}
