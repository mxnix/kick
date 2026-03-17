import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/oauth_tokens.dart';

abstract interface class SecretStoreBackend {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureStorageBackend implements SecretStoreBackend {
  const FlutterSecureStorageBackend({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SecretStore {
  const SecretStore({
    SecretStoreBackend backend = const FlutterSecureStorageBackend(),
  }) : _backend = backend;

  final SecretStoreBackend _backend;

  static const _proxyApiKeyKey = 'kick.proxy.api_key';

  Future<String?> readProxyApiKey() => _backend.read(_proxyApiKeyKey);

  Future<void> writeProxyApiKey(String apiKey) {
    return _backend.write(_proxyApiKeyKey, apiKey);
  }

  Future<void> writeOAuthTokens(String tokenRef, OAuthTokens tokens) {
    return _backend.write(tokenRef, jsonEncode(tokens.toJson()));
  }

  Future<OAuthTokens?> readOAuthTokens(String tokenRef) async {
    final raw = await _backend.read(tokenRef);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return OAuthTokens.fromJson(decoded.cast<String, Object?>());
    } on FormatException {
      return null;
    }
  }

  Future<void> deleteOAuthTokens(String tokenRef) {
    return _backend.delete(tokenRef);
  }
}
