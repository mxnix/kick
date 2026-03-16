import '../../core/accounts/account_priority.dart';
import '../../data/models/account_profile.dart';
import '../../data/models/oauth_tokens.dart';
import '../model_catalog.dart';

class ProxyRuntimeAccount {
  ProxyRuntimeAccount({
    required this.id,
    required this.label,
    required this.email,
    required this.projectId,
    required this.enabled,
    required this.priority,
    required this.notSupportedModels,
    required this.lastUsedAt,
    required this.usageCount,
    required this.errorCount,
    required this.cooldownUntil,
    required this.lastQuotaSnapshot,
    required this.tokenRef,
    required this.tokens,
  });

  final String id;
  final String label;
  final String email;
  final String projectId;
  bool enabled;
  int priority;
  final List<String> notSupportedModels;
  DateTime? lastUsedAt;
  int usageCount;
  int errorCount;
  DateTime? cooldownUntil;
  String? lastQuotaSnapshot;
  final String tokenRef;
  OAuthTokens tokens;

  bool get isCoolingDown => cooldownUntil != null && cooldownUntil!.isAfter(DateTime.now());

  AccountProfile toProfile() {
    return AccountProfile(
      id: id,
      label: label,
      email: email,
      projectId: projectId,
      enabled: enabled,
      priority: priority,
      notSupportedModels: List<String>.from(notSupportedModels),
      lastUsedAt: lastUsedAt,
      usageCount: usageCount,
      errorCount: errorCount,
      cooldownUntil: cooldownUntil,
      lastQuotaSnapshot: lastQuotaSnapshot,
      tokenRef: tokenRef,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'email': email,
      'project_id': projectId,
      'enabled': enabled,
      'priority': priority,
      'not_supported_models': List<String>.from(notSupportedModels),
      'last_used_at': lastUsedAt?.toIso8601String(),
      'usage_count': usageCount,
      'error_count': errorCount,
      'cooldown_until': cooldownUntil?.toIso8601String(),
      'last_quota_snapshot': lastQuotaSnapshot,
      'token_ref': tokenRef,
      'tokens': tokens.toJson(),
    };
  }

  factory ProxyRuntimeAccount.fromJson(Map<String, Object?> json) {
    return ProxyRuntimeAccount(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      email: json['email'] as String? ?? '',
      projectId: json['project_id'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      priority: json['priority'] as int? ?? 0,
      notSupportedModels:
          ((json['not_supported_models'] as List<dynamic>? ?? const []).cast<String>()).toList(
            growable: true,
          ),
      lastUsedAt: DateTime.tryParse(json['last_used_at'] as String? ?? ''),
      usageCount: json['usage_count'] as int? ?? 0,
      errorCount: json['error_count'] as int? ?? 0,
      cooldownUntil: DateTime.tryParse(json['cooldown_until'] as String? ?? ''),
      lastQuotaSnapshot: json['last_quota_snapshot'] as String?,
      tokenRef: json['token_ref'] as String? ?? '',
      tokens: OAuthTokens.fromJson(
        (json['tokens'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{},
      ),
    );
  }
}

class GeminiAccountPool {
  GeminiAccountPool(this._accounts);

  final List<ProxyRuntimeAccount> _accounts;

  List<ProxyRuntimeAccount> get accounts => _accounts;

  ProxyRuntimeAccount? select(String requestedModel, {Set<String>? excludedIds}) {
    final blockedIds = excludedIds ?? const <String>{};
    final normalizedModel = _normalizeModel(requestedModel);
    final candidates = _accounts
        .where((account) {
          return account.enabled &&
              !blockedIds.contains(account.id) &&
              !account.isCoolingDown &&
              !account.notSupportedModels.map(_normalizeModel).contains(normalizedModel);
        })
        .toList(growable: false);

    if (candidates.isEmpty) {
      return null;
    }

    final highestPriority = candidates
        .map((account) => normalizeAccountPriority(account.priority))
        .reduce((left, right) => left > right ? left : right);
    final tier = candidates
        .where((account) => normalizeAccountPriority(account.priority) == highestPriority)
        .toList();
    tier.sort((left, right) {
      final leftUsed = left.lastUsedAt?.millisecondsSinceEpoch ?? 0;
      final rightUsed = right.lastUsedAt?.millisecondsSinceEpoch ?? 0;
      if (leftUsed != rightUsed) {
        return leftUsed.compareTo(rightUsed);
      }
      if (left.usageCount != right.usageCount) {
        return left.usageCount.compareTo(right.usageCount);
      }
      return left.label.toLowerCase().compareTo(right.label.toLowerCase());
    });
    return tier.first;
  }

  void markUsed(ProxyRuntimeAccount account) {
    account.lastUsedAt = DateTime.now();
    account.usageCount += 1;
  }

  void markQuotaFailure(ProxyRuntimeAccount account, {String? quotaSnapshot, Duration? cooldown}) {
    final effectiveCooldown = cooldown ?? const Duration(minutes: 45);
    account.errorCount += 1;
    account.cooldownUntil = DateTime.now().add(effectiveCooldown);
    account.lastQuotaSnapshot = quotaSnapshot;
  }

  void markAuthFailure(ProxyRuntimeAccount account, {Duration? cooldown}) {
    final effectiveCooldown = cooldown ?? const Duration(days: 30);
    account.errorCount += 1;
    account.cooldownUntil = DateTime.now().add(effectiveCooldown);
  }

  void markCapacityFailure(ProxyRuntimeAccount account, {Duration? cooldown}) {
    final effectiveCooldown = cooldown ?? const Duration(minutes: 3);
    account.errorCount += 1;
    account.cooldownUntil = DateTime.now().add(effectiveCooldown);
  }

  void markUnsupportedModel(ProxyRuntimeAccount account, String model) {
    final normalized = _normalizeModel(model);
    if (!account.notSupportedModels.map(_normalizeModel).contains(normalized)) {
      account.notSupportedModels.add(normalized);
    }
    account.errorCount += 1;
  }

  void reset(ProxyRuntimeAccount account) {
    account.errorCount = 0;
    account.cooldownUntil = null;
    account.lastQuotaSnapshot = null;
  }

  String _normalizeModel(String value) {
    return ModelCatalog.normalizeModel(value);
  }
}
