import 'dart:io';
import 'dart:isolate';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/kick_analytics.dart';
import 'package:kick/data/app_database.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/app_settings.dart';
import 'package:kick/data/models/oauth_tokens.dart';
import 'package:kick/data/repositories/accounts_repository.dart';
import 'package:kick/data/repositories/logs_repository.dart';
import 'package:kick/data/repositories/secret_store.dart';
import 'package:kick/proxy/engine/proxy_controller.dart';

void main() {
  test('initialize can recover after the isolate exits before ready', () async {
    _spawnAttempts = 0;
    final harness = await _ControllerHarness.create(
      spawnIsolate: (messagePort, errorPort, exitPort) {
        _spawnAttempts += 1;
        if (_spawnAttempts == 1) {
          return Isolate.spawn(
            _exitImmediatelyIsolate,
            messagePort,
            onError: errorPort,
            onExit: exitPort,
          );
        }
        return Isolate.spawn(
          _readyOnlyIsolate,
          messagePort,
          onError: errorPort,
          onExit: exitPort,
        );
      },
    );
    addTearDown(harness.dispose);

    await expectLater(
      harness.controller.initialize().timeout(const Duration(seconds: 2)),
      throwsA(isA<StateError>()),
    );

    await harness.controller.initialize().timeout(const Duration(seconds: 2));

    expect(harness.controller.currentState.ready, isTrue);
  });

  test('dispose waits for shutdown messages before tearing down the controller', () async {
    final harness = await _ControllerHarness.create(
      spawnIsolate: (messagePort, errorPort, exitPort) {
        return Isolate.spawn(
          _flushTokenOnShutdownIsolate,
          messagePort,
          onError: errorPort,
          onExit: exitPort,
        );
      },
    );

    await harness.controller.initialize();
    await harness.controller.dispose();

    final tokens = await harness.secretStore.readOAuthTokens('shutdown.token');
    expect(tokens?.accessToken, 'disposed-token');
    await harness.database.close();
  });

  test('unauthorized client errors do not overwrite the runtime error state', () async {
    final harness = await _ControllerHarness.create();
    addTearDown(harness.dispose);
    final settings = AppSettings.defaults(apiKey: 'expected-key').copyWith(
      port: 0,
      androidBackgroundRuntime: false,
    );

    await harness.controller.configure(settings: settings, accounts: const <AccountProfile>[]);
    final runningState = harness.controller.states.firstWhere((state) => state.running);

    await harness.controller.start();
    final state = await runningState.timeout(const Duration(seconds: 2));

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(Uri.http('127.0.0.1:${state.port}', '/v1/models'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer wrong-key');
    final response = await request.close();
    await response.drain();

    expect(response.statusCode, HttpStatus.unauthorized);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(harness.controller.currentState.lastError, isNull);
  });
}

int _spawnAttempts = 0;

@pragma('vm:entry-point')
void _exitImmediatelyIsolate(SendPort _) {}

@pragma('vm:entry-point')
Future<void> _readyOnlyIsolate(SendPort sendPort) async {
  final commands = ReceivePort();
  sendPort.send({'type': 'ready', 'port': commands.sendPort});
  await for (final message in commands) {
    if (message is Map && message['type'] == 'shutdown') {
      commands.close();
    }
  }
}

@pragma('vm:entry-point')
Future<void> _flushTokenOnShutdownIsolate(SendPort sendPort) async {
  final commands = ReceivePort();
  sendPort.send({'type': 'ready', 'port': commands.sendPort});
  await for (final message in commands) {
    if (message is! Map) {
      continue;
    }
    if (message['type'] == 'shutdown') {
      sendPort.send({
        'type': 'token_updated',
        'payload': {
          'token_ref': 'shutdown.token',
          'tokens': _sampleTokens('disposed-token').toJson(),
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 25));
      commands.close();
    }
  }
}

OAuthTokens _sampleTokens(String accessToken) {
  return OAuthTokens(
    accessToken: accessToken,
    refreshToken: 'refresh-token',
    expiry: DateTime.now().add(const Duration(hours: 1)),
    tokenType: 'Bearer',
    scope: null,
  );
}

class _ControllerHarness {
  _ControllerHarness({
    required this.database,
    required this.secretStore,
    required this.controller,
  });

  final AppDatabase database;
  final SecretStore secretStore;
  final KickProxyController controller;

  static Future<_ControllerHarness> create({
    ProxyIsolateSpawner? spawnIsolate,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.ensureSchema();
    final secretStore = SecretStore(backend: _MemorySecretStoreBackend());
    final controller = KickProxyController(
      accountsRepository: AccountsRepository(database),
      analytics: KickAnalytics(
        config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: ''),
        transport: const NoOpAnalyticsTransport(),
      ),
      logsRepository: LogsRepository(database),
      secretStore: secretStore,
      spawnIsolate: spawnIsolate,
    );
    return _ControllerHarness(
      database: database,
      secretStore: secretStore,
      controller: controller,
    );
  }

  Future<void> dispose() async {
    await controller.dispose();
    await database.close();
  }
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
