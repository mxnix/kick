import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/models/app_settings.dart';

void main() {
  test('defaults disable analytics consent and require disclaimer acknowledgement', () {
    final settings = AppSettings.defaults(apiKey: 'kick_test');

    expect(settings.analyticsConsentEnabled, isFalse);
    expect(settings.hasAcknowledgedDisclaimer, isFalse);
    expect(settings.requestMaxRetries, 10);
    expect(settings.retry429DelaySeconds, 30);
    expect(settings.mark429AsUnhealthy, isFalse);
    expect(settings.apiKeyRequired, isTrue);
    expect(settings.defaultGoogleWebSearchEnabled, isFalse);
    expect(settings.renderGoogleGroundingInMessage, isFalse);
    expect(settings.logRetentionCount, defaultLogRetentionCount);
  });

  test('round-trips disclaimer fields through storage map', () {
    const settings = AppSettings(
      apiKey: 'kick_test',
      apiKeyRequired: false,
      themeMode: ThemeMode.dark,
      useDynamicColor: false,
      hasAcknowledgedDisclaimer: true,
      analyticsConsentEnabled: false,
      host: '0.0.0.0',
      port: 8080,
      allowLan: true,
      androidBackgroundRuntime: false,
      windowsLaunchAtStartup: true,
      requestMaxRetries: 7,
      retry429DelaySeconds: 45,
      mark429AsUnhealthy: true,
      defaultGoogleWebSearchEnabled: true,
      renderGoogleGroundingInMessage: true,
      loggingVerbosity: KickLogVerbosity.verbose,
      logRetentionCount: 2400,
      unsafeRawLoggingEnabled: true,
      customModels: ['gemini-2.5-flash'],
    );

    final restored = AppSettings.fromStorageMap(settings.toStorageMap(), apiKey: settings.apiKey);

    expect(restored.hasAcknowledgedDisclaimer, isTrue);
    expect(restored.analyticsConsentEnabled, isFalse);
    expect(restored.apiKeyRequired, isFalse);
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.allowLan, isTrue);
    expect(restored.requestMaxRetries, 7);
    expect(restored.retry429DelaySeconds, 45);
    expect(restored.mark429AsUnhealthy, isTrue);
    expect(restored.defaultGoogleWebSearchEnabled, isTrue);
    expect(restored.renderGoogleGroundingInMessage, isTrue);
    expect(restored.windowsLaunchAtStartup, isTrue);
    expect(restored.logRetentionCount, 2400);
    expect(restored.unsafeRawLoggingEnabled, isTrue);
    expect(restored.customModels, ['gemini-2.5-flash']);
  });

  test('round-trips settings through backup json', () {
    const settings = AppSettings(
      apiKey: 'kick_backup',
      apiKeyRequired: false,
      themeMode: ThemeMode.dark,
      useDynamicColor: false,
      hasAcknowledgedDisclaimer: true,
      analyticsConsentEnabled: true,
      host: '192.168.1.10',
      port: 4010,
      allowLan: true,
      androidBackgroundRuntime: false,
      windowsLaunchAtStartup: true,
      requestMaxRetries: 6,
      retry429DelaySeconds: 90,
      mark429AsUnhealthy: true,
      defaultGoogleWebSearchEnabled: true,
      renderGoogleGroundingInMessage: true,
      loggingVerbosity: KickLogVerbosity.verbose,
      logRetentionCount: 1200,
      unsafeRawLoggingEnabled: true,
      customModels: ['gemini-2.5-flash', 'gemini-2.5-pro'],
    );

    final restored = AppSettings.fromBackupJson(settings.toBackupJson());

    expect(restored.apiKey, 'kick_backup');
    expect(restored.analyticsConsentEnabled, isTrue);
    expect(restored.host, '192.168.1.10');
    expect(restored.port, 4010);
    expect(restored.customModels, ['gemini-2.5-flash', 'gemini-2.5-pro']);
    expect(restored.loggingVerbosity, KickLogVerbosity.verbose);
  });

  test('normalizes wildcard host back to loopback when LAN is disabled', () {
    final restored = AppSettings.fromStorageMap({
      'host': '0.0.0.0',
      'allow_lan': 'false',
    }, apiKey: 'kick_test');

    expect(restored.host, '127.0.0.1');
    expect(restored.allowLan, isFalse);
  });

  test('keeps analytics consent disabled when legacy settings are missing the key', () {
    final restored = AppSettings.fromStorageMap({
      'has_acknowledged_disclaimer': 'false',
    }, apiKey: 'kick_test');

    expect(restored.analyticsConsentEnabled, isFalse);
  });
}
