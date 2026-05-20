import 'dart:async';

import '../../data/models/account_profile.dart';
import '../../data/repositories/secret_store.dart';
import '../gemini/gemini_code_assist_client.dart' show GeminiGatewayException;
import 'luma_realm_client.dart';
import 'luma_session.dart';
import 'luma_session_source.dart';

/// Result of a successful Luma sign-in attempt.
class LumaConnectResult {
  const LumaConnectResult({
    required this.session,
    required this.email,
    required this.label,
    required this.tokenRef,
    this.tier,
  });

  final LumaSession session;
  final String email;
  final String label;
  final String tokenRef;

  /// Subscription tier the team belongs to, e.g. `free`/`paid`. Optional.
  final String? tier;
}

/// Errors specific to the Luma connect flow. Mapped to user-facing copy in
/// the UI layer.
class LumaConnectException implements Exception {
  const LumaConnectException(this.code, [this.cause]);

  final LumaConnectErrorCode code;
  final Object? cause;

  @override
  String toString() => 'LumaConnectException($code, $cause)';
}

enum LumaConnectErrorCode {
  invalidCookieHeader,
  missingRequiredCookie,
  unauthorized,
  networkFailure,
  noTeamsAvailable,
  unknown,
}

/// Validates a raw cookie blob, persists the resulting session, and resolves
/// the default team + realm. Throws [LumaConnectException] on failure.
class LumaConnectService {
  LumaConnectService({
    required SecretStore secretStore,
    LumaRealmClient? client,
    String preferredRealmName = 'KiCk',
  }) : _secretStore = secretStore,
       _client = client ?? LumaRealmClient(),
       _preferredRealmName = preferredRealmName;

  final SecretStore _secretStore;
  final LumaRealmClient _client;
  final String _preferredRealmName;

  Future<LumaConnectResult> connectWithRawCookies({
    required String tokenRef,
    required String rawCookieHeader,
    String? labelOverride,
  }) async {
    LumaSession session;
    try {
      session = sessionFromRawCookieHeader(rawCookieHeader);
    } on FormatException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('wos-session')) {
        throw const LumaConnectException(LumaConnectErrorCode.missingRequiredCookie);
      }
      throw LumaConnectException(LumaConnectErrorCode.invalidCookieHeader, error);
    } catch (error) {
      throw LumaConnectException(LumaConnectErrorCode.invalidCookieHeader, error);
    }

    final source = LumaSessionSource(
      secretStore: _secretStore,
      tokenRef: tokenRef,
      client: _client,
    );

    try {
      // Fetch teams first so we surface auth/network failures with clear copy.
      final team = await _client.readPrimaryTeam(session);
      if (team == null) {
        throw const LumaConnectException(LumaConnectErrorCode.noTeamsAvailable);
      }
      session = session.copyWith(
        teamId: team.teamId,
        userId: session.userId ?? team.userId,
        email: session.email ?? team.userEmail,
      );

      final resolved = await source.ensureTeamAndRealm(
        session,
        preferredRealmName: _preferredRealmName,
      );
      await source.save(resolved);

      final email = (resolved.email ?? team.userEmail ?? '').trim();
      final tier = team.tier.trim().isNotEmpty ? team.tier.trim() : null;
      final label =
          (labelOverride?.trim().isNotEmpty == true
                  ? labelOverride!.trim()
                  : email.isNotEmpty
                  ? email
                  : team.teamName)
              .trim();
      return LumaConnectResult(
        session: resolved,
        email: email,
        label: label.isEmpty ? 'Luma' : label,
        tokenRef: tokenRef,
        tier: tier,
      );
    } on LumaConnectException {
      rethrow;
    } on GeminiGatewayException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        throw LumaConnectException(LumaConnectErrorCode.unauthorized, error);
      }
      throw LumaConnectException(LumaConnectErrorCode.networkFailure, error);
    } catch (error) {
      throw LumaConnectException(LumaConnectErrorCode.unknown, error);
    } finally {
      source.close();
    }
  }

  /// Returns the cached or freshly-loaded session for [tokenRef]. The caller
  /// is responsible for keeping the session reference alive across calls.
  Future<LumaSession?> readStoredSession(String tokenRef) async {
    final source = LumaSessionSource(
      secretStore: _secretStore,
      tokenRef: tokenRef,
      client: _client,
    );
    try {
      return await source.read();
    } finally {
      source.close();
    }
  }

  /// Wipes the persisted session for [tokenRef].
  Future<void> deleteSession(String tokenRef) async {
    final source = LumaSessionSource(
      secretStore: _secretStore,
      tokenRef: tokenRef,
      client: _client,
    );
    try {
      await source.delete();
    } finally {
      source.close();
    }
  }
}

/// Returns the [AccountProvider] this service serves. Used by callers that
/// log/track per-provider analytics.
AccountProvider get lumaAccountProvider => AccountProvider.luma;
