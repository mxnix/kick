import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/oauth_tokens.dart';

class SecretStore {
  const SecretStore() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _proxyApiKeyKey = 'kick.proxy.api_key';

  Future<String?> readProxyApiKey() => _storage.read(key: _proxyApiKeyKey);

  Future<void> writeProxyApiKey(String apiKey) {
    return _storage.write(key: _proxyApiKeyKey, value: apiKey);
  }

  Future<void> writeOAuthTokens(String tokenRef, OAuthTokens tokens) {
    return _storage.write(key: tokenRef, value: jsonEncode(tokens.toJson()));
  }

  Future<OAuthTokens?> readOAuthTokens(String tokenRef) async {
    final raw = await _storage.read(key: tokenRef);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    return OAuthTokens.fromJson(decoded);
  }

  Future<void> deleteOAuthTokens(String tokenRef) {
    return _storage.delete(key: tokenRef);
  }
}
