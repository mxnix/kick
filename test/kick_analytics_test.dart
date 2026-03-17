import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/kick_analytics.dart';
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
      useDynamicColor: true,
      hasAcknowledgedDisclaimer: false,
      analyticsConsentEnabled: false,
      host: '127.0.0.1',
      port: 3000,
      allowLan: false,
      androidBackgroundRuntime: true,
      windowsLaunchAtStartup: false,
      requestMaxRetries: 10,
      mark429AsUnhealthy: false,
      loggingVerbosity: KickLogVerbosity.normal,
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

  test('model family buckets custom models without leaking exact ids', () {
    expect(KickAnalytics.modelFamily('gemini-2.5-pro-preview'), 'gemini-2.5-pro');
    expect(KickAnalytics.modelFamily('gemini-3-flash'), 'gemini-3');
    expect(KickAnalytics.modelFamily('gemini-3.1-pro-preview'), 'gemini-3');
    expect(KickAnalytics.modelFamily('my-private-model-id'), 'custom');
  });

  test('tracks retried requests as aggregated analytics events', () async {
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
    );

    expect(transport.events, hasLength(1));
    expect(transport.events.single.name, 'proxy_request_retried');
    expect(
      transport.events.single.properties,
      containsPair('model_family', KickAnalytics.modelFamily('gemini-3.1-pro-preview')),
    );
    expect(transport.events.single.properties, containsPair('retry_count', 2));
    expect(transport.events.single.properties, containsPair('upstream_retry_count', 1));
    expect(transport.events.single.properties, containsPair('account_failover_count', 1));
    expect(transport.events.single.properties, containsPair('retry_kinds', 'quota,capacity'));
    expect(transport.events.single.properties, containsPair('retry_delay_ms', 49000));
    expect(transport.events.single.properties, containsPair('status_code', 429));
    expect(transport.events.single.properties, containsPair('build_channel', 'test'));
  });

  test('tracks proxy session summaries with runtime configuration', () async {
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
    );

    expect(transport.events, hasLength(1));
    expect(transport.events.single.name, 'proxy_session_summary');
    expect(transport.events.single.properties, containsPair('uptime_sec', 321));
    expect(transport.events.single.properties, containsPair('healthy_accounts', 3));
    expect(transport.events.single.properties, containsPair('mark_429_as_unhealthy', 1));
    expect(transport.events.single.properties, containsPair('android_background_runtime', 1));
    expect(transport.events.single.properties, containsPair('stop_reason', 'stopped'));
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
    );

    expect(transport.events, hasLength(1));
    expect(transport.events.single.name, 'upstream_compatibility_issue');
    expect(transport.events.single.properties, containsPair('issue_kind', 'unsupported_model'));
    expect(transport.events.single.properties, containsPair('model_family', 'custom'));
    expect(transport.events.single.properties, containsPair('stream', 1));
    expect(transport.events.single.properties, containsPair('status_code', 400));
  });
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
