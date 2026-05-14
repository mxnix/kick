import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kick/proxy/kiro/kiro_ide_runtime_version.dart';

void main() {
  setUp(resetKiroIdeRuntimeVersionForTesting);
  tearDown(resetKiroIdeRuntimeVersionForTesting);

  test('falls back to the pinned version when the probe is not run', () {
    expect(kiroIdeRuntimeVersion, fallbackKiroIdeVersion);
  });

  test('refresh updates the runtime version on a successful response', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'prod.download.desktop.kiro.dev');
      return http.Response(
        jsonEncode({'currentRelease': '0.13.42'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await refreshKiroIdeRuntimeVersion(httpClient: client, force: true);

    expect(kiroIdeRuntimeVersion, '0.13.42');
  });

  test('refresh keeps fallback when probe fails with non-200 status', () async {
    final client = MockClient((request) async => http.Response('boom', 503));

    await refreshKiroIdeRuntimeVersion(httpClient: client, force: true);

    expect(kiroIdeRuntimeVersion, fallbackKiroIdeVersion);
  });

  test('refresh keeps previous value when payload is malformed', () async {
    final firstClient = MockClient((request) async {
      return http.Response(jsonEncode({'currentRelease': '0.99.0'}), 200);
    });
    await refreshKiroIdeRuntimeVersion(httpClient: firstClient, force: true);
    expect(kiroIdeRuntimeVersion, '0.99.0');

    final brokenClient = MockClient((request) async {
      return http.Response('not-json', 200);
    });

    await refreshKiroIdeRuntimeVersion(httpClient: brokenClient, force: true);

    expect(kiroIdeRuntimeVersion, '0.99.0');
  });

  test('refresh throttles within the configured min interval', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      return http.Response(jsonEncode({'currentRelease': '0.50.0'}), 200);
    });

    await refreshKiroIdeRuntimeVersion(httpClient: client, force: true);
    await refreshKiroIdeRuntimeVersion(httpClient: client);
    await refreshKiroIdeRuntimeVersion(httpClient: client, minInterval: const Duration(hours: 12));

    expect(calls, 1);
    expect(kiroIdeRuntimeVersion, '0.50.0');
  });
}
