import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/models/app_settings.dart';

void main() {
  test('defaults disable analytics consent and require disclaimer acknowledgement', () {
    final settings = AppSettings.defaults(apiKey: 'kick_test');

    expect(settings.analyticsConsentEnabled, isFalse);
    expect(settings.autoCheckUpdatesEnabled, isTrue);
    expect(settings.hasAcknowledgedDisclaimer, isFalse);
    expect(settings.requestMaxRetries, 10);
    expect(settings.mark429AsUnhealthy, isFalse);
    expect(settings.apiKeyRequired, isTrue);
  });

  test('round-trips disclaimer fields through storage map', () {
    const settings = AppSettings(
      apiKey: 'kick_test',
      apiKeyRequired: false,
      themeMode: ThemeMode.dark,
      useDynamicColor: false,
      hasAcknowledgedDisclaimer: true,
      analyticsConsentEnabled: false,
      autoCheckUpdatesEnabled: false,
      host: '0.0.0.0',
      port: 8080,
      allowLan: true,
      androidBackgroundRuntime: false,
      requestMaxRetries: 7,
      mark429AsUnhealthy: true,
      loggingVerbosity: KickLogVerbosity.verbose,
      unsafeRawLoggingEnabled: true,
      customModels: ['gemini-2.5-flash'],
    );

    final restored = AppSettings.fromStorageMap(settings.toStorageMap(), apiKey: settings.apiKey);

    expect(restored.hasAcknowledgedDisclaimer, isTrue);
    expect(restored.analyticsConsentEnabled, isFalse);
    expect(restored.autoCheckUpdatesEnabled, isFalse);
    expect(restored.apiKeyRequired, isFalse);
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.allowLan, isTrue);
    expect(restored.requestMaxRetries, 7);
    expect(restored.mark429AsUnhealthy, isTrue);
    expect(restored.unsafeRawLoggingEnabled, isTrue);
    expect(restored.customModels, ['gemini-2.5-flash']);
  });

  test('normalizes wildcard host back to loopback when LAN is disabled', () {
    final restored = AppSettings.fromStorageMap({
      'host': '0.0.0.0',
      'allow_lan': 'false',
    }, apiKey: 'kick_test');

    expect(restored.host, '127.0.0.1');
    expect(restored.allowLan, isFalse);
  });
}
