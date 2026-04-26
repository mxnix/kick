import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../../analytics/kick_analytics.dart';
import '../../core/platform/android_foreground_runtime.dart';
import '../../core/platform/android_local_network_permission.dart';
import '../../data/models/account_profile.dart';
import '../../data/models/app_log_entry.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/oauth_tokens.dart';
import '../../data/repositories/accounts_repository.dart';
import '../../data/repositories/logs_repository.dart';
import '../../data/repositories/secret_store.dart';
import '../../observability/glitchtip.dart';
import '../engine/proxy_isolate.dart';
import '../kiro/kiro_auth_source.dart';

typedef ProxyIsolateSpawner =
    Future<Isolate> Function(SendPort messagePort, SendPort errorPort, SendPort exitPort);
typedef ProxyRuntimeProbe = Future<Map<String, Object?>?> Function(AppSettings settings);
typedef AndroidPlatformCheck = bool Function();
typedef AndroidRuntimeRunningCheck = Future<bool> Function();
typedef AndroidRuntimeEffect = Future<void> Function();
typedef AndroidLocalNetworkPermissionRequest = Future<bool> Function();

class ProxyRuntimeState {
  const ProxyRuntimeState({
    required this.ready,
    required this.running,
    required this.startPending,
    required this.boundHost,
    required this.port,
    required this.startedAt,
    required this.requestCount,
    required this.activeAccounts,
    required this.healthyAccounts,
    required this.lastError,
  });

  factory ProxyRuntimeState.initial() {
    return const ProxyRuntimeState(
      ready: false,
      running: false,
      startPending: false,
      boundHost: '127.0.0.1',
      port: 3000,
      startedAt: null,
      requestCount: 0,
      activeAccounts: 0,
      healthyAccounts: 0,
      lastError: null,
    );
  }

  final bool ready;
  final bool running;
  final bool startPending;
  final String boundHost;
  final int port;
  final DateTime? startedAt;
  final int requestCount;
  final int activeAccounts;
  final int healthyAccounts;
  final String? lastError;

  Duration? get uptime => startedAt == null ? null : DateTime.now().difference(startedAt!);

  ProxyRuntimeState copyWith({
    bool? ready,
    bool? running,
    bool? startPending,
    String? boundHost,
    int? port,
    DateTime? startedAt,
    bool clearStartedAt = false,
    int? requestCount,
    int? activeAccounts,
    int? healthyAccounts,
    String? lastError,
    bool clearLastError = false,
  }) {
    return ProxyRuntimeState(
      ready: ready ?? this.ready,
      running: running ?? this.running,
      startPending: startPending ?? this.startPending,
      boundHost: boundHost ?? this.boundHost,
      port: port ?? this.port,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      requestCount: requestCount ?? this.requestCount,
      activeAccounts: activeAccounts ?? this.activeAccounts,
      healthyAccounts: healthyAccounts ?? this.healthyAccounts,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  factory ProxyRuntimeState.fromJson(Map<String, Object?> json) {
    return ProxyRuntimeState(
      ready: json['ready'] as bool? ?? false,
      running: json['running'] as bool? ?? false,
      startPending: json['start_pending'] as bool? ?? false,
      boundHost: json['bound_host'] as String? ?? '127.0.0.1',
      port: json['port'] as int? ?? 3000,
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? ''),
      requestCount: json['request_count'] as int? ?? 0,
      activeAccounts: json['active_accounts'] as int? ?? 0,
      healthyAccounts: json['healthy_accounts'] as int? ?? 0,
      lastError: json['last_error'] as String?,
    );
  }
}

class _ProxySessionMetrics {
  int successCount = 0;
  int failedCount = 0;
  int retriedCount = 0;
  bool active = false;
  bool summaryEmitted = false;

  void begin() {
    successCount = 0;
    failedCount = 0;
    retriedCount = 0;
    active = true;
    summaryEmitted = false;
  }

  void end() {
    active = false;
    summaryEmitted = true;
  }
}

class KickProxyController {
  KickProxyController({
    required AccountsRepository accountsRepository,
    required KickAnalytics analytics,
    String geminiInstallationIdPath = '',
    required LogsRepository logsRepository,
    required SecretStore secretStore,
    AndroidPlatformCheck? isAndroidPlatform,
    AndroidRuntimeRunningCheck? isAndroidRuntimeRunning,
    AndroidRuntimeEffect? stopAndroidRuntimeIfRunning,
    AndroidRuntimeEffect? ensureAndroidRuntimeRunning,
    AndroidLocalNetworkPermissionRequest? ensureAndroidLocalNetworkPermission,
    ProxyRuntimeProbe? probeExistingRuntime,
    ProxyIsolateSpawner? spawnIsolate,
  }) : _accountsRepository = accountsRepository,
       _analytics = analytics,
       _geminiInstallationIdPath = geminiInstallationIdPath,
       _isAndroidPlatform = isAndroidPlatform ?? _defaultIsAndroidPlatform,
       _isAndroidRuntimeRunning = isAndroidRuntimeRunning ?? AndroidForegroundRuntime.isRunning,
       _stopAndroidRuntimeIfRunning =
           stopAndroidRuntimeIfRunning ?? AndroidForegroundRuntime.stopIfRunning,
       _ensureAndroidRuntimeRunning =
           ensureAndroidRuntimeRunning ?? AndroidForegroundRuntime.ensureRunning,
       _ensureAndroidLocalNetworkPermission =
           ensureAndroidLocalNetworkPermission ?? AndroidLocalNetworkPermission.ensureGranted,
       _logsRepository = logsRepository,
       _probeExistingRuntime = probeExistingRuntime ?? _defaultProbeExistingRuntime,
       _secretStore = secretStore,
       _spawnIsolate = spawnIsolate ?? _defaultSpawnIsolate;

  final AccountsRepository _accountsRepository;
  final KickAnalytics _analytics;
  final String _geminiInstallationIdPath;
  final AndroidPlatformCheck _isAndroidPlatform;
  final AndroidRuntimeRunningCheck _isAndroidRuntimeRunning;
  final AndroidRuntimeEffect _stopAndroidRuntimeIfRunning;
  final AndroidRuntimeEffect _ensureAndroidRuntimeRunning;
  final AndroidLocalNetworkPermissionRequest _ensureAndroidLocalNetworkPermission;
  final LogsRepository _logsRepository;
  final ProxyRuntimeProbe _probeExistingRuntime;
  final SecretStore _secretStore;
  final ProxyIsolateSpawner _spawnIsolate;

  final _states = StreamController<ProxyRuntimeState>.broadcast();
  final _activity = StreamController<String>.broadcast();
  ProxyRuntimeState _currentState = ProxyRuntimeState.initial();
  final _sessionMetrics = _ProxySessionMetrics();
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
  String? _localRuntimeError;
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
    if (_currentState.running &&
        !await _ensureAndroidLocalNetworkPermissionFor(
          settings,
          route: '/runtime/configure',
          trackStartFailure: false,
        )) {
      return;
    }
    if (!settings.androidBackgroundRuntime) {
      await _stopAndroidRuntimeIfRunning();
    } else {
      await _syncExistingAndroidRuntime(settings);
    }
    final runtimeAccounts = <Map<String, Object?>>[];
    for (final account in accounts) {
      OAuthTokens? tokens;
      var runtimeAccount = account;
      if (account.provider == AccountProvider.kiro) {
        final KiroAuthSourceSnapshot? source;
        try {
          source = await loadKiroAuthSource(sourcePath: account.credentialSourcePath);
        } on FileSystemException {
          continue;
        } on FormatException {
          continue;
        } on TypeError {
          continue;
        }
        if (source == null) {
          continue;
        }
        tokens = source.toOAuthTokens();
        runtimeAccount = account.copyWith(
          providerRegion: source.effectiveRegion,
          credentialSourceType: source.sourceType,
          credentialSourcePath: source.sourcePath,
          providerProfileArn: source.profileArn ?? account.providerProfileArn,
          email: account.email.trim().isNotEmpty ? account.email : source.displayIdentity,
        );
      } else {
        tokens = await _secretStore.readOAuthTokens(account.tokenRef);
      }
      if (tokens == null) {
        continue;
      }
      runtimeAccounts.add(runtimeAccount.toRuntimeJson(tokens: tokens));
    }

    final payload = {
      'gemini_installation_id_path': _geminiInstallationIdPath,
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
        'retry_429_delay_seconds': settings.retry429DelaySeconds,
        'mark_429_as_unhealthy': settings.mark429AsUnhealthy,
        'default_google_web_search_enabled': settings.defaultGoogleWebSearchEnabled,
        'render_google_grounding_in_message': settings.renderGoogleGroundingInMessage,
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
    if (_awaitingStartResult) {
      return;
    }

    _awaitingStartResult = true;
    if (!_currentState.running) {
      _setStartPending(true);
    }
    var waitingForRuntimeStatus = false;
    try {
      await initialize();
      if (_lastSettings != null && _lastSignature == null) {
        await configure(settings: _lastSettings!, accounts: _lastAccounts);
      }

      final settings = _lastSettings;
      if (settings != null &&
          !await _ensureAndroidLocalNetworkPermissionFor(
            settings,
            route: '/runtime/start',
            trackStartFailure: true,
          )) {
        return;
      }
      final wasRunningBeforeSync = _currentState.running;
      if (settings != null && await _syncExistingAndroidRuntime(settings)) {
        _awaitingStartResult = false;
        _setStartPending(false);
        if (!wasRunningBeforeSync) {
          unawaited(
            _analytics.trackProxyStarted(
              allowLan: settings.allowLan,
              activeAccounts: _currentState.activeAccounts,
            ),
          );
        }
        if (settings.androidBackgroundRuntime) {
          await _ensureAndroidRuntimeRunning();
        }
        return;
      }
      if (_currentState.running) {
        _awaitingStartResult = false;
        _setStartPending(false);
        if (settings?.androidBackgroundRuntime == true) {
          await _ensureAndroidRuntimeRunning();
        }
        return;
      }
      if (settings != null &&
          settings.androidBackgroundRuntime &&
          await _isAndroidRuntimeRunning()) {
        await _stopAndroidRuntimeIfRunning();
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      waitingForRuntimeStatus = true;
      _commandPort?.send({'type': 'start'});
      if (settings?.androidBackgroundRuntime == true) {
        await _ensureAndroidRuntimeRunning();
      }
    } catch (_) {
      if (!waitingForRuntimeStatus) {
        _awaitingStartResult = false;
        _setStartPending(false);
      }
      rethrow;
    }
  }

  Future<void> stop() async {
    _awaitingStartResult = false;
    _setStartPending(false);
    _commandPort?.send({'type': 'stop'});
    await _stopAndroidRuntimeIfRunning();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposing = true;
    _awaitingStartResult = false;
    await _emitProxySessionSummaryIfNeeded(stopReason: 'shutdown');
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
        var state = _withDerivedStateFlags(
          ProxyRuntimeState.fromJson((message['payload'] as Map).cast<String, Object?>()),
        );
        final localRuntimeError = _localRuntimeError;
        if (localRuntimeError != null && state.lastError == null) {
          state = state.copyWith(lastError: localRuntimeError);
        } else if (state.lastError != null && state.lastError != localRuntimeError) {
          _localRuntimeError = null;
        }
        _currentState = state;
        _emitState(_currentState);
        _handleStatusTransition(previousState, state);
        break;
      case 'log':
        final payload = (message['payload'] as Map).cast<String, Object?>();
        final entry = AppLogEntry(
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
        );
        await _logsRepository.insert(entry);
        unawaited(recordGlitchTipProxyLog(entry));
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
    if (!_disposing && failureMessage != null && failureMessage.trim().isNotEmpty) {
      unawaited(
        captureGlitchTipMessage(
          message: 'Proxy isolate exited unexpectedly',
          template: 'Proxy isolate exited unexpectedly',
          source: 'proxy_isolate',
          tags: const <String, String>{'state': 'unexpected_exit'},
          data: <String, Object?>{
            'failure': failureMessage,
            'ready': _currentState.ready,
            'running': _currentState.running,
            'request_count': _currentState.requestCount,
            'active_accounts': _currentState.activeAccounts,
            'healthy_accounts': _currentState.healthyAccounts,
          },
          fingerprint: const <String>['kick-proxy', 'isolate_exit'],
        ),
      );
    }
    _pendingIsolateFailure = null;
    await _emitProxySessionSummaryIfNeeded(stopReason: _disposing ? 'shutdown' : 'runtime_error');
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
      startPending: false,
      clearStartedAt: true,
      requestCount: 0,
      lastError: failureMessage,
    );
    _emitState(_currentState);
  }

  Future<bool> _syncExistingAndroidRuntime(AppSettings settings) async {
    if (!_isAndroidPlatform() || !await _isAndroidRuntimeRunning()) {
      return false;
    }

    final payload = await _probeExistingRuntime(settings);
    if (payload == null || payload['ok'] != true || payload['running'] != true) {
      return false;
    }

    final wasRunning = _currentState.running;
    _currentState = _currentState.copyWith(
      ready: true,
      running: true,
      startPending: false,
      boundHost: settings.allowLan ? '0.0.0.0' : settings.host,
      port: settings.port,
      activeAccounts: payload['active_accounts'] as int? ?? 0,
      healthyAccounts: payload['healthy_accounts'] as int? ?? 0,
      clearLastError: true,
    );
    if (!wasRunning) {
      _sessionMetrics.begin();
    }
    _emitState(_currentState);
    return true;
  }

  static Future<Map<String, Object?>?> _defaultProbeExistingRuntime(AppSettings settings) async {
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

  static bool _defaultIsAndroidPlatform() => Platform.isAndroid;

  Future<bool> _ensureAndroidLocalNetworkPermissionFor(
    AppSettings settings, {
    required String route,
    required bool trackStartFailure,
  }) async {
    if (!_isAndroidPlatform() || !requiresAndroidLocalNetworkPermission(settings)) {
      _localRuntimeError = null;
      return true;
    }

    try {
      final granted = await _ensureAndroidLocalNetworkPermission();
      if (granted) {
        _localRuntimeError = null;
        return true;
      }
      await _recordLocalNetworkPermissionFailure(
        route: route,
        message: androidLocalNetworkPermissionDeniedMessage,
        trackStartFailure: trackStartFailure,
      );
      return false;
    } catch (error, stackTrace) {
      await _recordLocalNetworkPermissionFailure(
        route: route,
        message: 'Local network permission request failed: $error',
        stackTrace: stackTrace,
        trackStartFailure: trackStartFailure,
      );
      return false;
    }
  }

  Future<void> _recordLocalNetworkPermissionFailure({
    required String route,
    required String message,
    required bool trackStartFailure,
    StackTrace? stackTrace,
  }) async {
    _awaitingStartResult = false;
    _localRuntimeError = message;
    _currentState = _currentState.copyWith(startPending: false, lastError: message);
    _emitState(_currentState);
    await _logsRepository.insert(
      AppLogEntry(
        id: 'proxy-local-network-permission-${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        level: AppLogLevel.warning,
        category: 'proxy.runtime',
        route: route,
        message: message,
        maskedPayload: stackTrace?.toString(),
      ),
    );
    _emitActivity('logs');
    if (trackStartFailure) {
      await _analytics.trackProxyStartFailed(errorKind: _classifyRuntimeError(message));
    }
  }

  void _handleStatusTransition(ProxyRuntimeState previous, ProxyRuntimeState next) {
    if (!_awaitingStartResult) {
      if (!previous.running && next.running) {
        _sessionMetrics.begin();
      } else if (previous.running && !next.running) {
        unawaited(
          _emitProxySessionSummaryIfNeeded(
            stopReason: _stopReasonForState(next),
            stateSnapshot: _summaryStateForStopTransition(previous, next),
          ),
        );
      }
      return;
    }

    if (!previous.running && next.running) {
      _awaitingStartResult = false;
      _sessionMetrics.begin();
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
      unawaited(_emitProxySessionSummaryIfNeeded(stopReason: _stopReasonForState(next)));
      return;
    }

    if (previous.running && !next.running) {
      unawaited(
        _emitProxySessionSummaryIfNeeded(
          stopReason: _stopReasonForState(next),
          stateSnapshot: _summaryStateForStopTransition(previous, next),
        ),
      );
    }
  }

  Future<void> _handleAnalyticsMessage(Map<String, Object?> payload) async {
    final kind = payload['kind'] as String? ?? '';
    switch (kind) {
      case 'proxy_request_succeeded':
        if (_sessionMetrics.active) {
          _sessionMetrics.successCount += 1;
        }
        await _analytics.trackFirstSuccessfulRequest(
          route: payload['route'] as String? ?? '',
          model: payload['model'] as String? ?? '',
          stream: payload['stream'] == true,
        );
        break;
      case 'proxy_request_failed':
        if (_sessionMetrics.active) {
          _sessionMetrics.failedCount += 1;
        }
        await _analytics.trackProxyRequestFailed(
          route: payload['route'] as String? ?? '',
          model: payload['model'] as String? ?? '',
          stream: payload['stream'] == true,
          errorKind: payload['error_kind'] as String? ?? 'unknown',
          errorSource: payload['error_source'] as String?,
          statusCode: payload['status_code'] as int?,
          errorDetail: payload['error_detail'] as String?,
          upstreamReason: payload['upstream_reason'] as String?,
          retryAfterMs: payload['retry_after_ms'] as int?,
          hasActionUrl: payload.containsKey('has_action_url')
              ? payload['has_action_url'] == true
              : null,
        );
        break;
      case 'proxy_request_retried':
        if (_sessionMetrics.active) {
          _sessionMetrics.retriedCount += 1;
        }
        await _analytics.trackProxyRequestRetried(
          route: payload['route'] as String? ?? '',
          model: payload['model'] as String? ?? '',
          stream: payload['stream'] == true,
          outcome: payload['outcome'] as String? ?? 'unknown',
          retryCount: payload['retry_count'] as int? ?? 0,
          upstreamRetryCount: payload['upstream_retry_count'] as int? ?? 0,
          accountFailoverCount: payload['account_failover_count'] as int? ?? 0,
          retryKinds: payload['retry_kinds'] as String?,
          retryDelayMs: payload['retry_delay_ms'] as int?,
          statusCode: payload['status_code'] as int?,
          errorSource: payload['error_source'] as String?,
          errorDetail: payload['error_detail'] as String?,
          upstreamReason: payload['upstream_reason'] as String?,
          retryAfterMs: payload['retry_after_ms'] as int?,
          hasActionUrl: payload.containsKey('has_action_url')
              ? payload['has_action_url'] == true
              : null,
        );
        break;
      case 'upstream_compatibility_issue':
        await _analytics.trackUpstreamCompatibilityIssue(
          issueKind: payload['issue_kind'] as String? ?? 'unknown',
          route: payload['route'] as String? ?? '',
          model: payload['model'] as String? ?? '',
          stream: payload['stream'] == true,
          errorKind: payload['error_kind'] as String?,
          errorSource: payload['error_source'] as String?,
          statusCode: payload['status_code'] as int?,
          errorDetail: payload['error_detail'] as String?,
          upstreamReason: payload['upstream_reason'] as String?,
          retryAfterMs: payload['retry_after_ms'] as int?,
          hasActionUrl: payload.containsKey('has_action_url')
              ? payload['has_action_url'] == true
              : null,
        );
        break;
    }
  }

  String _classifyRuntimeError(String? message) {
    final value = (message ?? '').toLowerCase();
    if (value.contains('not configured')) {
      return 'not_configured';
    }
    if (looksLikeProxyPortInUseError(value)) {
      return 'port_in_use';
    }
    if (value.contains('permission')) {
      return 'permission_denied';
    }
    return 'runtime_error';
  }

  ProxyRuntimeState _summaryStateForStopTransition(
    ProxyRuntimeState previous,
    ProxyRuntimeState next,
  ) {
    return next.copyWith(startedAt: next.startedAt ?? previous.startedAt);
  }

  Future<void> _emitProxySessionSummaryIfNeeded({
    required String stopReason,
    ProxyRuntimeState? stateSnapshot,
  }) async {
    if (!_sessionMetrics.active || _sessionMetrics.summaryEmitted) {
      return;
    }

    final currentSettings = _lastSettings;
    final currentState = stateSnapshot ?? _currentState;
    final uptimeSec = currentState.startedAt == null
        ? 0
        : DateTime.now().difference(currentState.startedAt!).inSeconds;
    final payload = <String, Object?>{
      'stop_reason': stopReason,
      'uptime_sec': uptimeSec < 0 ? 0 : uptimeSec,
      'request_count': currentState.requestCount,
      'success_count': _sessionMetrics.successCount,
      'failed_count': _sessionMetrics.failedCount,
      'retried_count': _sessionMetrics.retriedCount,
      'active_accounts': currentState.activeAccounts,
      'healthy_accounts': currentState.healthyAccounts,
      if (currentSettings != null) 'request_max_retries': currentSettings.requestMaxRetries,
      if (currentSettings != null) 'mark_429_as_unhealthy': currentSettings.mark429AsUnhealthy,
      if (currentSettings != null)
        'android_background_runtime': currentSettings.androidBackgroundRuntime,
    };

    await _logsRepository.insert(
      AppLogEntry(
        id: 'proxy-session-${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        level: AppLogLevel.info,
        category: 'proxy.session',
        route: '/runtime/session',
        message: 'Proxy session summary',
        maskedPayload: jsonEncode(payload),
      ),
    );

    await _analytics.trackProxySessionSummary(
      uptimeSec: payload['uptime_sec'] as int? ?? 0,
      requestCount: payload['request_count'] as int? ?? 0,
      successCount: payload['success_count'] as int? ?? 0,
      failedCount: payload['failed_count'] as int? ?? 0,
      retriedCount: payload['retried_count'] as int? ?? 0,
      activeAccounts: payload['active_accounts'] as int? ?? 0,
      healthyAccounts: payload['healthy_accounts'] as int? ?? 0,
      requestMaxRetries: payload['request_max_retries'] as int? ?? 0,
      mark429AsUnhealthy: payload['mark_429_as_unhealthy'] as bool? ?? false,
      androidBackgroundRuntime: payload['android_background_runtime'] as bool? ?? false,
      stopReason: stopReason,
    );
    _sessionMetrics.end();
  }

  String _stopReasonForState(ProxyRuntimeState state) {
    if (state.lastError != null && state.lastError!.trim().isNotEmpty) {
      return _classifyRuntimeError(state.lastError);
    }
    return 'stopped';
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

  ProxyRuntimeState _withDerivedStateFlags(ProxyRuntimeState state) {
    return state.copyWith(
      startPending: _awaitingStartResult && !state.running && state.lastError == null,
    );
  }

  void _setStartPending(bool value) {
    if (_currentState.startPending == value) {
      return;
    }
    _currentState = _currentState.copyWith(startPending: value);
    _emitState(_currentState);
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
    return Isolate.spawn(proxyIsolateMain, messagePort, onError: errorPort, onExit: exitPort);
  }
}
