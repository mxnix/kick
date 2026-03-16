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
      autoCheckUpdatesEnabled: true,
      host: '127.0.0.1',
      port: 3000,
      allowLan: false,
      androidBackgroundRuntime: true,
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
    expect(KickAnalytics.modelFamily('my-private-model-id'), 'custom');
  });
}
