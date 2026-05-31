import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kick/data/repositories/secret_store.dart';
import 'package:kick/proxy/luma/luma_realm_client.dart';
import 'package:kick/proxy/luma/luma_session.dart';
import 'package:kick/proxy/luma/luma_session_source.dart';

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
  group('sessionFromRawCookieHeader', () {
    test('keeps only Luma-recognized cookies', () {
      final session = sessionFromRawCookieHeader(
        '_fbp=fb.123; wos-session=opaque; _ga=GA1.2; '
        'workos-access-token=jwt; user-logged-in=true; __recent_auth=1; junk=ignored',
        email: 'tester@example.com',
      );
      expect(session.cookies.keys, containsAll(<String>['wos-session', 'workos-access-token']));
      expect(session.cookies, isNot(contains('_fbp')));
      expect(session.cookies, isNot(contains('_ga')));
      expect(session.email, 'tester@example.com');
    });

    test('accepts a full Cookie header prefix', () {
      final session = sessionFromRawCookieHeader(
        'Cookie: wos-session=opaque; workos-access-token=jwt',
      );

      expect(session.cookies['wos-session'], 'opaque');
      expect(session.cookies['workos-access-token'], 'jwt');
    });

    test('throws when wos-session is missing', () {
      expect(
        () => sessionFromRawCookieHeader('_fbp=fb.123; access-token=blob'),
        throwsFormatException,
      );
    });
  });

  group('LumaSessionSource', () {
    test('hydrates from secret store and round-trips a save', () async {
      final backend = _InMemoryBackend();
      final store = SecretStore(backend: backend);
      final source = LumaSessionSource(
        secretStore: store,
        tokenRef: 'kick.luma.test',
        client: LumaRealmClient(httpClient: MockClient((_) async => http.Response('{}', 200))),
      );

      expect(await source.read(), isNull);

      const written = LumaSession(cookies: {'wos-session': 'cookie'}, email: 'tester@example.com');
      await source.save(written);

      expect(await source.read(), isNotNull);
      expect((await source.read())!.email, 'tester@example.com');

      await source.delete();
      expect(await source.read(), isNull);

      source.close();
    });

    test('ensureTeamAndRealm reuses an existing realm named KiCk', () async {
      var teamsCalls = 0;
      var realmsCalls = 0;
      var createCalls = 0;
      final client = LumaRealmClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/vespa/teams') {
            teamsCalls += 1;
            return http.Response(
              jsonEncode({
                'accepted': [
                  {
                    'team': {'id': 'team-1', 'name': 'My Team'},
                    'membership': {
                      'user': {'uuid': 'user-1', 'email': 'tester@example.com'},
                      'role': 'owner',
                    },
                    'subscription': {'tier': 'free'},
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/api/vespa/teams/team-1/realms' && request.method == 'GET') {
            realmsCalls += 1;
            return http.Response(
              jsonEncode([
                {'id': 'realm-existing', 'name': 'KiCk'},
              ]),
              200,
            );
          }
          if (request.url.path == '/api/vespa/teams/team-1/realms' && request.method == 'POST') {
            createCalls += 1;
            return http.Response(jsonEncode({'id': 'realm-new', 'name': 'KiCk'}), 200);
          }
          return http.Response('not found', 404);
        }),
      );
      final source = LumaSessionSource(
        secretStore: SecretStore(backend: _InMemoryBackend()),
        tokenRef: 'kick.luma.test',
        client: client,
      );

      const session = LumaSession(cookies: {'wos-session': 'cookie'});
      final resolved = await source.ensureTeamAndRealm(session);

      expect(resolved.teamId, 'team-1');
      expect(resolved.realmId, 'realm-existing');
      expect(resolved.email, 'tester@example.com');
      expect(teamsCalls, 1);
      expect(realmsCalls, 1);
      expect(createCalls, 0);

      source.close();
    });

    test('ensureTeamAndRealm creates a new realm when none match', () async {
      final client = LumaRealmClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/vespa/teams') {
            return http.Response(
              jsonEncode({
                'accepted': [
                  {
                    'team': {'id': 'team-1', 'name': 'My Team'},
                    'membership': {
                      'user': {'uuid': 'user-1', 'email': 't@example.com'},
                      'role': 'owner',
                    },
                    'subscription': {'tier': 'free'},
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/api/vespa/teams/team-1/realms' && request.method == 'GET') {
            return http.Response(jsonEncode(<Object?>[]), 200);
          }
          if (request.url.path == '/api/vespa/teams/team-1/realms' && request.method == 'POST') {
            return http.Response(jsonEncode({'id': 'realm-fresh', 'name': 'KiCk'}), 200);
          }
          return http.Response('not found', 404);
        }),
      );
      final source = LumaSessionSource(
        secretStore: SecretStore(backend: _InMemoryBackend()),
        tokenRef: 'kick.luma.test',
        client: client,
      );

      const session = LumaSession(cookies: {'wos-session': 'cookie'});
      final resolved = await source.ensureTeamAndRealm(session);

      expect(resolved.realmId, 'realm-fresh');
      source.close();
    });
  });
}
