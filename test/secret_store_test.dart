import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/models/oauth_tokens.dart';
import 'package:kick/data/repositories/secret_store.dart';

void main() {
  test('returns null for invalid OAuth token JSON payloads', () async {
    final backend = _MemorySecretStoreBackend()
      ..values['token.invalid'] = '{"access_token":';
    final store = SecretStore(backend: backend);

    final tokens = await store.readOAuthTokens('token.invalid');

    expect(tokens, isNull);
  });

  test('round-trips OAuth tokens through the configurable backend', () async {
    final backend = _MemorySecretStoreBackend();
    final store = SecretStore(backend: backend);
    final tokens = OAuthTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiry: DateTime.utc(2030, 1, 1),
      tokenType: 'Bearer',
      scope: 'scope',
    );

    await store.writeOAuthTokens('token.valid', tokens);

    final decoded = await store.readOAuthTokens('token.valid');

    expect(decoded?.accessToken, 'access-token');
    expect(decoded?.refreshToken, 'refresh-token');
    expect(decoded?.tokenType, 'Bearer');
    expect(decoded?.scope, 'scope');
  });
}

class _MemorySecretStoreBackend implements SecretStoreBackend {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
