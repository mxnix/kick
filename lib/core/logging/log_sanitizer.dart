import 'dart:convert';

class LogSanitizer {
  static const removedFromExportNotice = '[Removed from export for safety]';
  static const _prettyJsonEncoder = JsonEncoder.withIndent('  ');
  static final _emailPattern = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
    caseSensitive: false,
  );

  static const _secretKeys = <String>{
    'authorization',
    'api_key',
    'access_token',
    'refresh_token',
    'token',
    'token_ref',
    'key',
  };

  static Object? sanitizeJsonValue(Object? value) {
    return _sanitizeValue(value);
  }

  static String sanitizeText(String value) {
    return _sanitizeLooseString(value);
  }

  static String maskEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (!_looksLikeEmail(trimmed)) {
      return sanitizeText(trimmed);
    }
    return _maskEmailAddress(trimmed);
  }

  static String? sanitizeSerializedPayload(String? payload) {
    if (payload == null) {
      return null;
    }

    final trimmed = payload.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(trimmed);
      return jsonEncode(sanitizeJsonValue(decoded));
    } catch (_) {
      return _sanitizeLooseString(trimmed);
    }
  }

  static String? formatPayloadForDisplay(String? payload) {
    final sanitized = sanitizeSerializedPayload(payload);
    if (sanitized == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(sanitized);
      return _prettyJsonEncoder.convert(decoded);
    } catch (_) {
      return sanitized;
    }
  }

  static Object? _sanitizeValue(Object? value, {String? key}) {
    if (key != null && _isSensitiveKey(key)) {
      return '***';
    }

    if (key == 'messages' && value is List) {
      return _summarizeMessages(value);
    }
    if (key == 'input') {
      return _summarizeInput(value);
    }
    if (key == 'content') {
      return _redactValue(value, label: 'content');
    }
    if (key == 'parts' && value is List) {
      return _summarizeParts(value);
    }
    if (key == 'tools' && value is List) {
      return _summarizeTools(value);
    }
    if (key == 'tool_calls' && value is List) {
      return _summarizeToolCalls(value);
    }
    if (key == 'instructions' ||
        key == 'prompt' ||
        key == 'preview' ||
        key == 'output' ||
        key == 'result' ||
        key == 'system_instruction') {
      return _redactValue(value, label: key!);
    }
    if (key == 'text' && value is String) {
      return _redactText(value);
    }
    if (key == 'arguments') {
      return _redactValue(value, label: 'arguments');
    }
    if (key == 'image_url' || key == 'file_url' || key == 'url') {
      return _summarizeUri(value);
    }
    if (key == 'file_data' || key == 'inline_data' || key == 'data') {
      return _summarizeBlob(value);
    }

    if (value is Map) {
      return value.map((mapKey, innerValue) {
        final normalizedKey = _normalizeKey(mapKey.toString());
        return MapEntry(mapKey, _sanitizeValue(innerValue, key: normalizedKey));
      });
    }

    if (value is List) {
      return value.map((item) => _sanitizeValue(item)).toList(growable: false);
    }

    if (value is String) {
      return _sanitizeLooseString(value);
    }

    return value;
  }

  static bool _isSensitiveKey(String key) {
    return _secretKeys.contains(key) || key.endsWith('_token') || key.endsWith('_key');
  }

  static Map<String, Object?> _summarizeMessages(List messages) {
    final roles = <String>{};
    var containsMedia = false;
    var containsToolCalls = false;

    for (final rawMessage in messages) {
      if (rawMessage is! Map) {
        continue;
      }

      final message = rawMessage.cast<String, Object?>();
      final role = (message['role'] as String?)?.trim();
      if (role != null && role.isNotEmpty) {
        roles.add(role);
      }

      if (message['tool_calls'] is List && (message['tool_calls'] as List).isNotEmpty) {
        containsToolCalls = true;
      }
      if (_containsMedia(message['content'])) {
        containsMedia = true;
      }
    }

    return {
      'message_count': messages.length,
      'roles': roles.toList(growable: false),
      'contains_media': containsMedia,
      'contains_tool_calls': containsToolCalls,
    };
  }

  static Object? _summarizeInput(Object? value) {
    if (value is String) {
      return _redactText(value);
    }

    if (value is List) {
      final itemTypes = <String>{};
      var containsMedia = false;

      for (final rawItem in value) {
        if (rawItem is! Map) {
          itemTypes.add(rawItem.runtimeType.toString());
          continue;
        }

        final item = rawItem.cast<String, Object?>();
        final type = (item['type'] as String?)?.trim();
        if (type != null && type.isNotEmpty) {
          itemTypes.add(type);
        }
        if (_containsMedia(item['content']) || _containsMedia(item)) {
          containsMedia = true;
        }
      }

      return {
        'item_count': value.length,
        'types': itemTypes.toList(growable: false),
        'contains_media': containsMedia,
      };
    }

    return _redactValue(value, label: 'input');
  }

  static Map<String, Object?> _summarizeParts(List parts) {
    final types = <String>{};
    var containsMedia = false;

    for (final rawPart in parts) {
      if (rawPart is! Map) {
        continue;
      }

      final part = rawPart.cast<String, Object?>();
      final type = (part['type'] as String?)?.trim();
      if (type != null && type.isNotEmpty) {
        types.add(type);
      }
      if (_containsMedia(part)) {
        containsMedia = true;
      }
    }

    return {
      'part_count': parts.length,
      'types': types.toList(growable: false),
      'contains_media': containsMedia,
    };
  }

  static Map<String, Object?> _summarizeTools(List tools) {
    final toolNames = <String>[];

    for (final rawTool in tools) {
      if (rawTool is! Map) {
        continue;
      }

      final tool = rawTool.cast<String, Object?>();
      final function =
          (tool['function'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
      final name = ((function['name'] as String?) ?? (tool['name'] as String?) ?? '').trim();
      if (name.isNotEmpty) {
        toolNames.add(name);
      }
    }

    return {'tool_count': tools.length, if (toolNames.isNotEmpty) 'tool_names': toolNames};
  }

  static Map<String, Object?> _summarizeToolCalls(List toolCalls) {
    final toolNames = <String>[];

    for (final rawToolCall in toolCalls) {
      if (rawToolCall is! Map) {
        continue;
      }

      final toolCall = rawToolCall.cast<String, Object?>();
      final function =
          (toolCall['function'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
      final name = ((function['name'] as String?) ?? (toolCall['name'] as String?) ?? '').trim();
      if (name.isNotEmpty) {
        toolNames.add(name);
      }
    }

    return {'tool_call_count': toolCalls.length, if (toolNames.isNotEmpty) 'tool_names': toolNames};
  }

  static Object _redactValue(Object? value, {required String label}) {
    if (value is String) {
      return _redactText(value, label: label);
    }

    if (value is List) {
      return '[REDACTED $label items=${value.length}]';
    }

    if (value is Map) {
      final keys = value.keys.map((item) => item.toString()).take(6).toList(growable: false);
      return '[REDACTED $label keys=${keys.join(",")}]';
    }

    return '[REDACTED $label]';
  }

  static String _redactText(String value, {String label = 'text'}) {
    return '[REDACTED $label chars=${value.trim().length}]';
  }

  static String _summarizeUri(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((item) => item.toString()).take(6).toList(growable: false);
      return '[REDACTED uri keys=${keys.join(",")}]';
    }

    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return '[REDACTED uri]';
    }

    if (_looksLikeDataUri(text)) {
      return '[REDACTED data URI chars=${text.length}]';
    }

    final uri = Uri.tryParse(text);
    final host = uri?.host;
    if (host != null && host.isNotEmpty) {
      return '[REDACTED uri host=$host]';
    }

    return '[REDACTED uri chars=${text.length}]';
  }

  static String _summarizeBlob(Object? value) {
    if (value is String) {
      return '[REDACTED blob chars=${value.trim().length}]';
    }

    if (value is List) {
      return '[REDACTED blob items=${value.length}]';
    }

    if (value is Map) {
      final keys = value.keys.map((item) => item.toString()).take(6).toList(growable: false);
      return '[REDACTED blob keys=${keys.join(",")}]';
    }

    return '[REDACTED blob]';
  }

  static String _sanitizeLooseString(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('Bearer ') && trimmed.length > 12) {
      return 'Bearer ***';
    }
    if (_looksLikeDataUri(trimmed)) {
      return '[REDACTED data URI chars=${trimmed.length}]';
    }
    if (_looksLikeBase64(trimmed)) {
      return '[REDACTED blob chars=${trimmed.length}]';
    }
    return _maskEmails(value);
  }

  static String _maskEmails(String value) {
    return value.replaceAllMapped(
      _emailPattern,
      (match) => _maskEmailAddress(match.group(0) ?? ''),
    );
  }

  static String _maskEmailAddress(String value) {
    final atIndex = value.indexOf('@');
    if (atIndex <= 0 || atIndex >= value.length - 1) {
      return value;
    }

    final localPart = value.substring(0, atIndex);
    final domain = value.substring(atIndex + 1);
    if (localPart.length <= 1) {
      return '$localPart@$domain';
    }

    final middleMask = List.filled(localPart.length - 2, '*').join();
    return '${localPart[0]}$middleMask${localPart[localPart.length - 1]}@$domain';
  }

  static bool _containsMedia(Object? value) {
    if (value is List) {
      return value.any(_containsMedia);
    }

    if (value is! Map) {
      return false;
    }

    final map = value.cast<String, Object?>();
    final type = (map['type'] as String?)?.trim().toLowerCase();
    if (type == 'image_url' || type == 'input_image' || type == 'file') {
      return true;
    }

    return map.containsKey('image_url') ||
        map.containsKey('file') ||
        map.containsKey('file_url') ||
        map.containsKey('file_data') ||
        map.containsKey('inline_data');
  }

  static bool _looksLikeDataUri(String value) {
    return value.startsWith('data:') && value.contains(';base64,');
  }

  static bool _looksLikeBase64(String value) {
    if (value.length < 128) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(value);
  }

  static bool _looksLikeEmail(String value) {
    final match = _emailPattern.firstMatch(value);
    return match != null && match.start == 0 && match.end == value.length;
  }

  static String _normalizeKey(String key) {
    return key.trim().toLowerCase();
  }
}
