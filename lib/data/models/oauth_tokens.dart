class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiry,
    required this.tokenType,
    required this.scope,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiry;
  final String tokenType;
  final String? scope;

  bool get isExpired => expiry.isBefore(DateTime.now().add(const Duration(minutes: 1)));

  OAuthTokens copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiry,
    String? tokenType,
    String? scope,
  }) {
    return OAuthTokens(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiry: expiry ?? this.expiry,
      tokenType: tokenType ?? this.tokenType,
      scope: scope ?? this.scope,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expiry': expiry.toIso8601String(),
      'token_type': tokenType,
      'scope': scope,
    };
  }

  factory OAuthTokens.fromJson(Map<String, Object?> json) {
    return OAuthTokens(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      expiry:
          DateTime.tryParse(json['expiry'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      tokenType: json['token_type'] as String? ?? 'Bearer',
      scope: json['scope'] as String?,
    );
  }
}
