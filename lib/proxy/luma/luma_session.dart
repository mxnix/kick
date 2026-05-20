import 'dart:convert';

/// Long-lived Luma session material captured after a successful WorkOS sign-in.
///
/// Lumalabs deliberately stays first-party only: every `/api/vespa/*` request
/// is authenticated by the `wos-session` cookie issued by `auth.lumalabs.ai`.
/// We persist the relevant cookies so the proxy isolate can rebuild the
/// `Cookie` header without touching the OS cookie jar.
class LumaSession {
  const LumaSession({
    required this.cookies,
    this.userId,
    this.email,
    this.teamId,
    this.realmId,
    this.expiresAt,
  });

  factory LumaSession.fromJson(Map<String, Object?> json) {
    final rawCookies = json['cookies'];
    final cookies = <String, String>{};
    if (rawCookies is Map) {
      rawCookies.forEach((key, value) {
        if (key is String && value is String) {
          cookies[key] = value;
        }
      });
    }
    final expires = (json['expires_at'] as String?)?.trim();
    return LumaSession(
      cookies: Map<String, String>.unmodifiable(cookies),
      userId: (json['user_id'] as String?)?.trim().isNotEmpty == true
          ? (json['user_id'] as String).trim()
          : null,
      email: (json['email'] as String?)?.trim().isNotEmpty == true
          ? (json['email'] as String).trim()
          : null,
      teamId: (json['team_id'] as String?)?.trim().isNotEmpty == true
          ? (json['team_id'] as String).trim()
          : null,
      realmId: (json['realm_id'] as String?)?.trim().isNotEmpty == true
          ? (json['realm_id'] as String).trim()
          : null,
      expiresAt: expires == null || expires.isEmpty ? null : DateTime.tryParse(expires),
    );
  }

  /// Cookie jar keyed by name. We intentionally store only the names the Luma
  /// app actually relies on (everything else is analytics noise).
  final Map<String, String> cookies;

  /// User UUID returned by `/api/vespa/me`-style endpoints. Optional.
  final String? userId;

  /// Email captured at sign-in (used as default account label/identity).
  final String? email;

  /// Team selected for this account. We pin a single team per account.
  final String? teamId;

  /// Realm selected for this account. Created on first use as `KiCk` if absent.
  final String? realmId;

  /// Best-effort expiry of the underlying `wos-session` cookie. We treat the
  /// session as expired once `expiresAt` is in the past or after a 401 on the
  /// vespa surface.
  final DateTime? expiresAt;

  bool get hasSession => cookies.isNotEmpty && cookies.containsKey('wos-session');

  bool get isExpired {
    final at = expiresAt;
    return at != null && at.isBefore(DateTime.now());
  }

  String buildCookieHeader() {
    if (cookies.isEmpty) {
      return '';
    }
    final pieces = <String>[];
    cookies.forEach((name, value) {
      if (name.isEmpty || value.isEmpty) {
        return;
      }
      pieces.add('$name=$value');
    });
    return pieces.join('; ');
  }

  LumaSession copyWith({
    Map<String, String>? cookies,
    String? userId,
    String? email,
    String? teamId,
    String? realmId,
    DateTime? expiresAt,
    bool clearTeamId = false,
    bool clearRealmId = false,
    bool clearExpiresAt = false,
  }) {
    return LumaSession(
      cookies: cookies == null
          ? this.cookies
          : Map<String, String>.unmodifiable(Map<String, String>.from(cookies)),
      userId: userId ?? this.userId,
      email: email ?? this.email,
      teamId: clearTeamId ? null : (teamId ?? this.teamId),
      realmId: clearRealmId ? null : (realmId ?? this.realmId),
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'cookies': cookies,
      if (userId != null) 'user_id': userId,
      if (email != null) 'email': email,
      if (teamId != null) 'team_id': teamId,
      if (realmId != null) 'realm_id': realmId,
      if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
    };
  }

  String encode() => jsonEncode(toJson());

  static LumaSession? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map) {
        return null;
      }
      return LumaSession.fromJson(json.cast<String, Object?>());
    } on FormatException {
      return null;
    }
  }
}

/// Cookie names the Luma BFF reads to identify the session. Anything else is
/// safe to drop when persisting the session.
const Set<String> lumaSessionCookieNames = {
  'wos-session',
  'workos-access-token',
  'access-token',
  'session',
  'user-logged-in',
  '__recent_auth',
};

/// Domain prefix for Luma API hosts. Used by the http client to filter cookies.
const String lumaPrimaryHost = 'app.lumalabs.ai';
const String lumaAuthHost = 'auth.lumalabs.ai';
const String lumaAuthApiHost = 'auth.api.lumalabs.ai';
