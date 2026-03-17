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
        return Isolate.spawn(_readyOnlyIsolate, messagePort, onError: errorPort, onExit: exitPort);
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
    final settings = AppSettings.defaults(
      apiKey: 'expected-key',
    ).copyWith(port: 0, androidBackgroundRuntime: false);

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

  test('ignores repeated start requests while a start is already pending', () async {
    final harness = await _ControllerHarness.create(
      spawnIsolate: (messagePort, errorPort, exitPort) {
        return Isolate.spawn(
          _delayedStartCountingIsolate,
          messagePort,
          onError: errorPort,
          onExit: exitPort,
        );
      },
    );
    addTearDown(harness.dispose);
    final settings = AppSettings.defaults(
      apiKey: 'expected-key',
    ).copyWith(port: 0, androidBackgroundRuntime: false);

    await harness.controller.configure(settings: settings, accounts: const <AccountProfile>[]);

    await harness.controller.start();
    expect(harness.controller.currentState.startPending, isTrue);

    await harness.controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(harness.controller.currentState.running, isTrue);
    expect(harness.controller.currentState.requestCount, 1);
    expect(harness.controller.currentState.startPending, isFalse);
  });

  test('emits compatibility issues and proxy session summaries from isolate analytics', () async {
    final transport = _RecordingAnalyticsTransport();
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
      transport: transport,
      trackingAllowed: true,
    );
    final harness = await _ControllerHarness.create(
      analytics: analytics,
      spawnIsolate: (messagePort, errorPort, exitPort) {
        return Isolate.spawn(
          _analyticsSessionIsolate,
          messagePort,
          onError: errorPort,
          onExit: exitPort,
        );
      },
    );
    addTearDown(harness.dispose);
    final settings = AppSettings.defaults(
      apiKey: 'expected-key',
    ).copyWith(port: 0, androidBackgroundRuntime: false, requestMaxRetries: 7);

    await harness.controller.configure(settings: settings, accounts: const <AccountProfile>[]);
    await harness.controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await harness.controller.stop();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      transport.events.any(
        (event) =>
            event.name == 'upstream_compatibility_issue' &&
            event.properties['issue_kind'] == 'unsupported_model' &&
            event.properties['upstream_reason'] == 'CONSUMER_INVALID' &&
            event.properties['has_action_url'] == 1,
      ),
      isTrue,
    );
    expect(
      transport.events.any(
        (event) =>
            event.name == 'proxy_request_failed' &&
            event.properties['error_detail'] == 'projectConfiguration' &&
            event.properties['retry_after_ms'] == 45000,
      ),
      isTrue,
    );
    expect(
      transport.events.any(
        (event) =>
            event.name == 'proxy_request_retried' &&
            event.properties['upstream_reason'] == 'SERVICE_DISABLED' &&
            event.properties['has_action_url'] == 1,
      ),
      isTrue,
    );
    expect(
      transport.events.any(
        (event) =>
            event.name == 'proxy_session_summary' &&
            event.properties['request_count'] == 3 &&
            event.properties['healthy_accounts'] == 1,
      ),
      isTrue,
    );
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

@pragma('vm:entry-point')
Future<void> _analyticsSessionIsolate(SendPort sendPort) async {
  final commands = ReceivePort();
  sendPort.send({'type': 'ready', 'port': commands.sendPort});
  await for (final message in commands) {
    if (message is! Map) {
      continue;
    }
    switch (message['type']) {
      case 'start':
        final startedAt = DateTime.now().subtract(const Duration(seconds: 3)).toIso8601String();
        sendPort.send({
          'type': 'status',
          'payload': {
            'ready': true,
            'running': true,
            'bound_host': '127.0.0.1',
            'port': 3000,
            'started_at': startedAt,
            'request_count': 0,
            'active_accounts': 2,
            'healthy_accounts': 1,
            'last_error': null,
          },
        });
        sendPort.send({
          'type': 'analytics',
          'payload': {
            'kind': 'proxy_request_succeeded',
            'route': '/v1/responses',
            'model': 'gemini-3-flash',
            'stream': false,
          },
        });
        sendPort.send({
          'type': 'analytics',
          'payload': {
            'kind': 'proxy_request_failed',
            'route': '/v1/responses',
            'model': 'my-private-model-id',
            'stream': true,
            'error_kind': 'unsupportedModel',
            'status_code': 400,
            'error_detail': 'projectConfiguration',
            'upstream_reason': 'SERVICE_DISABLED',
            'retry_after_ms': 45000,
            'has_action_url': true,
          },
        });
        sendPort.send({
          'type': 'analytics',
          'payload': {
            'kind': 'upstream_compatibility_issue',
            'issue_kind': 'unsupported_model',
            'route': '/v1/responses',
            'model': 'my-private-model-id',
            'stream': true,
            'error_kind': 'unsupportedModel',
            'status_code': 400,
            'error_detail': 'projectIdMissing',
            'upstream_reason': 'CONSUMER_INVALID',
            'retry_after_ms': 15000,
            'has_action_url': true,
          },
        });
        sendPort.send({
          'type': 'analytics',
          'payload': {
            'kind': 'proxy_request_retried',
            'route': '/v1/responses',
            'model': 'gemini-3-flash',
            'stream': false,
            'outcome': 'succeeded',
            'retry_count': 2,
            'upstream_retry_count': 1,
            'account_failover_count': 1,
            'error_detail': 'projectConfiguration',
            'upstream_reason': 'SERVICE_DISABLED',
            'retry_after_ms': 45000,
            'has_action_url': true,
          },
        });
        break;
      case 'stop':
        sendPort.send({
          'type': 'status',
          'payload': {
            'ready': true,
            'running': false,
            'bound_host': '127.0.0.1',
            'port': 3000,
            'started_at': DateTime.now().subtract(const Duration(seconds: 3)).toIso8601String(),
            'request_count': 3,
            'active_accounts': 2,
            'healthy_accounts': 1,
            'last_error': null,
          },
        });
        break;
      case 'shutdown':
        commands.close();
        break;
    }
  }
}

@pragma('vm:entry-point')
Future<void> _delayedStartCountingIsolate(SendPort sendPort) async {
  final commands = ReceivePort();
  var startCount = 0;
  sendPort.send({'type': 'ready', 'port': commands.sendPort});
  await for (final message in commands) {
    if (message is! Map) {
      continue;
    }
    switch (message['type']) {
      case 'configure':
        sendPort.send({
          'type': 'status',
          'payload': {
            'ready': true,
            'running': false,
            'bound_host': '127.0.0.1',
            'port': 3000,
            'started_at': null,
            'request_count': startCount,
            'active_accounts': 0,
            'healthy_accounts': 0,
            'last_error': null,
          },
        });
        break;
      case 'start':
        startCount += 1;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        sendPort.send({
          'type': 'status',
          'payload': {
            'ready': true,
            'running': true,
            'bound_host': '127.0.0.1',
            'port': 3000,
            'started_at': DateTime.now().toIso8601String(),
            'request_count': startCount,
            'active_accounts': 0,
            'healthy_accounts': 0,
            'last_error': null,
          },
        });
        break;
      case 'shutdown':
        commands.close();
        break;
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
  _ControllerHarness({required this.database, required this.secretStore, required this.controller});

  final AppDatabase database;
  final SecretStore secretStore;
  final KickProxyController controller;

  static Future<_ControllerHarness> create({
    ProxyIsolateSpawner? spawnIsolate,
    KickAnalytics? analytics,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.ensureSchema();
    final secretStore = SecretStore(backend: _MemorySecretStoreBackend());
    final controller = KickProxyController(
      accountsRepository: AccountsRepository(database),
      analytics:
          analytics ??
          KickAnalytics(
            config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: ''),
            transport: const NoOpAnalyticsTransport(),
          ),
      logsRepository: LogsRepository(database),
      secretStore: secretStore,
      spawnIsolate: spawnIsolate,
    );
    return _ControllerHarness(database: database, secretStore: secretStore, controller: controller);
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

class _RecordingAnalyticsTransport implements AnalyticsTransport {
  final List<_RecordedAnalyticsEvent> events = <_RecordedAnalyticsEvent>[];

  @override
  Future<void> ensureInitialized(AnalyticsBuildConfig config) async {}

  @override
  Future<void> track(String eventName, Map<String, Object?> properties) async {
    events.add(_RecordedAnalyticsEvent(name: eventName, properties: properties));
  }
}

class _RecordedAnalyticsEvent {
  const _RecordedAnalyticsEvent({required this.name, required this.properties});

  final String name;
  final Map<String, Object?> properties;
}
