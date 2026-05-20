import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/repositories/secret_store.dart';
import 'package:kick/proxy/luma/luma_realm_client.dart';
import 'package:kick/proxy/luma/luma_session.dart';
import 'package:kick/proxy/luma/luma_usage_service.dart';

class _InMemoryBackend implements SecretStoreBackend {
  final Map<String, String> _store = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }
}

void main() {
  test('fetchUsage returns a credit bucket when team usage payload is healthy', () async {
    final backend = _InMemoryBackend();
    final store = SecretStore(backend: backend);
    const session = LumaSession(
      cookies: {'wos-session': 'cookie-blob'},
      teamId: 'team-1',
      realmId: 'realm-1',
      email: 'tester@example.com',
    );
    await store.writeLumaSession('kick.luma.test', session.encode());

    final realmClient = LumaRealmClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/vespa/teams/team-1/usage');
        return http.Response(
          jsonEncode({
            'team_id': 'team-1',
            'tier': 'free',
            'is_trial': true,
            'current_usage': 53,
            'usage_limit': 3000,
            'subscription_end': '2026-06-17T21:04:20Z',
          }),
          200,
        );
      }),
    );

    final service = LumaUsageService(secretStore: store, client: realmClient);
    final account = const AccountProfile(
      id: 'acc-1',
      label: 'Tester',
      email: 'tester@example.com',
      projectId: '',
      provider: AccountProvider.luma,
      enabled: true,
      priority: 1,
      notSupportedModels: <String>[],
      runtimeNotSupportedModels: <String>[],
      lastUsedAt: null,
      usageCount: 0,
      errorCount: 0,
      cooldownUntil: null,
      lastQuotaSnapshot: null,
      tokenRef: 'kick.luma.test',
    );

    final snapshot = await service.fetchUsage(account);
    expect(snapshot.subscriptionTitle, contains('Trial'));
    expect(snapshot.buckets, hasLength(1));
    final bucket = snapshot.buckets.single;
    expect(bucket.modelId, 'CREDIT');
    expect(bucket.tokenType, 'CREDITS');
    expect(bucket.currentUsage, 53);
    expect(bucket.usageLimit, 3000);
    expect(bucket.remainingFraction, closeTo((3000 - 53) / 3000, 1e-9));
    expect(snapshot.resolvedEmail, 'tester@example.com');
    service.dispose();
  });

  test('fetchUsage falls back gracefully when no session is stored', () async {
    final service = LumaUsageService(
      secretStore: SecretStore(backend: _InMemoryBackend()),
      client: LumaRealmClient(httpClient: MockClient((_) async => http.Response('{}', 200))),
    );
    final account = const AccountProfile(
      id: 'acc-2',
      label: 'Tester',
      email: '',
      projectId: '',
      provider: AccountProvider.luma,
      enabled: true,
      priority: 1,
      notSupportedModels: <String>[],
      runtimeNotSupportedModels: <String>[],
      lastUsedAt: null,
      usageCount: 0,
      errorCount: 0,
      cooldownUntil: null,
      lastQuotaSnapshot: null,
      tokenRef: 'kick.luma.missing',
    );

    final snapshot = await service.fetchUsage(account);
    expect(snapshot.buckets, isEmpty);
    expect(snapshot.subscriptionTitle, contains('not connected'));
    service.dispose();
  });
}
