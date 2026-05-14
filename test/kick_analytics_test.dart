import 'package:aptabase_flutter/storage_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/kick_analytics.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/models/app_settings.dart';

void main() {
  test('release config prefers release app key and host', () {
    final config = AnalyticsBuildConfig.resolve(
      isReleaseMode: true,
      releaseAppKey: 'A-EU-release',
      debugAppKey: 'A-EU-debug',
      releaseHost: 'https://analytics.example.com',
      debugHost: 'http://localhost:3000',
    );

    expect(config.buildChannel, 'release');
    expect(config.appKey, 'A-EU-release');
    expect(config.host, 'https://analytics.example.com');
    expect(config.isEnabled, isTrue);
  });

  test('debug config stays disabled when debug key is missing', () {
    final config = AnalyticsBuildConfig.resolve(
      isReleaseMode: false,
      releaseAppKey: 'A-EU-release',
      debugAppKey: '  ',
    );

    expect(config.buildChannel, 'debug');
    expect(config.isEnabled, isFalse);
  });

  test('tracking requires disclaimer acknowledgement and consent', () {
    const base = AppSettings(
      apiKey: 'kick_test',
      apiKeyRequired: true,
      themeMode: ThemeMode.system,
      useSystemFont: false,
      useDynamicColor: true,
      hasAcknowledgedDisclaimer: false,
      analyticsConsentEnabled: false,
      host: '127.0.0.1',
      port: 3000,
      allowLan: false,
      androidBackgroundRuntime: true,
      windowsLaunchAtStartup: false,
      requestMaxRetries: 10,
      retry429DelaySeconds: 30,
      mark429AsUnhealthy: false,
      loggingVerbosity: KickLogVerbosity.normal,
      logRetentionCount: defaultLogRetentionCount,
      unsafeRawLoggingEnabled: false,
      customModels: <String>[],
    );

    expect(analyticsTrackingAllowed(base), isFalse);
    expect(
      analyticsTrackingAllowed(
        base.copyWith(hasAcknowledgedDisclaimer: true, analyticsConsentEnabled: false),
      ),
      isFalse,
    );
    expect(
      analyticsTrackingAllowed(
        base.copyWith(hasAcknowledgedDisclaimer: true, analyticsConsentEnabled: true),
      ),
      isTrue,
    );
  });

  group('modelFamily', () {
    test('buckets gemini variants without leaking exact ids', () {
      expect(KickAnalytics.modelFamily('google/gemini-2.5-pro-preview'), 'gemini-2.5-pro');
      expect(KickAnalytics.modelFamily('google/gemini-2.5-flash-lite'), 'gemini-2.5-flash-lite');
      expect(KickAnalytics.modelFamily('google/gemini-3-flash'), 'gemini-3');
      expect(KickAnalytics.modelFamily('google/gemini-3.1-pro-preview'), 'gemini-3');
      expect(KickAnalytics.modelFamily('google/gemini-2.0-flash-exp'), 'gemini-2.0-flash');
    });

    test('buckets known kiro models including new opus 4.7', () {
      expect(KickAnalytics.modelFamily('kiro/claude-opus-4.5'), 'kiro-claude-opus-4.5');
      expect(KickAnalytics.modelFamily('kiro/claude-opus-4.7'), 'kiro-claude-opus-4.7');
      expect(KickAnalytics.modelFamily('kiro/claude-opus-4'), 'kiro-claude-opus-4');
      expect(KickAnalytics.modelFamily('kiro/claude-sonnet-4.5'), 'kiro-claude-sonnet-4.5');
      expect(KickAnalytics.modelFamily('kiro/claude-haiku-3.5'), 'kiro-claude-haiku');
      expect(KickAnalytics.modelFamily('kiro/auto'), 'kiro');
      expect(KickAnalytics.modelFamily('kiro/simple-task'), 'kiro');
      expect(KickAnalytics.modelFamily('kiro/deepseek-v3'), 'kiro-deepseek');
      expect(KickAnalytics.modelFamily('kiro/qwen3-coder'), 'kiro-qwen');
      expect(KickAnalytics.modelFamily('kiro/minimax-m1'), 'kiro-minimax');
    });

    test('falls back to bare claude-/anthropic prefixes', () {
      expect(KickAnalytics.modelFamily('claude-opus-4.7'), 'kiro-claude-opus-4.7');
      expect(KickAnalytics.modelFamily('anthropic.claude-sonnet-4'), 'kiro-claude-sonnet-4');
    });

    test('routes openai-style ids to openai bucket', () {
      expect(KickAnalytics.modelFamily('gpt-4o-mini'), 'openai');
      expect(KickAnalytics.modelFamily('openai-test'), 'openai');
    });

    test('falls back to custom for unknown ids', () {
      expect(KickAnalytics.modelFamily('my-private-model-id'), 'custom');
      expect(KickAnalytics.modelFamily(''), 'unknown');
    });
  });

  test('providerName maps account providers to backend tags', () {
    expect(KickAnalytics.providerName(AccountProvider.gemini), 'google');
    expect(KickAnalytics.providerName(AccountProvider.kiro), 'kiro');
  });

  test('tracks retried requests with native bool flags and session id', () async {
    final transport = _RecordingAnalyticsTransport();
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
      transport: transport,
      trackingAllowed: true,
    );

    await analytics.trackProxyRequestRetried(
      route: '/v1/chat/completions',
      model: 'gemini-3.1-pro-preview',
      stream: false,
      outcome: 'succeeded',
      retryCount: 2,
      upstreamRetryCount: 1,
      accountFailoverCount: 1,
      retryKinds: 'quota,capacity',
      retryDelayMs: 49000,
      statusCode: 429,
      errorDetail: 'quotaExhausted',
      upstreamReason: 'RATE_LIMIT_EXCEEDED',
      retryAfterMs: 30000,
      hasActionUrl: true,
      sessionId: 'session-1',
      latencyMs: 12345,
    );

    expect(transport.events, hasLength(1));
    final event = transport.events.single;
    expect(event.name, 'proxy_request_retried');
    expect(
      event.properties,
      containsPair('model_family', KickAnalytics.modelFamily('gemini-3.1-pro-preview')),
    );
    expect(event.properties, containsPair('retry_count', 2));
    expect(event.properties, containsPair('upstream_retry_count', 1));
    expect(event.properties, containsPair('account_failover_count', 1));
    expect(event.properties, containsPair('retry_kinds', 'quota,capacity'));
    expect(event.properties, containsPair('retry_delay_ms', 49000));
    expect(event.properties, containsPair('status_code', 429));
    expect(event.properties, containsPair('error_detail', 'quotaExhausted'));
    expect(event.properties, containsPair('upstream_reason', 'RATE_LIMIT_EXCEEDED'));
    expect(event.properties, containsPair('retry_after_ms', 30000));
    expect(event.properties, containsPair('has_action_url', true));
    expect(event.properties, containsPair('session_id', 'session-1'));
    expect(event.properties, containsPair('latency_ms', 12345));
    expect(event.properties, containsPair('build_channel', 'test'));
    expect(event.properties, containsPair('stream', false));
  });

  test('tracks failed requests with safe structured gateway metadata', () async {
    final transport = _RecordingAnalyticsTransport();
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
      transport: transport,
      trackingAllowed: true,
    );

    await analytics.trackProxyRequestFailed(
      route: '/v1/responses',
      model: 'gemini-2.5-flash',
      stream: true,
      errorKind: 'invalidRequest',
      errorSource: 'upstream',
      statusCode: 403,
      errorDetail: 'projectConfiguration',
      upstreamReason: 'SERVICE_DISABLED',
      retryAfterMs: 60000,
      hasActionUrl: true,
      sessionId: 'session-failed',
    );

    expect(transport.events, hasLength(1));
    final event = transport.events.single;
    expect(event.name, 'proxy_request_failed');
    expect(
      event.properties,
      containsPair('model_family', KickAnalytics.modelFamily('gemini-2.5-flash')),
    );
    expect(event.properties, containsPair('error_detail', 'projectConfiguration'));
    expect(event.properties, containsPair('error_source', 'upstream'));
    expect(event.properties, containsPair('upstream_reason', 'SERVICE_DISABLED'));
    expect(event.properties, containsPair('retry_after_ms', 60000));
    expect(event.properties, containsPair('has_action_url', true));
    expect(event.properties, containsPair('session_id', 'session-failed'));
    expect(event.properties, containsPair('stream', true));
  });

  test('throttles noisy request events and reports drop counts', () async {
    final transport = _RecordingAnalyticsTransport();
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
      transport: transport,
      trackingAllowed: true,
      requestEventCapPerSession: 2,
    );

    Future<void> trackFailed() async {
      await analytics.trackProxyRequestFailed(
        route: '/v1/chat/completions',
        model: 'gemini-3.1-pro-preview',
        stream: false,
        errorKind: 'serviceUnavailable',
      );
    }

    await trackFailed();
    await trackFailed();
    await trackFailed();
    await trackFailed();

    expect(transport.events, hasLength(2));
    expect(analytics.droppedEventsFor(KickAnalyticsEvents.proxyRequestFailed), 2);

    analytics.resetSessionThrottle();
    await trackFailed();
    expect(transport.events, hasLength(3));
    expect(analytics.droppedEventsFor(KickAnalyticsEvents.proxyRequestFailed), 0);
  });

  test('tracks proxy session summaries with schema version and aggregates', () async {
    final transport = _RecordingAnalyticsTransport();
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
      transport: transport,
      trackingAllowed: true,
    );

    await analytics.trackProxySessionSummary(
      uptimeSec: 321,
      requestCount: 12,
      successCount: 10,
      failedCount: 2,
      retriedCount: 3,
      activeAccounts: 4,
      healthyAccounts: 3,
      requestMaxRetries: 8,
      mark429AsUnhealthy: true,
      androidBackgroundRuntime: true,
      stopReason: 'stopped',
      sessionId: 'session-2',
      failedDropped: 5,
      retriedDropped: 1,
      latencyP50Ms: 480,
      latencyP95Ms: 1200,
      latencyMaxMs: 4500,
      routesSeen: <String>['/v1/chat/completions', '/v1/responses', '/v1/responses'],
      modelFamiliesSeen: <String>['gemini-3', 'kiro-claude-opus-4.7'],
    );

    expect(transport.events, hasLength(1));
    final event = transport.events.single;
    expect(event.name, 'proxy_session_summary');
    expect(
      event.properties,
      containsPair('schema_version', kickAnalyticsSessionSummarySchemaVersion),
    );
    expect(event.properties, containsPair('uptime_sec', 321));
    expect(event.properties, containsPair('healthy_accounts', 3));
    expect(event.properties, containsPair('mark_429_as_unhealthy', true));
    expect(event.properties, containsPair('android_background_runtime', true));
    expect(event.properties, containsPair('stop_reason', 'stopped'));
    expect(event.properties, containsPair('session_id', 'session-2'));
    expect(event.properties, containsPair('failed_dropped', 5));
    expect(event.properties, containsPair('retried_dropped', 1));
    expect(event.properties, containsPair('latency_p50_ms', 480));
    expect(event.properties, containsPair('latency_p95_ms', 1200));
    expect(event.properties, containsPair('latency_max_ms', 4500));
    expect(event.properties['routes_seen'], equals('/v1/chat/completions,/v1/responses'));
    expect(event.properties['model_families_seen'], equals('gemini-3,kiro-claude-opus-4.7'));
  });

  test('tracks upstream compatibility issues without leaking raw model ids', () async {
    final transport = _RecordingAnalyticsTransport();
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
      transport: transport,
      trackingAllowed: true,
    );

    await analytics.trackUpstreamCompatibilityIssue(
      issueKind: 'unsupported_model',
      route: '/v1/responses',
      model: 'my-private-model-id',
      stream: true,
      errorKind: 'unsupportedModel',
      statusCode: 400,
      errorDetail: 'projectIdMissing',
      upstreamReason: 'CONSUMER_INVALID',
      retryAfterMs: 15000,
      hasActionUrl: true,
    );

    expect(transport.events, hasLength(1));
    final event = transport.events.single;
    expect(event.name, 'upstream_compatibility_issue');
    expect(event.properties, containsPair('issue_kind', 'unsupported_model'));
    expect(event.properties, containsPair('model_family', 'custom'));
    expect(event.properties, containsPair('stream', true));
    expect(event.properties, containsPair('status_code', 400));
    expect(event.properties, containsPair('error_detail', 'projectIdMissing'));
    expect(event.properties, containsPair('upstream_reason', 'CONSUMER_INVALID'));
    expect(event.properties, containsPair('retry_after_ms', 15000));
    expect(event.properties, containsPair('has_action_url', true));
  });

  test('tracks new feature events with stable shapes', () async {
    final transport = _RecordingAnalyticsTransport();
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
      transport: transport,
      trackingAllowed: true,
    );

    await analytics.trackUpdateCheckCompleted(hasUpdate: true, installerAvailable: true);
    await analytics.trackUpdateDownloadCompleted(
      checksumVerified: true,
      succeeded: true,
      sizeBytes: 32 * 1024 * 1024,
      durationMs: 2700,
    );
    await analytics.trackUpdateInstallLaunched(permissionRequired: false);
    await analytics.trackBackupExported(encrypted: true, accountCount: 4, accountsWithTokens: 3);
    await analytics.trackBackupRestored(
      wasPasswordProtected: false,
      accountCount: 2,
      accountsWithoutTokens: 1,
    );
    await analytics.trackSillyTavernPushSucceeded();
    await analytics.trackSillyTavernPushFailed(failureKind: 'httpError', statusCode: 500);
    await analytics.trackLogsExported(target: 'share', entryCount: 250);
    await analytics.trackAccountStateChanged(
      action: 'disabled',
      provider: 'kiro',
      enabledAccounts: 0,
      totalAccounts: 1,
    );

    final names = transport.events.map((event) => event.name).toList(growable: false);
    expect(names, <String>[
      KickAnalyticsEvents.updateCheckCompleted,
      KickAnalyticsEvents.updateDownloadCompleted,
      KickAnalyticsEvents.updateInstallLaunched,
      KickAnalyticsEvents.backupExported,
      KickAnalyticsEvents.backupRestored,
      KickAnalyticsEvents.sillyTavernPushSucceeded,
      KickAnalyticsEvents.sillyTavernPushFailed,
      KickAnalyticsEvents.logsExported,
      KickAnalyticsEvents.accountStateChanged,
    ]);
    expect(transport.events[1].properties, containsPair('size_mb', 32));
    expect(transport.events[7].properties, containsPair('entry_count', 250));
  });

  test('analytics swallows transport failures and retries later', () async {
    final transport = _FlakyAnalyticsTransport(remainingInitializationFailures: 1);
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
      transport: transport,
      trackingAllowed: true,
    );

    await expectLater(analytics.trackAppOpen(), completes);
    expect(transport.events, isEmpty);

    await expectLater(analytics.trackAppOpen(), completes);
    expect(transport.initializationAttempts, 2);
    expect(transport.events, hasLength(1));
    expect(transport.events.single.name, 'app_open');
  });

  test('first successful request is retried after transient analytics failure', () async {
    final transport = _FlakyAnalyticsTransport(remainingInitializationFailures: 1);
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
      transport: transport,
      trackingAllowed: true,
    );

    await expectLater(
      analytics.trackFirstSuccessfulRequest(
        route: '/v1/chat/completions',
        model: 'gemini-3.1-pro-preview',
        stream: true,
      ),
      completes,
    );
    expect(transport.events, isEmpty);

    await expectLater(
      analytics.trackFirstSuccessfulRequest(
        route: '/v1/chat/completions',
        model: 'gemini-3.1-pro-preview',
        stream: true,
      ),
      completes,
    );
    await expectLater(
      analytics.trackFirstSuccessfulRequest(
        route: '/v1/chat/completions',
        model: 'gemini-3.1-pro-preview',
        stream: true,
      ),
      completes,
    );

    expect(transport.initializationAttempts, 2);
    expect(transport.events, hasLength(1));
    expect(transport.events.single.name, 'first_successful_request');
  });

  test('revoking consent emits a final marker and clears the queue', () async {
    final transport = _RecordingAnalyticsTransport();
    final analytics = KickAnalytics(
      config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
      transport: transport,
      trackingAllowed: true,
    );

    await analytics.trackAppOpen();
    expect(transport.events.map((event) => event.name), <String>['app_open']);

    await analytics.setTrackingAllowed(false);
    expect(transport.events.map((event) => event.name), <String>[
      'app_open',
      KickAnalyticsEvents.analyticsConsentRevoked,
    ]);
    expect(transport.queueCleared, isTrue);

    await analytics.trackAppOpen();
    expect(
      transport.events.length,
      2,
      reason: 'Tracking should remain disabled until consent is granted again.',
    );
  });

  test('aptabase transport retries initialization after transient failure', () async {
    var initializationAttempts = 0;
    final transport = AptabaseAnalyticsTransport(
      storageFactory: () async => _NoOpStorageManager(),
      initializer: (config, storage) async {
        initializationAttempts += 1;
        if (initializationAttempts == 1) {
          throw StateError('lock failed');
        }
      },
    );
    const config = AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test');

    await expectLater(transport.ensureInitialized(config), throwsStateError);
    await expectLater(transport.ensureInitialized(config), completes);

    expect(initializationAttempts, 2);
  });

  test('windows analytics storage falls back to in-memory queue', () async {
    var supportDirectoryRequested = false;
    final storage = createDefaultAnalyticsStorage(
      isWindows: true,
      supportDirectoryProvider: () async {
        supportDirectoryRequested = true;
        throw StateError('filesystem should not be used on Windows fallback');
      },
    );

    await storage.init();
    await storage.add('first');
    await storage.add('second');

    final items = (await storage.getItems(10)).toList(growable: false);
    expect(supportDirectoryRequested, isFalse);
    expect(items.map((entry) => entry.value), <String>['first', 'second']);

    await storage.deleteAllKeys(<dynamic>[items.first.key]);

    final remainingItems = (await storage.getItems(10)).toList(growable: false);
    expect(remainingItems.map((entry) => entry.value), <String>['second']);
  });
}

class _RecordingAnalyticsTransport extends AnalyticsTransport {
  final List<_RecordedAnalyticsEvent> events = <_RecordedAnalyticsEvent>[];
  bool queueCleared = false;

  @override
  Future<void> ensureInitialized(AnalyticsBuildConfig config) async {}

  @override
  Future<void> track(String eventName, Map<String, Object?> properties) async {
    events.add(_RecordedAnalyticsEvent(name: eventName, properties: properties));
  }

  @override
  Future<void> clearQueue() async {
    queueCleared = true;
  }
}

class _RecordedAnalyticsEvent {
  const _RecordedAnalyticsEvent({required this.name, required this.properties});

  final String name;
  final Map<String, Object?> properties;
}

class _FlakyAnalyticsTransport extends AnalyticsTransport {
  _FlakyAnalyticsTransport({required this.remainingInitializationFailures});

  final List<_RecordedAnalyticsEvent> events = <_RecordedAnalyticsEvent>[];
  int remainingInitializationFailures;
  int initializationAttempts = 0;

  @override
  Future<void> ensureInitialized(AnalyticsBuildConfig config) async {
    initializationAttempts += 1;
    if (remainingInitializationFailures > 0) {
      remainingInitializationFailures -= 1;
      throw StateError('lock failed');
    }
  }

  @override
  Future<void> track(String eventName, Map<String, Object?> properties) async {
    events.add(_RecordedAnalyticsEvent(name: eventName, properties: properties));
  }
}

class _NoOpStorageManager implements StorageManager {
  @override
  Future<void> add(String item) async {}

  @override
  Future<void> deleteAllKeys(Iterable<dynamic> keys) async {}

  @override
  Future<Iterable<MapEntry<dynamic, String>>> getItems(int length) async {
    return const <MapEntry<dynamic, String>>[];
  }

  @override
  Future<void> init() async {}
}
