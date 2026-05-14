import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Pinned fallback used when no probe has succeeded yet, when the probe fails,
/// or in tests. Kept aligned with the version embedded by the build matrix and
/// rotated by the [Sync Kiro IDE Version] CI workflow.
const String fallbackKiroIdeVersion = '0.12.184';

const Duration _kiroIdeVersionProbeMinInterval = Duration(hours: 12);
const Duration _kiroIdeVersionProbeTimeout = Duration(seconds: 6);
const String _kiroIdeStableMetadataUrl =
    'https://prod.download.desktop.kiro.dev/stable/metadata-win32-x64-user-stable.json';

String _runtimeVersion = fallbackKiroIdeVersion;
DateTime? _lastSuccessfulProbe;
Future<void>? _inFlightProbe;

String get kiroIdeRuntimeVersion => _runtimeVersion;

void setKiroIdeRuntimeVersionForTesting(String value) {
  final trimmed = value.trim();
  _runtimeVersion = trimmed.isEmpty ? fallbackKiroIdeVersion : trimmed;
}

void resetKiroIdeRuntimeVersionForTesting() {
  _runtimeVersion = fallbackKiroIdeVersion;
  _lastSuccessfulProbe = null;
  _inFlightProbe = null;
}

/// Fetches the latest Kiro IDE stable release version, applying it as the
/// in-process default for outbound user agent strings. Failures are swallowed
/// silently; the previously known version remains in effect.
Future<void> refreshKiroIdeRuntimeVersion({
  http.Client? httpClient,
  Duration minInterval = _kiroIdeVersionProbeMinInterval,
  bool force = false,
}) {
  final inFlight = _inFlightProbe;
  if (inFlight != null) {
    return inFlight;
  }
  if (!force) {
    final last = _lastSuccessfulProbe;
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return Future.value();
    }
  }

  final probe = _probe(httpClient: httpClient);
  _inFlightProbe = probe;
  return probe.whenComplete(() {
    _inFlightProbe = null;
  });
}

Future<void> _probe({http.Client? httpClient}) async {
  final ownsClient = httpClient == null;
  final client = httpClient ?? http.Client();
  try {
    final response = await client
        .get(
          Uri.parse(_kiroIdeStableMetadataUrl),
          headers: <String, String>{
            HttpHeaders.userAgentHeader: 'KiCk-KiroVersionProbe',
            HttpHeaders.acceptHeader: 'application/json',
          },
        )
        .timeout(_kiroIdeVersionProbeTimeout);
    if (response.statusCode >= 400) {
      return;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      return;
    }
    final candidate = decoded['currentRelease'];
    if (candidate is! String) {
      return;
    }
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _runtimeVersion = trimmed;
    _lastSuccessfulProbe = DateTime.now();
  } on TimeoutException {
    // Silent fallback: keep current value.
  } on http.ClientException {
    // Silent fallback.
  } on FormatException {
    // Silent fallback (malformed JSON).
  } on SocketException {
    // Silent fallback (offline).
  } finally {
    if (ownsClient) {
      client.close();
    }
  }
}
