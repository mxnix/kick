import 'dart:async';

import '../../data/models/account_profile.dart';
import '../../data/repositories/secret_store.dart';
import '../gemini/gemini_code_assist_client.dart' show GeminiGatewayException;
import '../gemini/gemini_usage_models.dart';
import 'luma_realm_client.dart';
import 'luma_session.dart';

/// Pulls credit usage from the Luma vespa surface and converts it into the
/// shape the rest of the app expects.
///
/// The endpoint we hit is `GET /api/vespa/teams/{team_id}/usage`. Sample
/// payloads live under `.tmp/luma/full/GET___api__vespa__teams___uuid___usage.json`.
class LumaUsageService {
  LumaUsageService({SecretStore? secretStore, LumaRealmClient? client})
    : _secretStore = secretStore,
      _client = client ?? LumaRealmClient();

  final SecretStore? _secretStore;
  final LumaRealmClient _client;

  Future<GeminiUsageSnapshot> fetchUsage(AccountProfile account) async {
    final session = await _resolveSession(account);
    if (session == null) {
      return _fallbackSnapshot(account, 'Luma · not connected');
    }

    final teamId = session.teamId;
    if (teamId == null || teamId.isEmpty) {
      return _fallbackSnapshot(account, 'Luma · no team');
    }

    try {
      final json = await _client.readTeamUsage(session, teamId);
      return _snapshotFromJson(account, session, json);
    } on GeminiGatewayException catch (error) {
      // Surface a snapshot with the error wrapped in subscription title so
      // the UI can render the "limits unavailable" state without throwing.
      return _fallbackSnapshot(account, 'Luma · ${error.statusCode}');
    } catch (_) {
      return _fallbackSnapshot(account, 'Luma');
    }
  }

  Future<LumaSession?> _resolveSession(AccountProfile account) async {
    final secretStore = _secretStore;
    if (secretStore == null) {
      return null;
    }
    try {
      final raw = await secretStore.readLumaSession(account.tokenRef);
      return LumaSession.tryDecode(raw);
    } catch (_) {
      return null;
    }
  }

  GeminiUsageSnapshot _fallbackSnapshot(AccountProfile account, String title) {
    return GeminiUsageSnapshot(
      fetchedAt: DateTime.now(),
      subscriptionTitle: title,
      buckets: const <GeminiUsageBucket>[],
      resolvedEmail: account.email.trim().isEmpty ? null : account.email.trim(),
    );
  }

  GeminiUsageSnapshot _snapshotFromJson(
    AccountProfile account,
    LumaSession session,
    Map<String, Object?> json,
  ) {
    final tier = (json['tier'] as String?)?.trim() ?? '';
    final isTrial = json['is_trial'] == true;
    final subscriptionTitle = _formatSubscriptionTitle(tier: tier, isTrial: isTrial);

    final currentUsage = _readDouble(json['current_usage']);
    final usageLimit = _readDouble(json['usage_limit']);
    final resetAt =
        _parseUtcDateTime(json['credits_refill_at']) ?? _parseUtcDateTime(json['subscription_end']);

    final buckets = <GeminiUsageBucket>[];
    if (currentUsage != null || usageLimit != null) {
      buckets.add(
        GeminiUsageBucket(
          modelId: 'CREDIT',
          remainingFraction: _remainingFraction(currentUsage, usageLimit),
          resetAt: resetAt,
          tokenType: 'CREDITS',
          currentUsage: currentUsage,
          usageLimit: usageLimit,
          unit: 'credits',
        ),
      );
    }

    final email = (session.email ?? account.email).trim();
    return GeminiUsageSnapshot(
      fetchedAt: DateTime.now(),
      subscriptionTitle: subscriptionTitle,
      buckets: List<GeminiUsageBucket>.unmodifiable(buckets),
      resolvedEmail: email.isEmpty ? null : email,
    );
  }

  String _formatSubscriptionTitle({required String tier, required bool isTrial}) {
    if (tier.isEmpty) {
      return isTrial ? 'Luma Trial' : 'Luma';
    }
    final pretty = _capitalize(tier);
    if (isTrial && !pretty.toLowerCase().contains('trial')) {
      return 'Luma · $pretty Trial';
    }
    return 'Luma · $pretty';
  }

  String _capitalize(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }

  double _remainingFraction(double? current, double? limit) {
    if (current == null || limit == null || limit <= 0) {
      return 0;
    }
    return ((limit - current) / limit).clamp(0, 1).toDouble();
  }

  double? _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  DateTime? _parseUtcDateTime(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return DateTime.tryParse(trimmed)?.toLocal();
  }

  void dispose() {
    _client.close();
  }
}
