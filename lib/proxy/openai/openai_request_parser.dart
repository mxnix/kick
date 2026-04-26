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
    this.thoughtSignature,
  }) : type = UnifiedPartType.functionCall,
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
      final message = _readRequiredMapValue(rawMessage, 'messages[]');
      final role = (_readStringValue(message['role'], 'messages[].role') ?? 'user').trim();
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
        final toolCallId =
            _readStringValue(message['tool_call_id'], 'messages[].tool_call_id') ?? '';
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
          final toolCall = _readRequiredMapValue(rawToolCall, 'messages[].tool_calls[]');
          final id = _readStringValue(toolCall['id'], 'messages[].tool_calls[].id') ?? '';
          final function =
              _readMapValue(toolCall['function'], 'messages[].tool_calls[].function') ??
              const <String, Object?>{};
          final name =
              _readStringValue(function['name'], 'messages[].tool_calls[].function.name') ?? '';
          if (id.isNotEmpty && name.isNotEmpty) {
            toolCallNames[id] = name;
          }
          parts.add(
            UnifiedPart.functionCall(
              callId: id,
              name: name,
              arguments: _parseJsonLike(function['arguments']),
              thoughtSignature: _extractToolCallThoughtSignature(toolCall),
            ),
          );
        }
      }

      if (parts.isEmpty) {
        continue;
      }
      turns.add(UnifiedTurn(role: role == 'assistant' ? 'assistant' : 'user', parts: parts));
    }

    final responseFormat = _readMapField(json, 'response_format');
    final jsonSchema = _readMapValue(responseFormat?['json_schema'], 'response_format.json_schema');
    final googleWebSearchEnabled = _parseGoogleWebSearchEnabled(json);
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
      temperature: _readNumField(json, 'temperature')?.toDouble(),
      topP: _readNumField(json, 'top_p')?.toDouble(),
      maxOutputTokens:
          _readIntField(json, 'max_completion_tokens') ?? _readIntField(json, 'max_tokens'),
      stopSequences: _parseStopSequences(json['stop']),
      reasoningEffort: _parseReasoningEffort(json),
      googleThinkingConfig: _parseGoogleThinkingConfig(json),
      googleWebSearchEnabled: googleWebSearchEnabled,
      responseModalities: _parseModalities(json['modalities']),
      jsonMode:
          responseFormat?['type'] == 'json_object' || responseFormat?['type'] == 'json_schema',
      responseSchema: _readMapValue(jsonSchema?['schema'], 'response_format.json_schema.schema'),
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
        final item = _readRequiredMapValue(rawItem, 'input[]');
        final type = _readStringValue(item['type'], 'input[].type') ?? 'message';
        if (type == 'function_call') {
          turns.add(
            UnifiedTurn(
              role: 'assistant',
              parts: [
                UnifiedPart.functionCall(
                  callId: _readStringValue(item['call_id'], 'input[].call_id') ?? '',
                  name: _readStringValue(item['name'], 'input[].name') ?? 'tool',
                  arguments: _parseJsonLike(item['arguments']),
                  thoughtSignature: _extractToolCallThoughtSignature(item),
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
                  callId: _readStringValue(item['call_id'], 'input[].call_id') ?? '',
                  name: _readStringValue(item['name'], 'input[].name') ?? 'tool',
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

        final role = _readStringValue(item['role'], 'input[].role') == 'assistant'
            ? 'assistant'
            : 'user';
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
    final textConfig = _readMapField(json, 'text');
    final responseFormat = _readMapValue(textConfig?['format'], 'text.format');

    return UnifiedPromptRequest(
      requestId: requestId,
      model: model,
      stream: json['stream'] == true,
      source: 'responses',
      turns: turns,
      tools: tools,
      systemInstruction: _readTrimmedStringField(json, 'instructions'),
      toolChoice: json['tool_choice'],
      temperature: _readNumField(json, 'temperature')?.toDouble(),
      topP: _readNumField(json, 'top_p')?.toDouble(),
      maxOutputTokens: _readIntField(json, 'max_output_tokens'),
      stopSequences: _parseStopSequences(json['stop']),
      reasoningEffort: _parseReasoningEffort(json),
      googleThinkingConfig: _parseGoogleThinkingConfig(json),
      googleWebSearchEnabled: googleWebSearchEnabled,
      responseModalities: _parseModalities(json['modalities']),
      jsonMode:
          responseFormat?['type'] == 'json_schema' || responseFormat?['type'] == 'json_object',
      responseSchema: _readMapValue(responseFormat?['schema'], 'text.format.schema'),
    );
  }

  static String _readRequiredString(Map<String, Object?> json, String key) {
    final raw = json[key];
    if (raw != null && raw is! String) {
      throw FormatException('`$key` must be a string.');
    }
    final value = (raw as String?)?.trim();
    if (value == null || value.isEmpty) {
      throw FormatException('`$key` is required.');
    }
    return value;
  }

  static String? _readTrimmedStringField(Map<String, Object?> json, String key) {
    final raw = json[key];
    if (raw == null) {
      return null;
    }
    if (raw is! String) {
      throw FormatException('`$key` must be a string.');
    }
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  static String? _readStringValue(Object? raw, String fieldName) {
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      return raw;
    }
    throw FormatException('`$fieldName` must be a string.');
  }

  static num? _readNumField(Map<String, Object?> json, String key) {
    final raw = json[key];
    if (raw == null) {
      return null;
    }
    if (raw is num) {
      return raw;
    }
    throw FormatException('`$key` must be a number.');
  }

  static int? _readIntField(Map<String, Object?> json, String key) {
    return _readNumField(json, key)?.toInt();
  }

  static Map<String, Object?>? _readMapField(Map<String, Object?> json, String key) {
    return _readMapValue(json[key], key);
  }

  static Map<String, Object?>? _readMapValue(Object? raw, String fieldName) {
    if (raw == null) {
      return null;
    }
    if (raw is! Map) {
      throw FormatException('`$fieldName` must be an object.');
    }

    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw FormatException('`$fieldName` keys must be strings.');
      }
      result[key] = entry.value;
    }
    return result;
  }

  static Map<String, Object?> _readRequiredMapValue(Object? raw, String fieldName) {
    final value = _readMapValue(raw, fieldName);
    if (value == null) {
      throw FormatException('`$fieldName` must be an object.');
    }
    return value;
  }

  static List<Object?>? _readListValue(Object? raw, String fieldName) {
    if (raw == null) {
      return null;
    }
    if (raw is List) {
      return raw.cast<Object?>();
    }
    throw FormatException('`$fieldName` must be an array.');
  }

  static String? _extractToolCallThoughtSignature(Map<String, Object?> toolCall) {
    final direct =
        _trimmedString(toolCall['thought_signature']) ??
        _trimmedString(toolCall['thoughtSignature']);
    if (direct != null) {
      return direct;
    }

    final extraContent = _readMapValue(toolCall['extra_content'], 'extra_content');
    final google = _readMapValue(extraContent?['google'], 'extra_content.google');
    return _trimmedString(google?['thought_signature']) ??
        _trimmedString(google?['thoughtSignature']);
  }

  static String? _trimmedString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<UnifiedToolDeclaration> _parseTools(Object? rawTools) {
    final rawToolList = _readListValue(rawTools, 'tools');
    if (rawToolList == null) {
      return const [];
    }

    final tools = <UnifiedToolDeclaration>[];
    for (final rawTool in rawToolList) {
      if (rawTool is! Map) {
        continue;
      }
      final tool = _readRequiredMapValue(rawTool, 'tools[]');
      final function = _readMapValue(tool['function'], 'tools[].function') ?? tool;
      final name = _readStringValue(function['name'], 'tools[].function.name') ?? '';
      if (name.trim().isEmpty) {
        continue;
      }
      final parameters =
          _readMapValue(
            function['parametersJsonSchema'],
            'tools[].function.parametersJsonSchema',
          ) ??
          _readMapValue(function['parameters'], 'tools[].function.parameters') ??
          const {'type': 'object', 'properties': <String, Object?>{}};
      tools.add(
        UnifiedToolDeclaration(
          name: name,
          description:
              _readStringValue(function['description'], 'tools[].function.description') ?? '',
          parameters: parameters,
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
        final entry = _readRequiredMapValue(item, 'content[]');
        if (entry['type'] == 'text' && entry['text'] is String) {
          buffer.writeln((entry['text'] as String).trim());
        } else if (entry['type'] == 'image_url') {
          final imageUrl = entry['image_url'];
          final url = imageUrl is String
              ? imageUrl
              : _readStringValue(
                  _readMapValue(imageUrl, 'content[].image_url')?['url'],
                  'content[].image_url.url',
                );
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
      _appendContentItemAsPart(parts, _readRequiredMapValue(raw, 'content[]'));
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
      _appendContentItemAsPart(parts, _readRequiredMapValue(raw, 'content[]'));
    }
    return parts;
  }

  static void _appendContentItemAsPart(List<UnifiedPart> parts, Map<String, Object?> item) {
    final type = _readStringValue(item['type'], 'content[].type') ?? '';
    switch (type) {
      case 'reasoning':
      case 'reasoning_content':
      case 'summary_text':
        final text = _readStringValue(item['text'], 'content[].text')?.trim();
        if (text != null && text.isNotEmpty) {
          parts.add(
            UnifiedPart.thought(
              text: text,
              thoughtSignature: _readStringValue(
                item['thought_signature'],
                'content[].thought_signature',
              )?.trim(),
            ),
          );
        }
        break;
      case 'text':
      case 'input_text':
      case 'output_text':
        final text = _readStringValue(item['text'], 'content[].text')?.trim();
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
        final text = _readStringValue(item['text'], 'content[].text')?.trim();
        if (text != null && text.isNotEmpty) {
          parts.add(UnifiedPart.text(text));
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
        final thought = _readRequiredMapValue(rawThought, 'google_thoughts[]');
        final text = _readStringValue(thought['text'], 'google_thoughts[].text')?.trim() ?? '';
        final signature = _readStringValue(
          thought['signature'],
          'google_thoughts[].signature',
        )?.trim();
        if (text.isEmpty && (signature == null || signature.isEmpty)) {
          continue;
        }
        parts.add(UnifiedPart.thought(text: text, thoughtSignature: signature));
      }
      if (parts.isNotEmpty) {
        return parts;
      }
    }

    final reasoningText = _readStringValue(
      message['reasoning_content'],
      'reasoning_content',
    )?.trim();
    final reasoningSignature = _readStringValue(
      message['reasoning_signature'],
      'reasoning_signature',
    )?.trim();
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
      final entry = _readRequiredMapValue(rawPart, 'summary[]');
      final text = _readStringValue(entry['text'], 'summary[].text')?.trim() ?? '';
      final signature = _readStringValue(
        entry['thought_signature'],
        'summary[].thought_signature',
      )?.trim();
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
        : _readStringValue(_readMapValue(rawImage, 'image_url')?['url'], 'image_url.url');
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
    final file = _readRequiredMapValue(rawFile, 'file');
    final fileData = _readStringValue(file['file_data'], 'file.file_data')?.trim();
    final fileUrl =
        (_readStringValue(file['file_url'], 'file.file_url') ??
                _readStringValue(file['url'], 'file.url'))
            ?.trim();
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
      return _readRequiredMapValue(raw, 'arguments');
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return _readRequiredMapValue(decoded, 'arguments');
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
    final direct = _readStringValue(json['reasoning_effort'], 'reasoning_effort')?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final reasoning = _readMapField(json, 'reasoning');
    final effort = _readStringValue(reasoning?['effort'], 'reasoning.effort')?.trim();
    return effort == null || effort.isEmpty ? null : effort;
  }

  static Map<String, Object?>? _parseGoogleThinkingConfig(Map<String, Object?> json) {
    final extraBody = _readMapField(json, 'extra_body');
    final google = _readMapValue(extraBody?['google'], 'extra_body.google');
    final config =
        _readMapValue(google?['thinking_config'], 'extra_body.google.thinking_config') ??
        _readMapValue(google?['thinkingConfig'], 'extra_body.google.thinkingConfig');
    if (config == null || config.isEmpty) {
      return null;
    }
    return config;
  }

  static bool _parseGoogleWebSearchEnabled(Map<String, Object?> json) {
    final extraBody = _readMapField(json, 'extra_body');
    final google = _readMapValue(extraBody?['google'], 'extra_body.google');
    final directGoogle = _readMapField(json, 'google');
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
  final explicitMimeType = OpenAiRequestParser._readStringValue(
    file['mime_type'],
    'file.mime_type',
  )?.trim();
  if (explicitMimeType != null && explicitMimeType.isNotEmpty) {
    return explicitMimeType;
  }

  final filename = OpenAiRequestParser._readStringValue(file['filename'], 'file.filename')?.trim();
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
