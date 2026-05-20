import 'dart:async';

import '../../data/repositories/secret_store.dart';
import 'luma_realm_client.dart';
import 'luma_realm_models.dart';
import 'luma_session.dart';

/// Persistent owner of a [LumaSession]. Reads/writes the encrypted blob from
/// [SecretStore], lazily resolves a default team and realm, and exposes a
/// single async-safe accessor to the rest of the code.
class LumaSessionSource {
  LumaSessionSource({
    required SecretStore secretStore,
    required this.tokenRef,
    LumaRealmClient? client,
  }) : _secretStore = secretStore,
       _client = client ?? LumaRealmClient();

  final SecretStore _secretStore;
  final LumaRealmClient _client;

  final String tokenRef;

  Future<LumaSession?>? _pending;
  LumaSession? _cached;

  /// Returns the latest known session or `null` when no session is stored.
  /// The first call hydrates from the secret store; subsequent calls hit the
  /// in-memory cache.
  Future<LumaSession?> read() {
    if (_cached != null) {
      return Future.value(_cached);
    }
    return _pending ??= _loadFromStore();
  }

  Future<LumaSession?> _loadFromStore() async {
    final raw = await _secretStore.readLumaSession(tokenRef);
    final decoded = LumaSession.tryDecode(raw);
    _cached = decoded;
    _pending = null;
    return decoded;
  }

  Future<void> save(LumaSession session) async {
    await _secretStore.writeLumaSession(tokenRef, session.encode());
    _cached = session;
    _pending = null;
  }

  Future<void> delete() async {
    await _secretStore.deleteLumaSession(tokenRef);
    _cached = null;
    _pending = null;
  }

  /// Resolves a usable team + realm pair for [session].
  ///
  /// - If both are already pinned in the session, returns them as-is.
  /// - Otherwise falls back to the first accepted team and reuses an existing
  ///   realm whose name matches [preferredRealmName]; creates one when no
  ///   match is found.
  ///
  /// Returns the resolved session (may equal the input). Callers are
  /// responsible for persisting the returned session via [save].
  Future<LumaSession> ensureTeamAndRealm(
    LumaSession session, {
    String preferredRealmName = 'KiCk',
  }) async {
    var current = session;

    if (current.teamId == null || current.teamId!.isEmpty) {
      final team = await _client.readPrimaryTeam(current);
      if (team == null) {
        throw StateError(
          'No team is associated with this Luma session. Sign in to lumalabs.ai first.',
        );
      }
      current = current.copyWith(
        teamId: team.teamId,
        email: current.email ?? team.userEmail,
        userId: current.userId ?? team.userId,
      );
    }

    if (current.realmId == null || current.realmId!.isEmpty) {
      final teamId = current.teamId!;
      final realms = await _client.listRealms(current, teamId);
      LumaRealmRef? selected;
      final preferred = preferredRealmName.trim();
      if (preferred.isNotEmpty) {
        for (final realm in realms) {
          if (realm.name.trim() == preferred) {
            selected = realm;
            break;
          }
        }
      }
      selected ??= realms.isEmpty ? null : realms.first;
      selected ??= await _client.createRealm(
        current,
        teamId: teamId,
        name: preferred.isNotEmpty ? preferred : 'KiCk',
      );
      current = current.copyWith(realmId: selected.id);
    }

    return current;
  }

  void close() {
    _client.close();
  }
}

/// Convenience factory: takes a raw cookie header string (as copied from the
/// browser DevTools `cookie:` row), strips analytics-only entries, and returns
/// a fresh [LumaSession] keyed by [lumaSessionCookieNames].
LumaSession sessionFromRawCookieHeader(
  String rawCookieHeader, {
  Set<String> requiredCookies = const {'wos-session'},
  String? email,
}) {
  final cookies = <String, String>{};
  for (final piece in rawCookieHeader.split(';')) {
    final trimmed = piece.trim();
    if (trimmed.isEmpty) continue;
    final eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    final name = trimmed.substring(0, eq).trim();
    final value = trimmed.substring(eq + 1).trim();
    if (name.isEmpty || value.isEmpty) continue;
    if (!lumaSessionCookieNames.contains(name)) continue;
    cookies[name] = value;
  }
  for (final required in requiredCookies) {
    if (!cookies.containsKey(required)) {
      throw FormatException('Cookie header is missing the required `$required` entry.');
    }
  }
  return LumaSession(cookies: Map<String, String>.unmodifiable(cookies), email: email);
}
