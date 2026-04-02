import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/analytics/android_background_session_log.dart';
import 'package:kick/analytics/android_background_session_tracker.dart';
import 'package:kick/analytics/kick_analytics.dart';
import 'package:kick/data/app_database.dart';
import 'package:kick/data/repositories/logs_repository.dart';

void main() {
  test('tracks Android background sessions that return to the app', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureSchema();

    var now = DateTime.utc(2026, 3, 17, 12, 0, 0);
    final transport = _RecordingAnalyticsTransport();
    final tracker = AndroidBackgroundSessionTracker(
      logsRepository: LogsRepository(database),
      analytics: KickAnalytics(
        config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
        transport: transport,
        trackingAllowed: true,
      ),
      now: () => now,
      createId: () => 'session-1',
    );

    await tracker.onBackgrounded(androidBackgroundRuntimeEnabled: true, proxyWasRunning: true);
    now = now.add(const Duration(seconds: 95));
    await tracker.onResumed(androidBackgroundRuntimeEnabled: true, proxyWasRunning: true);

    final logs = await LogsRepository(database).readAll(limit: 10);
    expect(logs.map((entry) => entry.message), contains(androidBackgroundSessionStartedMessage));
    expect(logs.map((entry) => entry.message), contains(androidBackgroundSessionEndedMessage));
    expect(transport.events, hasLength(1));
    expect(transport.events.single.name, 'android_background_session');
    expect(transport.events.single.properties, containsPair('duration_sec', 95));
    expect(transport.events.single.properties, containsPair('killed_in_background', 0));
    expect(
      transport.events.single.properties,
      containsPair('android_background_runtime_enabled', 1),
    );
  });

  test('recovers background sessions after process restart', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.ensureSchema();

    var now = DateTime.utc(2026, 3, 17, 12, 0, 0);
    final logsRepository = LogsRepository(database);
    final seedTracker = AndroidBackgroundSessionTracker(
      logsRepository: logsRepository,
      analytics: KickAnalytics(
        config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: ''),
        transport: const NoOpAnalyticsTransport(),
      ),
      now: () => now,
      createId: () => 'session-open',
    );
    await seedTracker.onBackgrounded(androidBackgroundRuntimeEnabled: false, proxyWasRunning: true);

    now = now.add(const Duration(minutes: 4));
    final transport = _RecordingAnalyticsTransport();
    final tracker = AndroidBackgroundSessionTracker(
      logsRepository: logsRepository,
      analytics: KickAnalytics(
        config: const AnalyticsBuildConfig(buildChannel: 'test', appKey: 'A-EU-test'),
        transport: transport,
        trackingAllowed: true,
      ),
      now: () => now,
      createId: () => 'session-recovered',
    );

    await tracker.recoverIfNeeded();

    final logs = await logsRepository.readAll(limit: 10);
    expect(logs.map((entry) => entry.message), contains(androidBackgroundSessionRecoveredMessage));
    expect(transport.events, hasLength(1));
    expect(transport.events.single.name, 'android_background_session');
    expect(transport.events.single.properties, containsPair('duration_sec', 240));
    expect(transport.events.single.properties, containsPair('killed_in_background', 1));
    expect(transport.events.single.properties, containsPair('proxy_was_running', 1));
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
