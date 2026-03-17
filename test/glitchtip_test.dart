import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/models/app_log_entry.dart';
import 'package:kick/observability/glitchtip.dart';

void main() {
  test('release config defaults to release environment and clamps sample rate', () {
    final config = GlitchTipBuildConfig.resolve(
      isReleaseMode: true,
      dsn: 'https://public@example.com/1',
      tracesSampleRate: '2.5',
    );

    expect(config.buildChannel, 'release');
    expect(config.environment, 'release');
    expect(config.release, startsWith('kick@'));
    expect(config.tracesSampleRate, 1.0);
    expect(config.isEnabled, isTrue);
  });

  test('debug config stays disabled without a dsn', () {
    final config = GlitchTipBuildConfig.resolve(
      isReleaseMode: false,
      dsn: '   ',
      environment: 'local-debug',
      tracesSampleRate: 'oops',
    );

    expect(config.buildChannel, 'debug');
    expect(config.environment, 'local-debug');
    expect(config.tracesSampleRate, 0.0);
    expect(config.isEnabled, isFalse);
  });

  test('captures only selected proxy error logs', () {
    final reportable = AppLogEntry(
      id: '1',
      timestamp: DateTime(2026, 3, 17),
      level: AppLogLevel.error,
      category: 'responses',
      route: '/v1/responses',
      message: 'Request failed',
      maskedPayload: '{"request_id":"abc"}',
    );
    final ignored = AppLogEntry(
      id: '2',
      timestamp: DateTime(2026, 3, 17),
      level: AppLogLevel.warning,
      category: 'responses',
      route: '/v1/responses',
      message: 'Request succeeded after retries',
      maskedPayload: '{"request_id":"abc"}',
    );

    expect(shouldCaptureGlitchTipProxyLog(reportable), isTrue);
    expect(shouldCaptureGlitchTipProxyLog(ignored), isFalse);
    expect(glitchTipProxyLogEventMessage(reportable), 'Gemini responses request failed');
  });
}
