import 'dart:convert';

class OpenAiThoughtSignatureCache {
  OpenAiThoughtSignatureCache({
    this.maxEntries = 256,
    this.ttl = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxEntries;
  final Duration ttl;
  final DateTime Function() _now;
  final Map<String, _CachedThoughtSignature> _entries = <String, _CachedThoughtSignature>{};

  void rememberToolCalls(Iterable<Map<String, Object?>> toolCalls) {
    _prune();
    for (final toolCall in toolCalls) {
      final signature = _extractThoughtSignature(toolCall);
      if (signature == null) {
        continue;
      }
      final record = _CachedThoughtSignature(
        signature: signature,
        id: _toolCallId(toolCall),
        name: _toolCallName(toolCall),
        arguments: _toolCallArguments(toolCall),
        createdAt: _now(),
      );
      for (final key in _keysForRecord(record)) {
        _entries[key] = record;
      }
    }
    _prune();
  }

  bool enrichChatRequest(Map<String, Object?> body) {
    final messages = body['messages'];
    if (messages is! List) {
      return false;
    }

    var changed = false;
    _prune();
    for (final rawMessage in messages) {
      final message = _asStringMap(rawMessage);
      if (message == null || message['role'] != 'assistant') {
        continue;
      }
      final toolCalls = message['tool_calls'];
      if (toolCalls is! List) {
        continue;
      }
      for (final rawToolCall in toolCalls) {
        final toolCall = _asStringMap(rawToolCall);
        if (toolCall == null || _extractThoughtSignature(toolCall) != null) {
          continue;
        }
        final signature = _lookup(toolCall);
        if (signature == null) {
          continue;
        }
        _writeThoughtSignature(toolCall, signature);
        changed = true;
      }
    }
    return changed;
  }

  bool enrichResponsesRequest(Map<String, Object?> body) {
    final input = body['input'];
    if (input is! List) {
      return false;
    }

    var changed = false;
    _prune();
    for (final rawItem in input) {
      final item = _asStringMap(rawItem);
      if (item == null || item['type'] != 'function_call') {
        continue;
      }
      if (_extractThoughtSignature(item) != null) {
        continue;
      }
      final signature = _lookup(item);
      if (signature == null) {
        continue;
      }
      _writeThoughtSignature(item, signature);
      changed = true;
    }
    return changed;
  }

  String? _lookup(Map<String, Object?> toolCall) {
    final id = _toolCallId(toolCall);
    if (id != null) {
      final byId = _entries['id:$id'];
      if (byId != null && (!_isGenericToolCallId(id) || byId.hasSameFingerprintAs(toolCall))) {
        return byId.signature;
      }
    }

    final fingerprint = _fingerprintForToolCall(toolCall);
    if (fingerprint == null) {
      return null;
    }
    return _entries[fingerprint]?.signature;
  }

  void _prune() {
    final now = _now();
    _entries.removeWhere((_, entry) => now.difference(entry.createdAt) > ttl);
    if (_entries.length <= maxEntries) {
      return;
    }

    final keysByAge = _entries.keys.toList(growable: false)
      ..sort((left, right) => _entries[left]!.createdAt.compareTo(_entries[right]!.createdAt));
    final removeCount = _entries.length - maxEntries;
    for (final key in keysByAge.take(removeCount)) {
      _entries.remove(key);
    }
  }

  static Iterable<String> _keysForRecord(_CachedThoughtSignature record) sync* {
    if (record.id != null) {
      yield 'id:${record.id}';
    }
    final fingerprint = _fingerprint(record.name, record.arguments);
    if (fingerprint != null) {
      yield fingerprint;
    }
  }

  static String? _fingerprintForToolCall(Map<String, Object?> toolCall) {
    return _fingerprint(_toolCallName(toolCall), _toolCallArguments(toolCall));
  }

  static String? _fingerprint(String? name, String? arguments) {
    if (name == null || arguments == null) {
      return null;
    }
    return 'fn:$name:$arguments';
  }

  static String? _toolCallId(Map<String, Object?> toolCall) {
    return _trimmedString(toolCall['id']) ?? _trimmedString(toolCall['call_id']);
  }

  static String? _toolCallName(Map<String, Object?> toolCall) {
    final function = _asStringMap(toolCall['function']);
    return _trimmedString(function?['name']) ?? _trimmedString(toolCall['name']);
  }

  static String? _toolCallArguments(Map<String, Object?> toolCall) {
    final function = _asStringMap(toolCall['function']);
    return _canonicalArguments(function?['arguments'] ?? toolCall['arguments']);
  }

  static String? _canonicalArguments(Object? rawArguments) {
    if (rawArguments == null) {
      return null;
    }
    if (rawArguments is String) {
      final trimmed = rawArguments.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      try {
        return jsonEncode(jsonDecode(trimmed));
      } catch (_) {
        return trimmed;
      }
    }
    try {
      return jsonEncode(rawArguments);
    } catch (_) {
      return rawArguments.toString();
    }
  }

  static String? _extractThoughtSignature(Map<String, Object?> toolCall) {
    final direct =
        _trimmedString(toolCall['thought_signature']) ??
        _trimmedString(toolCall['thoughtSignature']);
    if (direct != null) {
      return direct;
    }

    final extraContent = _asStringMap(toolCall['extra_content']);
    final google = _asStringMap(extraContent?['google']);
    return _trimmedString(google?['thought_signature']) ??
        _trimmedString(google?['thoughtSignature']);
  }

  static void _writeThoughtSignature(Map<String, Object?> toolCall, String signature) {
    final extraContent = _asWritableStringMap(toolCall, 'extra_content');
    final google = _asWritableStringMap(extraContent, 'google');
    google['thought_signature'] = signature;
  }

  static Map<String, Object?> _asWritableStringMap(Map<String, Object?> parent, String key) {
    final current = _asStringMap(parent[key]);
    if (current != null) {
      return current;
    }
    final next = <String, Object?>{};
    parent[key] = next;
    return next;
  }

  static Map<String, Object?>? _asStringMap(Object? value) {
    return value is Map ? value.cast<String, Object?>() : null;
  }

  static String? _trimmedString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _isGenericToolCallId(String id) {
    return RegExp(r'^call_\d+$').hasMatch(id);
  }
}

class _CachedThoughtSignature {
  const _CachedThoughtSignature({
    required this.signature,
    required this.id,
    required this.name,
    required this.arguments,
    required this.createdAt,
  });

  final String signature;
  final String? id;
  final String? name;
  final String? arguments;
  final DateTime createdAt;

  bool hasSameFingerprintAs(Map<String, Object?> toolCall) {
    final currentName = OpenAiThoughtSignatureCache._toolCallName(toolCall);
    final currentArguments = OpenAiThoughtSignatureCache._toolCallArguments(toolCall);
    return name != null &&
        arguments != null &&
        currentName == name &&
        currentArguments == arguments;
  }
}
