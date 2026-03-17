import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../../analytics/kick_analytics.dart';
import '../../core/platform/android_foreground_runtime.dart';
import '../../data/models/account_profile.dart';
import '../../data/models/app_log_entry.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/oauth_tokens.dart';
import '../../data/repositories/accounts_repository.dart';
import '../../data/repositories/logs_repository.dart';
import '../../data/repositories/secret_store.dart';
import '../engine/proxy_isolate.dart';

typedef ProxyIsolateSpawner =
    Future<Isolate> Function(SendPort messagePort, SendPort errorPort, SendPort exitPort);

class ProxyRuntimeState {
  const ProxyRuntimeState({
    required this.ready,
    required this.running,
    required this.boundHost,
    required this.port,
    required this.startedAt,
    required this.requestCount,
    required this.activeAccounts,
    required this.lastError,
  });

  factory ProxyRuntimeState.initial() {
    return const ProxyRuntimeState(
      ready: false,
      running: false,
      boundHost: '127.0.0.1',
      port: 3000,
      startedAt: null,
      requestCount: 0,
      activeAccounts: 0,
      lastError: null,
    );
  }

  final bool ready;
  final bool running;
  final String boundHost;
  final int port;
  final DateTime? startedAt;
  final int requestCount;
  final int activeAccounts;
  final String? lastError;

  Duration? get uptime => startedAt == null ? null : DateTime.now().difference(startedAt!);

  ProxyRuntimeState copyWith({
    bool? ready,
    bool? running,
    String? boundHost,
    int? port,
    DateTime? startedAt,
    bool clearStartedAt = false,
    int? requestCount,
    int? activeAccounts,
    String? lastError,
    bool clearLastError = false,
  }) {
    return ProxyRuntimeState(
      ready: ready ?? this.ready,
      running: running ?? this.running,
      boundHost: boundHost ?? this.boundHost,
      port: port ?? this.port,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      requestCount: requestCount ?? this.requestCount,
      activeAccounts: activeAccounts ?? this.activeAccounts,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  factory ProxyRuntimeState.fromJson(Map<String, Object?> json) {
    return ProxyRuntimeState(
      ready: json['ready'] as bool? ?? false,
      running: json['running'] as bool? ?? false,
      boundHost: json['bound_host'] as String? ?? '127.0.0.1',
      port: json['port'] as int? ?? 3000,
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? ''),
      requestCount: json['request_count'] as int? ?? 0,
      activeAccounts: json['active_accounts'] as int? ?? 0,
      lastError: json['last_error'] as String?,
    );
  }
}

class KickProxyController {
  KickProxyController({
    required AccountsRepository accountsRepository,
    required KickAnalytics analytics,
    required LogsRepository logsRepository,
    required SecretStore secretStore,
    ProxyIsolateSpawner? spawnIsolate,
  }) : _accountsRepository = accountsRepository,
        _analytics = analytics,
        _logsRepository = logsRepository,
        _secretStore = secretStore,
        _spawnIsolate = spawnIsolate ?? _defaultSpawnIsolate;

  final AccountsRepository _accountsRepository;
  final KickAnalytics _analytics;
  final LogsRepository _logsRepository;
  final SecretStore _secretStore;
  final ProxyIsolateSpawner _spawnIsolate;

  final _states = StreamController<ProxyRuntimeState>.broadcast();
  final _activity = StreamController<String>.broadcast();
  ProxyRuntimeState _currentState = ProxyRuntimeState.initial();
  ProxyRuntimeState get currentState => _currentState;
  Stream<ProxyRuntimeState> get states => _states.stream;
  Stream<String> get activity => _activity.stream;

  ReceivePort? _receivePort;
  ReceivePort? _errorPort;
  ReceivePort? _exitPort;
  StreamSubscription<dynamic>? _receiveSubscription;
  StreamSubscription<dynamic>? _errorSubscription;
  StreamSubscription<dynamic>? _exitSubscription;
  SendPort? _commandPort;
  Isolate? _isolate;
  Completer<void>? _readyCompleter;
  Completer<void>? _shutdownCompleter;
  String? _lastSignature;
  AppSettings? _lastSettings;
  List<AccountProfile> _lastAccounts = const [];
  String? _pendingIsolateFailure;
  bool _awaitingStartResult = false;
  bool _disposing = false;
  bool _disposed = false;

  Future<void> initialize() async {
    if (_disposed || _disposing) {
      throw StateError('Proxy controller has already been disposed.');
    }

    final existingCompleter = _readyCompleter;
    if (existingCompleter != null) {
      return existingCompleter.future;
    }

    final readyCompleter = _readyCompleter = Completer<void>();
    _shutdownCompleter = Completer<void>();
    _receivePort = ReceivePort();
    _errorPort = ReceivePort();
    _exitPort = ReceivePort();
    _receiveSubscription = _receivePort!.listen(_handleIsolateMessage);
    _errorSubscription = _errorPort!.listen(_handleIsolateError);
    _exitSubscription = _exitPort!.listen(_handleIsolateExit);
    try {
      _isolate = await _spawnIsolate(
        _receivePort!.sendPort,
        _errorPort!.sendPort,
        _exitPort!.sendPort,
      );
    } catch (error, stackTrace) {
      _completeInitializationError(error, stackTrace);
      await _resetIsolateConnection();
    }
    await readyCompleter.future;
  }

  Future<void> configure({
    required AppSettings settings,
    required List<AccountProfile> accounts,
  }) async {
    await initialize();
    _lastSettings = settings;
    _lastAccounts = accounts;
    if (!settings.androidBackgroundRuntime) {
      await AndroidForegroundRuntime.stopIfRunning();
    } else {
      await _syncExistingAndroidRuntime(settings);
    }
    final runtimeAccounts = <Map<String, Object?>>[];
    for (final account in accounts) {
      final tokens = await _secretStore.readOAuthTokens(account.tokenRef);
      if (tokens == null) {
        continue;
      }
      runtimeAccounts.add(account.toRuntimeJson(tokens: tokens));
    }

    final payload = {
      'settings': {
        'api_key': settings.apiKey,
        'api_key_required': settings.apiKeyRequired,
        'host': settings.host,
        'port': settings.port,
        'allow_lan': settings.allowLan,
        'custom_models': settings.customModels,
        'logging_verbosity': settings.loggingVerbosity.name,
        'unsafe_raw_logging_enabled': settings.unsafeRawLoggingEnabled,
        'android_background_runtime': settings.androidBackgroundRuntime,
        'request_max_retries': settings.requestMaxRetries,
        'mark_429_as_unhealthy': settings.mark429AsUnhealthy,
      },
      'accounts': runtimeAccounts,
    };

    final signature = jsonEncode(payload);
    if (signature == _lastSignature) {
      return;
    }
    _lastSignature = signature;
    _commandPort?.send({'type': 'configure', 'payload': payload});
  }

  Future<void> start() async {
    await initialize();
    if (_lastSettings != null && _lastSignature == null) {
      await configure(settings: _lastSettings!, accounts: _lastAccounts);
    }
    _awaitingStartResult = true;
    final settings = _lastSettings;
    if (settings != null && await _syncExistingAndroidRuntime(settings)) {
      _awaitingStartResult = false;
      unawaited(
        _analytics.trackProxyStarted(
          allowLan: settings.allowLan,
          activeAccounts: _currentState.activeAccounts,
        ),
      );
      if (settings.androidBackgroundRuntime) {
        await AndroidForegroundRuntime.ensureRunning();
      }
      return;
    }
    if (settings != null &&
        settings.androidBackgroundRuntime &&
        await AndroidForegroundRuntime.isRunning()) {
      await AndroidForegroundRuntime.stopIfRunning();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    _commandPort?.send({'type': 'start'});
    if (settings?.androidBackgroundRuntime == true) {
      await AndroidForegroundRuntime.ensureRunning();
    }
  }

  Future<void> stop() async {
    _awaitingStartResult = false;
    _commandPort?.send({'type': 'stop'});
    await AndroidForegroundRuntime.stopIfRunning();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposing = true;
    _awaitingStartResult = false;
    _completeInitializationError(
      StateError('Proxy controller was disposed during initialization.'),
      StackTrace.current,
    );
    final isolate = _isolate;
    final shutdown = _shutdownCompleter ?? Completer<void>();
    _shutdownCompleter = shutdown;
    _commandPort?.send({'type': 'shutdown'});
    if (isolate != null) {
      try {
        await shutdown.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        isolate.kill(priority: Isolate.immediate);
        try {
          await shutdown.future.timeout(const Duration(seconds: 1));
        } on TimeoutException {
          if (!shutdown.isCompleted) {
            shutdown.complete();
          }
        }
      }
    }
    await _resetIsolateConnection();
    _disposed = true;
    await _states.close();
    await _activity.close();
  }

  Future<void> _handleIsolateMessage(dynamic message) async {
    if (message is! Map) {
      return;
    }
    final type = message['type'];
    switch (type) {
      case 'ready':
        _commandPort = message['port'] as SendPort?;
        _currentState = _currentState.copyWith(ready: true);
        _emitState(_currentState);
        final readyCompleter = _readyCompleter;
        if (readyCompleter != null && !readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
        break;
      case 'status':
        final previousState = _currentState;
        final state = ProxyRuntimeState.fromJson(
          (message['payload'] as Map).cast<String, Object?>(),
        );
        _currentState = state;
        _emitState(_currentState);
        _handleStatusTransition(previousState, state);
        break;
      case 'log':
        final payload = (message['payload'] as Map).cast<String, Object?>();
        await _logsRepository.insert(
          AppLogEntry(
            id: payload['id'] as String,
            timestamp: DateTime.tryParse(payload['timestamp'] as String? ?? '') ?? DateTime.now(),
            level: AppLogLevel.values.firstWhere(
              (value) => value.name == payload['level'],
              orElse: () => AppLogLevel.info,
            ),
            category: payload['category'] as String? ?? 'proxy',
            route: payload['route'] as String?,
            message: payload['message'] as String? ?? '',
            maskedPayload: payload['masked_payload'] as String?,
            rawPayload: payload['raw_payload'] as String?,
          ),
        );
        _emitActivity('logs');
        break;
      case 'accounts_runtime_updated':
        final accounts = ((message['payload'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => AccountProfile.fromDatabaseMap(item.cast<String, Object?>()))
            .toList(growable: false);
        await _accountsRepository.mergeRuntimeState(accounts);
        _emitActivity('accounts');
        break;
      case 'analytics':
        final payload = (message['payload'] as Map).cast<String, Object?>();
        await _handleAnalyticsMessage(payload);
        break;
      case 'token_updated':
        final payload = (message['payload'] as Map).cast<String, Object?>();
        final tokens = OAuthTokens.fromJson(
          ((payload['tokens'] as Map?) ?? const <String, Object?>{}).cast<String, Object?>(),
        );
        final tokenRef = payload['token_ref'] as String? ?? '';
        if (tokenRef.isNotEmpty) {
          await _secretStore.writeOAuthTokens(tokenRef, tokens);
        }
        break;
      case 'request_reconfigure':
        if (_lastSettings != null) {
          await configure(settings: _lastSettings!, accounts: _lastAccounts);
        }
        break;
    }
  }

  void _handleIsolateError(dynamic message) {
    _pendingIsolateFailure = _formatIsolateFailure(message);
  }

  Future<void> _handleIsolateExit(dynamic _) async {
    final failureMessage =
        _pendingIsolateFailure ??
        (_disposing ? null : 'Proxy runtime stopped unexpectedly. Restart the proxy.');
    _pendingIsolateFailure = null;
    await _resetIsolateConnection();
    _completeInitializationError(
      StateError(failureMessage ?? 'Proxy isolate exited before initialization completed.'),
      StackTrace.current,
    );
    final shutdownCompleter = _shutdownCompleter;
    if (shutdownCompleter != null && !shutdownCompleter.isCompleted) {
      shutdownCompleter.complete();
    }
    if (_disposing) {
      return;
    }
    _lastSignature = null;
    _currentState = _currentState.copyWith(
      ready: false,
      running: false,
      clearStartedAt: true,
      lastError: failureMessage,
    );
    _emitState(_currentState);
  }

  Future<bool> _syncExistingAndroidRuntime(AppSettings settings) async {
    if (!Platform.isAndroid || !await AndroidForegroundRuntime.isRunning()) {
      return false;
    }

    final payload = await _probeExistingRuntime(settings);
    if (payload == null || payload['ok'] != true || payload['running'] != true) {
      return false;
    }

    _currentState = _currentState.copyWith(
      ready: true,
      running: true,
      boundHost: settings.allowLan ? '0.0.0.0' : settings.host,
      port: settings.port,
      activeAccounts: payload['active_accounts'] as int? ?? 0,
      clearLastError: true,
    );
    _emitState(_currentState);
    return true;
  }

  Future<Map<String, Object?>?> _probeExistingRuntime(AppSettings settings) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    final probeHost = settings.allowLan || settings.host == '0.0.0.0' ? '127.0.0.1' : settings.host;
    final uri = Uri.http('$probeHost:${settings.port}', '/health');

    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 1));
      final response = await request.close().timeout(const Duration(seconds: 1));
      if (response.statusCode != 200) {
        return null;
      }

      final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 1));
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.cast<String, Object?>();
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void _handleStatusTransition(ProxyRuntimeState previous, ProxyRuntimeState next) {
    if (!_awaitingStartResult) {
      return;
    }

    if (!previous.running && next.running) {
      _awaitingStartResult = false;
      unawaited(
        _analytics.trackProxyStarted(
          allowLan: _lastSettings?.allowLan ?? false,
          activeAccounts: next.activeAccounts,
        ),
      );
      return;
    }

    if (!next.running && next.lastError != null) {
      _awaitingStartResult = false;
      unawaited(_analytics.trackProxyStartFailed(errorKind: _classifyRuntimeError(next.lastError)));
    }
  }

  Future<void> _handleAnalyticsMessage(Map<String, Object?> payload) async {
    final kind = payload['kind'] as String? ?? '';
    switch (kind) {
      case 'proxy_request_succeeded':
        await _analytics.trackFirstSuccessfulRequest(
          route: payload['route'] as String? ?? '',
          model: payload['model'] as String? ?? '',
          stream: payload['stream'] == true,
        );
        break;
      case 'proxy_request_failed':
        await _analytics.trackProxyRequestFailed(
          route: payload['route'] as String? ?? '',
          model: payload['model'] as String? ?? '',
          stream: payload['stream'] == true,
          errorKind: payload['error_kind'] as String? ?? 'unknown',
          statusCode: payload['status_code'] as int?,
        );
        break;
    }
  }

  String _classifyRuntimeError(String? message) {
    final value = (message ?? '').toLowerCase();
    if (value.contains('not configured')) {
      return 'not_configured';
    }
    if (_looksLikePortInUseError(value)) {
      return 'port_in_use';
    }
    if (value.contains('permission')) {
      return 'permission_denied';
    }
    return 'runtime_error';
  }

  void _emitState(ProxyRuntimeState state) {
    if (_states.isClosed) {
      return;
    }
    _states.add(state);
  }

  void _emitActivity(String value) {
    if (_activity.isClosed) {
      return;
    }
    _activity.add(value);
  }

  void _completeInitializationError(Object error, StackTrace stackTrace) {
    final readyCompleter = _readyCompleter;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.completeError(error, stackTrace);
    }
    _readyCompleter = null;
  }

  Future<void> _resetIsolateConnection() async {
    _commandPort = null;
    _isolate = null;
    _lastSignature = null;

    await _receiveSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _exitSubscription?.cancel();
    _receiveSubscription = null;
    _errorSubscription = null;
    _exitSubscription = null;

    _receivePort?.close();
    _errorPort?.close();
    _exitPort?.close();
    _receivePort = null;
    _errorPort = null;
    _exitPort = null;
  }

  String _formatIsolateFailure(dynamic message) {
    if (message is List && message.isNotEmpty) {
      final error = message.first;
      final stackTrace = message.length > 1 ? message[1] : null;
      final errorText = error?.toString().trim();
      final stackText = stackTrace?.toString().trim();
      if (errorText != null && errorText.isNotEmpty) {
        if (stackText != null && stackText.isNotEmpty) {
          return '$errorText\n$stackText';
        }
        return errorText;
      }
    }
    final value = message?.toString().trim();
    return value == null || value.isEmpty
        ? 'Proxy isolate exited before initialization completed.'
        : value;
  }

  static Future<Isolate> _defaultSpawnIsolate(
    SendPort messagePort,
    SendPort errorPort,
    SendPort exitPort,
  ) {
    return Isolate.spawn(
      proxyIsolateMain,
      messagePort,
      onError: errorPort,
      onExit: exitPort,
    );
  }
}

bool _looksLikePortInUseError(String value) {
  return value.contains('address already in use') ||
      value.contains('only one usage') ||
      value.contains('shared flag to bind()') ||
      value.contains('binding multiple times on the same') ||
      value.contains('failed to create server socket');
}
