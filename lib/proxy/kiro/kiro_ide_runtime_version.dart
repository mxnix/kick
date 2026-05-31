import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Pinned fallback used when no probe has succeeded yet, when the probe fails,
/// or in tests. Kept aligned with the version embedded by the build matrix and
/// rotated by the [Sync Kiro IDE Version] CI workflow.
const String fallbackKiroIdeVersion = '0.12.263';

const Duration _kiroIdeVersionProbeMinInterval = Duration(hours: 12);
const Duration _kiroIdeVersionProbeTimeout = Duration(seconds: 6);
const String _kiroIdeStableMetadataUrl =
    'https://prod.download.desktop.kiro.dev/stable/metadata-win32-x64-user-stable.json';

String _runtimeVersion = fallbackKiroIdeVersion;
DateTime? _lastSuccessfulProbe;
Future<void>? _inFlightProbe;
KiroIdeVersionPersistedState? _cachedPersistedState;
KiroIdeVersionStateWriter? _persistedStateWriter;

String get kiroIdeRuntimeVersion => _runtimeVersion;

/// Hydrates the in-process cache from a previously persisted snapshot. Should
/// be called once during bootstrap so the first probe-call after a restart can
/// honour the 12h throttle without making a fresh network round-trip.
void hydrateKiroIdeRuntimeVersionFromCache(KiroIdeVersionPersistedState? state) {
  if (state == null) {
    return;
  }
  if (state.version.trim().isNotEmpty) {
    _runtimeVersion = state.version.trim();
  }
  _lastSuccessfulProbe = state.probedAt;
  _cachedPersistedState = state;
}

/// Wires the persistent cache I/O so the probe can write the latest
/// `(version, probedAt)` pair to durable storage on success.
void registerKiroIdeRuntimeVersionPersistence({KiroIdeVersionStateWriter? writer}) {
  _persistedStateWriter = writer;
}

void setKiroIdeRuntimeVersionForTesting(String value) {
  final trimmed = value.trim();
  _runtimeVersion = trimmed.isEmpty ? fallbackKiroIdeVersion : trimmed;
}

void resetKiroIdeRuntimeVersionForTesting() {
  _runtimeVersion = fallbackKiroIdeVersion;
  _lastSuccessfulProbe = null;
  _inFlightProbe = null;
  _cachedPersistedState = null;
  _persistedStateWriter = null;
}

/// Returns true when [refreshKiroIdeRuntimeVersion] would otherwise short
/// circuit because the previous successful probe is still within
/// [minInterval]. Lets the bootstrap decide upfront whether to spend a future
/// on the network at all.
bool shouldSkipKiroIdeRuntimeVersionProbe({
  Duration minInterval = _kiroIdeVersionProbeMinInterval,
}) {
  final last = _lastSuccessfulProbe;
  if (last == null) {
    return false;
  }
  return DateTime.now().difference(last) < minInterval;
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
    final state = KiroIdeVersionPersistedState(version: trimmed, probedAt: _lastSuccessfulProbe!);
    if (_cachedPersistedState != state) {
      _cachedPersistedState = state;
      final writer = _persistedStateWriter;
      if (writer != null) {
        unawaited(
          Future<void>.sync(() => writer(state)).catchError((_) {
            // Persistence is best-effort; keep the in-memory cache regardless.
          }),
        );
      }
    }
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

typedef KiroIdeVersionStateReader = Future<KiroIdeVersionPersistedState?> Function();
typedef KiroIdeVersionStateWriter = Future<void> Function(KiroIdeVersionPersistedState state);

/// Snapshot persisted between runs so the 12h probe throttle survives
/// process restarts. The serialized form is `version|iso8601` text — kept
/// trivial so callers can drop it straight into the existing key/value
/// settings table without an extra schema migration.
class KiroIdeVersionPersistedState {
  const KiroIdeVersionPersistedState({required this.version, required this.probedAt});

  final String version;
  final DateTime probedAt;

  String encode() {
    final trimmed = version.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return '$trimmed|${probedAt.toUtc().toIso8601String()}';
  }

  static KiroIdeVersionPersistedState? tryDecode(String? raw) {
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final separator = trimmed.indexOf('|');
    if (separator <= 0 || separator == trimmed.length - 1) {
      return null;
    }
    final version = trimmed.substring(0, separator).trim();
    final timestamp = DateTime.tryParse(trimmed.substring(separator + 1).trim());
    if (version.isEmpty || timestamp == null) {
      return null;
    }
    return KiroIdeVersionPersistedState(version: version, probedAt: timestamp);
  }

  @override
  bool operator ==(Object other) =>
      other is KiroIdeVersionPersistedState &&
      other.version == version &&
      other.probedAt.isAtSameMomentAs(probedAt);

  @override
  int get hashCode => Object.hash(version, probedAt.toUtc());
}
