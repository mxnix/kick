import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kick/features/settings/app_update_checker.dart';

void main() {
  test('normalizes GitHub tags into app version format', () {
    expect(AppUpdateChecker.normalizeVersion('v0.2.1'), '0.2.1');
    expect(AppUpdateChecker.normalizeVersion('0.2.1+9'), '0.2.1');
  });

  test('compares semantic versions numerically', () {
    expect(AppUpdateChecker.compareVersions('0.2.0', '0.1.9'), greaterThan(0));
    expect(AppUpdateChecker.compareVersions('1.0.0', '1.0.0'), 0);
    expect(AppUpdateChecker.compareVersions('1.0.0-beta.1', '1.0.0'), lessThan(0));
  });

  test('detects available update from GitHub release payload', () async {
    final checker = AppUpdateChecker(
      apiUrl: 'https://example.com/releases/latest',
      httpClient: QueueHttpClient([
        (request) async {
          expect(request.url.toString(), 'https://example.com/releases/latest');
          return http.Response(
            jsonEncode({
              'tag_name': 'v0.2.0',
              'html_url': 'https://github.com/mxnix/kick/releases/tag/v0.2.0',
            }),
            200,
          );
        },
      ]),
    );

    final result = await checker.checkForUpdates(currentVersion: '0.1.0');

    expect(result.currentVersion, '0.1.0');
    expect(result.latestVersion, '0.2.0');
    expect(result.hasUpdate, isTrue);
    expect(result.releaseUrl, 'https://github.com/mxnix/kick/releases/tag/v0.2.0');
  });

  test('reports no update when installed version is current', () async {
    final checker = AppUpdateChecker(
      apiUrl: 'https://example.com/releases/latest',
      httpClient: QueueHttpClient([
        (_) async => http.Response(
          jsonEncode({
            'tag_name': 'v0.2.0',
            'html_url': 'https://github.com/mxnix/kick/releases/tag/v0.2.0',
          }),
          200,
        ),
      ]),
    );

    final result = await checker.checkForUpdates(currentVersion: '0.2.0');

    expect(result.hasUpdate, isFalse);
  });

  test('times out when the update endpoint stalls', () async {
    final checker = AppUpdateChecker(
      apiUrl: 'https://example.com/releases/latest',
      requestTimeout: const Duration(milliseconds: 10),
      httpClient: QueueHttpClient([
        (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return http.Response('{}', 200);
        },
      ]),
    );

    await expectLater(
      checker.checkForUpdates(currentVersion: '0.2.0'),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          'Checking for updates timed out.',
        ),
      ),
    );
  });
}

class QueueHttpClient extends http.BaseClient {
  QueueHttpClient(this._handlers);

  final List<Future<http.BaseResponse> Function(http.BaseRequest request)> _handlers;
  var _index = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_index >= _handlers.length) {
      throw StateError('No queued HTTP response for ${request.method} ${request.url}.');
    }

    final response = await _handlers[_index++](request);
    if (response is http.StreamedResponse) {
      return response;
    }
    if (response is http.Response) {
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
      );
    }
    throw StateError('Unsupported HTTP response type: ${response.runtimeType}.');
  }
}
