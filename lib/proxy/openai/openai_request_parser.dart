import 'dart:convert';

class UnifiedPromptRequest {
  UnifiedPromptRequest({
    required this.requestId,
    required this.model,
    required this.stream,
    required this.source,
    required this.turns,
    required this.tools,
    required this.systemInstruction,
    required this.toolChoice,
    required this.temperature,
    required this.topP,
    required this.maxOutputTokens,
    required this.stopSequences,
    required this.reasoningEffort,
    required this.googleThinkingConfig,
    required this.googleWebSearchEnabled,
    required this.responseModalities,
    required this.jsonMode,
    required this.responseSchema,
  });

  final String requestId;
  final String model;
  final bool stream;
  final String source;
  final List<UnifiedTurn> turns;
  final List<UnifiedToolDeclaration> tools;
  final String? systemInstruction;
  final Object? toolChoice;
  final double? temperature;
  final double? topP;
  final int? maxOutputTokens;
  final List<String>? stopSequences;
  final String? reasoningEffort;
  final Map<String, Object?>? googleThinkingConfig;
  final bool googleWebSearchEnabled;
  final List<String>? responseModalities;
  final bool jsonMode;
  final Map<String, Object?>? responseSchema;
}

class UnifiedTurn {
  const UnifiedTurn({required this.role, required this.parts});

  final String role;
  final List<UnifiedPart> parts;
}

enum UnifiedPartType { text, thought, functionCall, functionResponse, inlineData, fileData }

class UnifiedPart {
  const UnifiedPart.text(this.text)
    : type = UnifiedPartType.text,
      thoughtSignature = null,
      callId = null,
      name = null,
      arguments = null,
      mimeType = null,
      data = null,
      fileUri = null;

  const UnifiedPart.thought({required this.text, this.thoughtSignature})
    : type = UnifiedPartType.thought,
      callId = null,
      name = null,
      arguments = null,
      mimeType = null,
      data = null,
      fileUri = null;

  const UnifiedPart.functionCall({
    required this.callId,
    required this.name,
    required this.arguments,
  }) : type = UnifiedPartType.functionCall,
       thoughtSignature = null,
       text = null,
       mimeType = null,
       data = null,
       fileUri = null;

  const UnifiedPart.functionResponse({
    required this.callId,
    required this.name,
    required this.arguments,
  }) : type = UnifiedPartType.functionResponse,
       thoughtSignature = null,
       text = null,
       mimeType = null,
       data = null,
       fileUri = null;

  const UnifiedPart.inlineData({required this.mimeType, required this.data})
    : type = UnifiedPartType.inlineData,
      text = null,
      thoughtSignature = null,
      callId = null,
      name = null,
      arguments = null,
      fileUri = null;

  const UnifiedPart.fileData({required this.mimeType, required this.fileUri})
    : type = UnifiedPartType.fileData,
      text = null,
      thoughtSignature = null,
      callId = null,
      name = null,
      arguments = null,
      data = null;

  final UnifiedPartType type;
  final String? text;
  final String? thoughtSignature;
  final String? callId;
  final String? name;
  final Map<String, Object?>? arguments;
  final String? mimeType;
  final String? data;
  final String? fileUri;
}

class UnifiedToolDeclaration {
  const UnifiedToolDeclaration({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;
}

class OpenAiRequestParser {
  static UnifiedPromptRequest parseChatRequest(
    Map<String, Object?> json, {
    required String requestId,
  }) {
    final model = _readRequiredString(json, 'model');
    final messages = json['messages'];
    if (messages is! List) {
      throw const FormatException('`messages` must be an array.');
    }

    final leadingSystemParts = <String>[];
    final turns = <UnifiedTurn>[];
    final toolDeclarations = _parseTools(json['tools']);
    final toolCallNames = <String, String>{};
    var seenNonSystemMessage = false;

    for (final rawMessage in messages) {
      if (rawMessage is! Map) {
        continue;
      }
      final message = rawMessage.cast<String, Object?>();
      final role = (message['role'] as String? ?? 'user').trim();
      if (role == 'system' || role == 'developer') {
        final text = _extractTextContent(message['content']);
        if (text.isEmpty) {
          continue;
        }
        if (!seenNonSystemMessage) {
          leadingSystemParts.add(text);
        } else {
          turns.add(UnifiedTurn(role: 'user', parts: [UnifiedPart.text(text)]));
        }
        continue;
      }

      seenNonSystemMessage = true;

      if (role == 'tool') {
        final toolCallId = message['tool_call_id'] as String? ?? '';
        final functionName = toolCallNames[toolCallId];
        if (functionName == null) {
          continue;
        }
        turns.add(
          UnifiedTurn(
            role: 'user',
            parts: [
              UnifiedPart.functionResponse(
                callId: toolCallId,
                name: functionName,
                arguments: {'result': _extractTextContent(message['content'])},
              ),
            ],
          ),
        );
        continue;
      }

      final parts = <UnifiedPart>[
        ..._extractMessageThoughtParts(message),
        ..._extractChatParts(message['content']),
      ];

      final toolCalls = message['tool_calls'];
      if (toolCalls is List) {
        for (final rawToolCall in toolCalls) {
          if (rawToolCall is! Map) {
            continue;
          }
          final toolCall = rawToolCall.cast<String, Object?>();
          final id = toolCall['id'] as String? ?? '';
          final function =
              (toolCall['function'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
          final name = function['name'] as String? ?? '';
          if (id.isNotEmpty && name.isNotEmpty) {
            toolCallNames[id] = name;
          }
          parts.add(
            UnifiedPart.functionCall(
              callId: id,
              name: name,
              arguments: _parseJsonLike(function['arguments']),
            ),
          );
        }
      }

      if (parts.isEmpty) {
        continue;
      }
      turns.add(UnifiedTurn(role: role == 'assistant' ? 'assistant' : 'user', parts: parts));
    }

    final responseFormat = (json['response_format'] as Map?)?.cast<String, Object?>();
    final googleWebSearchEnabled = _parseGoogleWebSearchEnabled(json);
    if (toolDeclarations.isNotEmpty && googleWebSearchEnabled) {
      throw const FormatException('`google web search` cannot be used together with `tools` yet.');
    }
    final mergedSystemInstruction = leadingSystemParts.join('\n\n').trim();
    var systemInstruction = mergedSystemInstruction.isEmpty ? null : mergedSystemInstruction;
    if (turns.isEmpty && systemInstruction != null) {
      turns.add(UnifiedTurn(role: 'user', parts: [UnifiedPart.text(systemInstruction)]));
      systemInstruction = null;
    }

    return UnifiedPromptRequest(
      requestId: requestId,
      model: model,
      stream: json['stream'] == true,
      source: 'chat.completions',
      turns: turns,
      tools: toolDeclarations,
      systemInstruction: systemInstruction,
      toolChoice: json['tool_choice'],
      temperature: (json['temperature'] as num?)?.toDouble(),
      topP: (json['top_p'] as num?)?.toDouble(),
      maxOutputTokens:
          (json['max_completion_tokens'] as num?)?.toInt() ?? (json['max_tokens'] as num?)?.toInt(),
      stopSequences: _parseStopSequences(json['stop']),
      reasoningEffort: _parseReasoningEffort(json),
      googleThinkingConfig: _parseGoogleThinkingConfig(json),
      googleWebSearchEnabled: googleWebSearchEnabled,
      responseModalities: _parseModalities(json['modalities']),
      jsonMode:
          responseFormat?['type'] == 'json_object' || responseFormat?['type'] == 'json_schema',
      responseSchema: ((responseFormat?['json_schema'] as Map?)?['schema'] as Map?)
          ?.cast<String, Object?>(),
    );
  }

  static UnifiedPromptRequest parseResponsesRequest(
    Map<String, Object?> json, {
    required String requestId,
  }) {
    final model = _readRequiredString(json, 'model');
    final turns = <UnifiedTurn>[];
    final input = json['input'];
    if (input is String && input.trim().isNotEmpty) {
      turns.add(UnifiedTurn(role: 'user', parts: [UnifiedPart.text(input.trim())]));
    } else if (input is List) {
      for (final rawItem in input) {
        if (rawItem is! Map) {
          continue;
        }
        final item = rawItem.cast<String, Object?>();
        final type = item['type'] as String? ?? 'message';
        if (type == 'function_call') {
          turns.add(
            UnifiedTurn(
              role: 'assistant',
              parts: [
                UnifiedPart.functionCall(
                  callId: item['call_id'] as String? ?? '',
                  name: item['name'] as String? ?? 'tool',
                  arguments: _parseJsonLike(item['arguments']),
                ),
              ],
            ),
          );
          continue;
        }
        if (type == 'function_call_output') {
          turns.add(
            UnifiedTurn(
              role: 'user',
              parts: [
                UnifiedPart.functionResponse(
                  callId: item['call_id'] as String? ?? '',
                  name: item['name'] as String? ?? 'tool',
                  arguments: {'result': _extractTextContent(item['output'])},
                ),
              ],
            ),
          );
          continue;
        }

        if (type == 'reasoning') {
          final parts = _extractReasoningParts(item);
          if (parts.isNotEmpty) {
            turns.add(UnifiedTurn(role: 'assistant', parts: parts));
          }
          continue;
        }

        final role = (item['role'] as String? ?? 'user') == 'assistant' ? 'assistant' : 'user';
        final parts = <UnifiedPart>[
          ..._extractMessageThoughtParts(item),
          ..._extractResponsesParts(item['content']),
        ];
        if (parts.isNotEmpty) {
          turns.add(UnifiedTurn(role: role, parts: parts));
        }
      }
    }

    final tools = _parseTools(json['tools']);
    final googleWebSearchEnabled = _parseGoogleWebSearchEnabled(json);
    if (tools.isNotEmpty && googleWebSearchEnabled) {
      throw const FormatException('`google web search` cannot be used together with `tools` yet.');
    }
    final textConfig = (json['text'] as Map?)?.cast<String, Object?>();
    final responseFormat = (textConfig?['format'] as Map?)?.cast<String, Object?>();

    return UnifiedPromptRequest(
      requestId: requestId,
      model: model,
      stream: json['stream'] == true,
      source: 'responses',
      turns: turns,
      tools: tools,
      systemInstruction: (json['instructions'] as String?)?.trim().isEmpty == true
          ? null
          : (json['instructions'] as String?),
      toolChoice: json['tool_choice'],
      temperature: (json['temperature'] as num?)?.toDouble(),
      topP: (json['top_p'] as num?)?.toDouble(),
      maxOutputTokens: (json['max_output_tokens'] as num?)?.toInt(),
      stopSequences: _parseStopSequences(json['stop']),
      reasoningEffort: _parseReasoningEffort(json),
      googleThinkingConfig: _parseGoogleThinkingConfig(json),
      googleWebSearchEnabled: googleWebSearchEnabled,
      responseModalities: _parseModalities(json['modalities']),
      jsonMode:
          responseFormat?['type'] == 'json_schema' || responseFormat?['type'] == 'json_object',
      responseSchema: (responseFormat?['schema'] as Map?)?.cast<String, Object?>(),
    );
  }

  static String _readRequiredString(Map<String, Object?> json, String key) {
    final value = (json[key] as String?)?.trim();
    if (value == null || value.isEmpty) {
      throw FormatException('`$key` is required.');
    }
    return value;
  }

  static List<UnifiedToolDeclaration> _parseTools(Object? rawTools) {
    if (rawTools is! List) {
      return const [];
    }

    final tools = <UnifiedToolDeclaration>[];
    for (final rawTool in rawTools) {
      if (rawTool is! Map) {
        continue;
      }
      final tool = rawTool.cast<String, Object?>();
      final function =
          (tool['function'] as Map?)?.cast<String, Object?>() ?? tool.cast<String, Object?>();
      final name = function['name'] as String? ?? '';
      if (name.trim().isEmpty) {
        continue;
      }
      tools.add(
        UnifiedToolDeclaration(
          name: name,
          description: function['description'] as String? ?? '',
          parameters:
              (function['parametersJsonSchema'] as Map?)?.cast<String, Object?>() ??
              (function['parameters'] as Map?)?.cast<String, Object?>() ??
              const {'type': 'object', 'properties': <String, Object?>{}},
        ),
      );
    }
    return tools;
  }

  static String _extractTextContent(Object? content) {
    if (content is String) {
      return content.trim();
    }
    if (content is List) {
      final buffer = StringBuffer();
      for (final item in content) {
        if (item is! Map) {
          continue;
        }
        final entry = item.cast<String, Object?>();
        if (entry['type'] == 'text' && entry['text'] is String) {
          buffer.writeln((entry['text'] as String).trim());
        } else if (entry['type'] == 'image_url') {
          final imageUrl = entry['image_url'];
          final url = imageUrl is String ? imageUrl : (imageUrl as Map?)?['url'] as String?;
          if (url != null && url.isNotEmpty) {
            buffer.writeln('[Image: $url]');
          }
        }
      }
      return buffer.toString().trim();
    }
    if (content is Map) {
      return jsonEncode(content);
    }
    return '';
  }

  static List<UnifiedPart> _extractChatParts(Object? content) {
    if (content is String) {
      final text = content.trim();
      return text.isEmpty ? const [] : [UnifiedPart.text(text)];
    }
    if (content is! List) {
      if (content is Map) {
        return [UnifiedPart.text(jsonEncode(content))];
      }
      return const [];
    }

    final parts = <UnifiedPart>[];
    for (final raw in content) {
      if (raw is! Map) {
        continue;
      }
      _appendContentItemAsPart(parts, raw.cast<String, Object?>());
    }
    return parts;
  }

  static List<UnifiedPart> _extractResponsesParts(Object? content) {
    if (content is String) {
      final text = content.trim();
      return text.isEmpty ? const [] : [UnifiedPart.text(text)];
    }
    if (content is! List) {
      return const [];
    }

    final parts = <UnifiedPart>[];
    for (final raw in content) {
      if (raw is! Map) {
        continue;
      }
      _appendContentItemAsPart(parts, raw.cast<String, Object?>());
    }
    return parts;
  }

  static void _appendContentItemAsPart(List<UnifiedPart> parts, Map<String, Object?> item) {
    final type = item['type'] as String? ?? '';
    switch (type) {
      case 'reasoning':
      case 'reasoning_content':
      case 'summary_text':
        final text = (item['text'] as String?)?.trim();
        if (text != null && text.isNotEmpty) {
          parts.add(
            UnifiedPart.thought(
              text: text,
              thoughtSignature: (item['thought_signature'] as String?)?.trim(),
            ),
          );
        }
        break;
      case 'text':
      case 'input_text':
      case 'output_text':
        final text = (item['text'] as String?)?.trim();
        if (text != null && text.isNotEmpty) {
          parts.add(UnifiedPart.text(text));
        }
        break;
      case 'image_url':
        _appendImagePart(parts, item['image_url']);
        break;
      case 'input_image':
        _appendImagePart(parts, item['image_url'] ?? item['url']);
        break;
      case 'file':
        _appendFilePart(parts, item['file']);
        break;
      default:
        if (item['text'] is String && (item['text'] as String).trim().isNotEmpty) {
          parts.add(UnifiedPart.text((item['text'] as String).trim()));
        }
        break;
    }
  }

  static List<UnifiedPart> _extractMessageThoughtParts(Map<String, Object?> message) {
    final explicitThoughts = message['google_thoughts'];
    if (explicitThoughts is List) {
      final parts = <UnifiedPart>[];
      for (final rawThought in explicitThoughts) {
        if (rawThought is! Map) {
          continue;
        }
        final thought = rawThought.cast<String, Object?>();
        final text = (thought['text'] as String?)?.trim() ?? '';
        final signature = (thought['signature'] as String?)?.trim();
        if (text.isEmpty && (signature == null || signature.isEmpty)) {
          continue;
        }
        parts.add(UnifiedPart.thought(text: text, thoughtSignature: signature));
      }
      if (parts.isNotEmpty) {
        return parts;
      }
    }

    final reasoningText = (message['reasoning_content'] as String?)?.trim();
    final reasoningSignature = (message['reasoning_signature'] as String?)?.trim();
    if ((reasoningText == null || reasoningText.isEmpty) &&
        (reasoningSignature == null || reasoningSignature.isEmpty)) {
      return const [];
    }

    return [UnifiedPart.thought(text: reasoningText ?? '', thoughtSignature: reasoningSignature)];
  }

  static List<UnifiedPart> _extractReasoningParts(Map<String, Object?> item) {
    final explicitThoughts = _extractMessageThoughtParts(item);
    if (explicitThoughts.isNotEmpty) {
      return explicitThoughts;
    }

    final summary = item['summary'];
    if (summary is! List) {
      return const [];
    }

    final parts = <UnifiedPart>[];
    for (final rawPart in summary) {
      if (rawPart is! Map) {
        continue;
      }
      final entry = rawPart.cast<String, Object?>();
      final text = (entry['text'] as String?)?.trim() ?? '';
      final signature = (entry['thought_signature'] as String?)?.trim();
      if (text.isEmpty && (signature == null || signature.isEmpty)) {
        continue;
      }
      parts.add(UnifiedPart.thought(text: text, thoughtSignature: signature));
    }
    return parts;
  }

  static void _appendImagePart(List<UnifiedPart> parts, Object? rawImage) {
    final imageUrl = rawImage is String
        ? rawImage
        : (rawImage as Map?)?.cast<String, Object?>()['url'] as String?;
    if (imageUrl == null || imageUrl.trim().isEmpty) {
      return;
    }

    final parsedDataUri = _parseDataUri(imageUrl.trim());
    if (parsedDataUri != null) {
      parts.add(UnifiedPart.inlineData(mimeType: parsedDataUri.mimeType, data: parsedDataUri.data));
      return;
    }

    parts.add(
      UnifiedPart.fileData(
        mimeType: _guessMimeType(imageUrl, fallback: 'image/jpeg'),
        fileUri: imageUrl.trim(),
      ),
    );
  }

  static void _appendFilePart(List<UnifiedPart> parts, Object? rawFile) {
    if (rawFile is! Map) {
      return;
    }
    final file = rawFile.cast<String, Object?>();
    final fileData = (file['file_data'] as String?)?.trim();
    final fileUrl = ((file['file_url'] as String?) ?? (file['url'] as String?))?.trim();
    final mimeType = _resolveFileMimeType(file);

    if (fileData != null && fileData.isNotEmpty) {
      final parsedDataUri = _parseDataUri(fileData);
      if (parsedDataUri != null) {
        parts.add(
          UnifiedPart.inlineData(mimeType: parsedDataUri.mimeType, data: parsedDataUri.data),
        );
      } else {
        parts.add(UnifiedPart.inlineData(mimeType: mimeType, data: fileData));
      }
      return;
    }

    if (fileUrl != null && fileUrl.isNotEmpty) {
      parts.add(UnifiedPart.fileData(mimeType: mimeType, fileUri: fileUrl));
    }
  }

  static Map<String, Object?> _parseJsonLike(Object? raw) {
    if (raw is Map) {
      return raw.cast<String, Object?>();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.cast<String, Object?>();
        }
      } catch (_) {
        return {'raw': raw};
      }
    }
    return const <String, Object?>{};
  }

  static List<String>? _parseStopSequences(Object? rawStop) {
    if (rawStop is String) {
      final value = rawStop.trim();
      return value.isEmpty ? null : [value];
    }
    if (rawStop is! List) {
      return null;
    }

    final values = rawStop
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return values.isEmpty ? null : values;
  }

  static String? _parseReasoningEffort(Map<String, Object?> json) {
    final direct = (json['reasoning_effort'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final reasoning = (json['reasoning'] as Map?)?.cast<String, Object?>();
    final effort = (reasoning?['effort'] as String?)?.trim();
    return effort == null || effort.isEmpty ? null : effort;
  }

  static Map<String, Object?>? _parseGoogleThinkingConfig(Map<String, Object?> json) {
    final extraBody = (json['extra_body'] as Map?)?.cast<String, Object?>();
    final google = (extraBody?['google'] as Map?)?.cast<String, Object?>();
    final config = ((google?['thinking_config'] as Map?) ?? (google?['thinkingConfig'] as Map?))
        ?.cast<String, Object?>();
    if (config == null || config.isEmpty) {
      return null;
    }
    return config;
  }

  static bool _parseGoogleWebSearchEnabled(Map<String, Object?> json) {
    final extraBody = (json['extra_body'] as Map?)?.cast<String, Object?>();
    final google = (extraBody?['google'] as Map?)?.cast<String, Object?>();
    final directGoogle = (json['google'] as Map?)?.cast<String, Object?>();
    return _readBooleanFlag(google?['web_search']) ??
        _readBooleanFlag(google?['webSearch']) ??
        _readBooleanFlag(extraBody?['web_search']) ??
        _readBooleanFlag(extraBody?['webSearch']) ??
        _readBooleanFlag(directGoogle?['web_search']) ??
        _readBooleanFlag(directGoogle?['webSearch']) ??
        _readBooleanFlag(json['web_search']) ??
        _readBooleanFlag(json['webSearch']) ??
        false;
  }

  static bool? _readBooleanFlag(Object? raw) {
    if (raw is bool) {
      return raw;
    }
    if (raw is num) {
      return raw != 0;
    }
    if (raw is! String) {
      return null;
    }

    switch (raw.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'off':
        return false;
      default:
        return null;
    }
  }

  static List<String>? _parseModalities(Object? rawModalities) {
    if (rawModalities is! List) {
      return null;
    }

    final values = rawModalities
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return values.isEmpty ? null : values;
  }
}

class _ParsedDataUri {
  const _ParsedDataUri({required this.mimeType, required this.data});

  final String mimeType;
  final String data;
}

_ParsedDataUri? _parseDataUri(String value) {
  final match = RegExp(r'^data:([^;,]+);base64,(.+)$', dotAll: true).firstMatch(value);
  if (match == null) {
    return null;
  }
  return _ParsedDataUri(
    mimeType: match.group(1) ?? 'application/octet-stream',
    data: match.group(2) ?? '',
  );
}

String _resolveFileMimeType(Map<String, Object?> file) {
  final explicitMimeType = (file['mime_type'] as String?)?.trim();
  if (explicitMimeType != null && explicitMimeType.isNotEmpty) {
    return explicitMimeType;
  }

  final filename = (file['filename'] as String?)?.trim();
  return _guessMimeType(filename, fallback: 'application/octet-stream');
}

String _guessMimeType(String? value, {required String fallback}) {
  if (value == null || value.trim().isEmpty) {
    return fallback;
  }

  final lowerValue = value.trim().toLowerCase();
  if (lowerValue.endsWith('.png')) {
    return 'image/png';
  }
  if (lowerValue.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lowerValue.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lowerValue.endsWith('.svg')) {
    return 'image/svg+xml';
  }
  if (lowerValue.endsWith('.pdf')) {
    return 'application/pdf';
  }
  if (lowerValue.endsWith('.json')) {
    return 'application/json';
  }
  if (lowerValue.endsWith('.txt')) {
    return 'text/plain';
  }
  if (lowerValue.endsWith('.md')) {
    return 'text/markdown';
  }
  if (lowerValue.endsWith('.wav')) {
    return 'audio/wav';
  }
  if (lowerValue.endsWith('.mp3')) {
    return 'audio/mpeg';
  }
  if (lowerValue.endsWith('.mp4')) {
    return 'video/mp4';
  }
  if (lowerValue.endsWith('.jpeg') || lowerValue.endsWith('.jpg')) {
    return 'image/jpeg';
  }
  return fallback;
}
