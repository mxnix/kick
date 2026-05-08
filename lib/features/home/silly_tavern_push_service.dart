import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class SillyTavernPushService {
  SillyTavernPushService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final _CookieJar _cookies = _CookieJar();
  final _uuid = const Uuid();

  Future<SillyTavernPushResult> pushProfile({
    required String sillyTavernUrl,
    required String proxyEndpoint,
    required String apiKey,
    required String profileName,
    required String model,
  }) async {
    final baseUri = _normalizeBaseUri(sillyTavernUrl);
    final csrf = await _fetchCsrfToken(baseUri);

    final secretId = await _writeSecret(baseUri, csrfToken: csrf, apiKey: apiKey);
    final settings = await _readSettings(baseUri, csrfToken: csrf);
    final profileId = _upsertConnectionProfile(
      settings,
      profileName: profileName,
      proxyEndpoint: proxyEndpoint,
      model: model,
      secretId: secretId,
    );
    await _saveSettings(baseUri, csrfToken: csrf, settings: settings);

    return SillyTavernPushResult(profileId: profileId, profileName: profileName);
  }

  void dispose() {
    _client.close();
  }

  Future<String> _fetchCsrfToken(Uri baseUri) async {
    final response = await _send(baseUri, 'GET', '/csrf-token');
    final payload = _decodeJsonObject(response.body);
    final token = _readFirstString(payload, const ['token', 'csrfToken', '_csrf']);
    if (token == null) {
      throw const SillyTavernPushException(SillyTavernPushFailure.missingCsrfToken);
    }
    return token;
  }

  Future<String> _writeSecret(
    Uri baseUri, {
    required String csrfToken,
    required String apiKey,
  }) async {
    final response = await _sendJson(
      baseUri,
      '/api/secrets/write',
      csrfToken: csrfToken,
      body: {'key': 'api_key_custom', 'value': apiKey},
    );
    final payload = _tryDecodeJsonObject(response.body);
    return _readFirstString(payload, const ['id', 'key']) ?? 'api_key_custom';
  }

  Future<Map<String, Object?>> _readSettings(Uri baseUri, {required String csrfToken}) async {
    final response = await _sendJson(
      baseUri,
      '/api/settings/get',
      csrfToken: csrfToken,
      body: const <String, Object?>{},
    );
    final payload = _decodeJsonObject(response.body);
    final settingsValue = payload['settings'];
    if (settingsValue is String) {
      return _decodeJsonObject(settingsValue);
    }
    if (settingsValue is Map) {
      return settingsValue.map((key, value) => MapEntry(key.toString(), value));
    }
    return payload;
  }

  Future<void> _saveSettings(
    Uri baseUri, {
    required String csrfToken,
    required Map<String, Object?> settings,
  }) async {
    await _sendJson(baseUri, '/api/settings/save', csrfToken: csrfToken, body: settings);
  }

  String _upsertConnectionProfile(
    Map<String, Object?> settings, {
    required String profileName,
    required String proxyEndpoint,
    required String model,
    required String secretId,
  }) {
    settings['main_api'] = 'openai';
    _patchOpenAiSettings(settings, proxyEndpoint: proxyEndpoint, model: model);

    final extensionSettings = _ensureObject(settings, 'extension_settings');
    final manager = _ensureObject(extensionSettings, 'connectionManager');
    final profiles = _ensureList(manager, 'profiles');
    final existingIndex = profiles.indexWhere((item) {
      if (item is! Map) {
        return false;
      }
      return item['name'] == profileName || item['api-url'] == proxyEndpoint;
    });
    final profileId = existingIndex >= 0 && profiles[existingIndex] is Map
        ? ((profiles[existingIndex] as Map)['id']?.toString() ?? _uuid.v4())
        : _uuid.v4();
    final profile = <String, Object?>{
      'id': profileId,
      'name': profileName,
      'mode': 'cc',
      'api': 'custom',
      'api-url': proxyEndpoint,
      'model': model,
      'secret-id': secretId,
      'prompt-post-processing': 'merge',
      'exclude': const <String>[],
    };

    if (existingIndex >= 0) {
      profiles[existingIndex] = profile;
    } else {
      profiles.add(profile);
    }
    manager['selectedProfile'] = profileId;
    return profileId;
  }

  void _patchOpenAiSettings(
    Map<String, Object?> settings, {
    required String proxyEndpoint,
    required String model,
  }) {
    final candidates = <Map<String, Object?>>[
      settings,
      if (settings['oai_settings'] is Map)
        (settings['oai_settings'] as Map).map((key, value) => MapEntry(key.toString(), value)),
      if (settings['openai_settings'] is Map)
        (settings['openai_settings'] as Map).map((key, value) => MapEntry(key.toString(), value)),
    ];

    for (final target in candidates) {
      target['chat_completion_source'] = 'custom';
      target['custom_url'] = proxyEndpoint;
      target['custom_model'] = model;
      target['bypass_status_check'] = true;
      target['custom_prompt_post_processing'] ??= 'merge';
    }

    if (settings['oai_settings'] is Map) {
      settings['oai_settings'] = candidates[1];
    }
    if (settings['openai_settings'] is Map) {
      settings['openai_settings'] = candidates.last;
    }
  }

  Future<http.Response> _sendJson(
    Uri baseUri,
    String path, {
    required String csrfToken,
    required Map<String, Object?> body,
  }) {
    return _send(
      baseUri,
      'POST',
      path,
      csrfToken: csrfToken,
      body: jsonEncode(body),
      headers: const {'content-type': 'application/json'},
    );
  }

  Future<http.Response> _send(
    Uri baseUri,
    String method,
    String path, {
    String? csrfToken,
    String? body,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final request = http.Request(method, baseUri.resolve(path));
    request.headers.addAll({'accept': 'application/json', ...headers});
    final cookieHeader = _cookies.header;
    if (cookieHeader != null) {
      request.headers['cookie'] = cookieHeader;
    }
    if (csrfToken != null) {
      request.headers['x-csrf-token'] = csrfToken;
    }
    if (body != null) {
      request.body = body;
    }
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 8)),
    );
    _cookies.capture(response.headers['set-cookie']);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SillyTavernPushException(
        SillyTavernPushFailure.httpError,
        statusCode: response.statusCode,
        path: path,
      );
    }
    return response;
  }

  Uri _normalizeBaseUri(String value) {
    final trimmed = value.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme || parsed.host.trim().isEmpty) {
      throw const SillyTavernPushException(SillyTavernPushFailure.invalidUrl);
    }
    return parsed.replace(path: parsed.path.endsWith('/') ? parsed.path : '${parsed.path}/');
  }
}

class SillyTavernPushResult {
  const SillyTavernPushResult({required this.profileId, required this.profileName});

  final String profileId;
  final String profileName;
}

enum SillyTavernPushFailure { invalidUrl, missingCsrfToken, httpError, invalidJson }

class SillyTavernPushException implements Exception {
  const SillyTavernPushException(this.failure, {this.statusCode, this.path});

  final SillyTavernPushFailure failure;
  final int? statusCode;
  final String? path;

  @override
  String toString() => failure.name;
}

class _CookieJar {
  final Map<String, String> _cookies = <String, String>{};

  String? get header {
    if (_cookies.isEmpty) {
      return null;
    }
    return _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  void capture(String? rawHeader) {
    if (rawHeader == null || rawHeader.trim().isEmpty) {
      return;
    }
    for (final rawCookie in rawHeader.split(RegExp(r', (?=[^ ;]+=)'))) {
      final pair = rawCookie.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      _cookies[pair.substring(0, separator)] = pair.substring(separator + 1);
    }
  }
}

Map<String, Object?> _decodeJsonObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const SillyTavernPushException(SillyTavernPushFailure.invalidJson);
}

Map<String, Object?> _tryDecodeJsonObject(String source) {
  try {
    return _decodeJsonObject(source);
  } catch (_) {
    return const <String, Object?>{};
  }
}

String? _readFirstString(Map<String, Object?> payload, List<String> keys) {
  for (final key in keys) {
    final value = payload[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

Map<String, Object?> _ensureObject(Map<String, Object?> owner, String key) {
  final current = owner[key];
  if (current is Map) {
    final map = current.map((childKey, value) => MapEntry(childKey.toString(), value));
    owner[key] = map;
    return map;
  }
  final map = <String, Object?>{};
  owner[key] = map;
  return map;
}

List<Object?> _ensureList(Map<String, Object?> owner, String key) {
  final current = owner[key];
  if (current is List) {
    return current;
  }
  final list = <Object?>[];
  owner[key] = list;
  return list;
}
