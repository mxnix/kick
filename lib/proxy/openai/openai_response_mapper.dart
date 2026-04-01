import 'dart:convert';
import 'dart:math';

class OpenAiResponseMapper {
  static const int _minimumContinuationOverlap = 6;
  static const String _promptBlockedFallbackText =
      'Upstream blocked the prompt before generating a response.';
  static const Set<String> _contentFilteredFinishReasons = {
    'SAFETY',
    'RECITATION',
    'BLOCKLIST',
    'PROHIBITED_CONTENT',
    'SPII',
    'MODEL_ARMOR',
    'IMAGE_SAFETY',
    'IMAGE_PROHIBITED_CONTENT',
    'IMAGE_RECITATION',
  };

  static Map<String, Object?> toChatCompletion({
    required String requestId,
    required String model,
    required Map<String, Object?> payload,
    bool renderGoogleGroundingInMessage = true,
  }) {
    final extracted = _extractResponsePayload(
      payload,
      renderGoogleGroundingInMessage: renderGoogleGroundingInMessage,
    );

    return {
      'id': 'chatcmpl_$requestId',
      'object': 'chat.completion',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'model': model,
      'choices': [
        for (var index = 0; index < extracted.choices.length; index += 1)
          {
            'index': index,
            'message': {
              'role': 'assistant',
              'content': extracted.choices[index].text.isEmpty
                  ? null
                  : extracted.choices[index].text,
              if (extracted.choices[index].reasoningText.isNotEmpty)
                'reasoning_content': extracted.choices[index].reasoningText,
              if (extracted.choices[index].reasoningSignature != null)
                'reasoning_signature': extracted.choices[index].reasoningSignature,
              if (extracted.choices[index].googleThoughts.isNotEmpty)
                'google_thoughts': extracted.choices[index].googleThoughts,
              if (extracted.choices[index].googleGrounding.isNotEmpty)
                'google_grounding': extracted.choices[index].googleGrounding,
              if (extracted.choices[index].toolCalls.isNotEmpty)
                'tool_calls': extracted.choices[index].toolCalls,
            },
            'finish_reason': extracted.choices[index].toolCalls.isNotEmpty
                ? 'tool_calls'
                : extracted.choices[index].finishReason,
          },
      ],
      'usage': extracted.usage,
    };
  }

  static List<Map<String, Object?>> toChatStreamDeltas({
    required String requestId,
    required String model,
    required Map<String, Object?> payload,
    bool renderGoogleGroundingInMessage = true,
    required bool includeRole,
    required String previousText,
    required String previousReasoningText,
    required int previousToolCallCount,
  }) {
    final extracted = _extractPrimaryChoice(
      payload,
      renderGoogleGroundingInMessage: renderGoogleGroundingInMessage,
    );
    final streamText = payload['final_chunk'] == true && previousText.isEmpty
        ? extracted.text
        : extracted.rawText;
    final textDelta = _textDelta(previousText, streamText);
    final reasoningDelta = _textDelta(previousReasoningText, extracted.reasoningText);
    final toolCalls = extracted.toolCalls.length > previousToolCallCount
        ? extracted.toolCalls.sublist(previousToolCallCount)
        : const <Map<String, Object?>>[];
    final events = <Map<String, Object?>>[];

    if (includeRole) {
      events.add({
        'id': 'chatcmpl_$requestId',
        'object': 'chat.completion.chunk',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': model,
        'choices': [
          {
            'index': 0,
            'delta': {'role': 'assistant'},
            'finish_reason': null,
          },
        ],
      });
    }

    if (reasoningDelta.isNotEmpty) {
      events.add({
        'id': 'chatcmpl_$requestId',
        'object': 'chat.completion.chunk',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': model,
        'choices': [
          {
            'index': 0,
            'delta': {'reasoning_content': reasoningDelta},
            'finish_reason': null,
          },
        ],
      });
    }

    if (textDelta.isNotEmpty) {
      events.add({
        'id': 'chatcmpl_$requestId',
        'object': 'chat.completion.chunk',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': model,
        'choices': [
          {
            'index': 0,
            'delta': {'content': textDelta},
            'finish_reason': null,
          },
        ],
      });
    }

    if (toolCalls.isNotEmpty) {
      events.add({
        'id': 'chatcmpl_$requestId',
        'object': 'chat.completion.chunk',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': model,
        'choices': [
          {
            'index': 0,
            'delta': {'tool_calls': toolCalls},
            'finish_reason': null,
          },
        ],
      });
    }

    if (payload['final_chunk'] == true &&
        previousText.isNotEmpty &&
        extracted.sourcesText.isNotEmpty) {
      events.add({
        'id': 'chatcmpl_$requestId',
        'object': 'chat.completion.chunk',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': model,
        'choices': [
          {
            'index': 0,
            'delta': {'content': extracted.sourcesText},
            'finish_reason': null,
          },
        ],
      });
    }

    if (payload['final_chunk'] == true) {
      events.add({
        'id': 'chatcmpl_$requestId',
        'object': 'chat.completion.chunk',
        'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'model': model,
        'choices': [
          {
            'index': 0,
            'delta': const <String, Object?>{},
            'finish_reason': extracted.toolCalls.isNotEmpty ? 'tool_calls' : extracted.finishReason,
          },
        ],
        'usage': _extractResponsePayload(
          payload,
          renderGoogleGroundingInMessage: renderGoogleGroundingInMessage,
        ).usage,
      });
    }

    return events;
  }

  static Map<String, Object?> toResponsesObject({
    required String requestId,
    required String model,
    required Map<String, Object?> payload,
    bool renderGoogleGroundingInMessage = true,
  }) {
    final extractedResponse = _extractResponsePayload(
      payload,
      renderGoogleGroundingInMessage: renderGoogleGroundingInMessage,
    );
    final extracted = _extractPrimaryChoice(
      payload,
      renderGoogleGroundingInMessage: renderGoogleGroundingInMessage,
    );
    final output = <Map<String, Object?>>[];

    if (extracted.reasoningText.isNotEmpty || extracted.googleThoughts.isNotEmpty) {
      output.add({
        'id': 'rs_$requestId',
        'type': 'reasoning',
        'summary': extracted.reasoningText.isEmpty
            ? const <Map<String, Object?>>[]
            : [
                {'type': 'summary_text', 'text': extracted.reasoningText},
              ],
        if (extracted.reasoningSignature != null)
          'reasoning_signature': extracted.reasoningSignature,
        if (extracted.googleThoughts.isNotEmpty) 'google_thoughts': extracted.googleThoughts,
      });
    }

    if (extracted.toolCalls.isNotEmpty) {
      output.addAll(
        extracted.toolCalls.map(
          (toolCall) => {
            'id': toolCall['id'] ?? 'call_$requestId',
            'type': 'function_call',
            'status': 'completed',
            'call_id': toolCall['id'],
            'name': ((toolCall['function'] as Map?)?['name']),
            'arguments': ((toolCall['function'] as Map?)?['arguments']) ?? '{}',
          },
        ),
      );
    }

    output.add({
      'id': 'msg_$requestId',
      'type': 'message',
      'role': 'assistant',
      'status': 'completed',
      if (extracted.googleGrounding.isNotEmpty) 'google_grounding': extracted.googleGrounding,
      'content': [
        {
          'type': 'output_text',
          'text': extracted.text,
          'annotations': const [],
          'logprobs': const [],
        },
      ],
    });

    return {
      'id': 'resp_$requestId',
      'object': 'response',
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'status': 'completed',
      'model': model,
      'output': output,
      'parallel_tool_calls': true,
      'usage': {
        'input_tokens': _usageValue(extractedResponse.usage, 'prompt_tokens'),
        'input_tokens_details': {
          'cached_tokens': _usageValue(extractedResponse.usage, 'cached_tokens'),
        },
        'output_tokens': _usageValue(extractedResponse.usage, 'completion_tokens'),
        'output_tokens_details': {
          'reasoning_tokens': _usageValue(
            extractedResponse.usage['completion_tokens_details'] as Map<String, Object?>? ??
                const {},
            'reasoning_tokens',
          ),
        },
        'total_tokens': _usageValue(extractedResponse.usage, 'total_tokens'),
      },
      'error': null,
      'metadata': const <String, Object?>{},
    };
  }

  static List<Map<String, Object?>> toResponsesStreamEvents({
    required String requestId,
    required String model,
    required Map<String, Object?> payload,
    bool renderGoogleGroundingInMessage = true,
    required bool includePrelude,
    required String previousText,
    required String previousReasoningText,
    required int previousToolCallCount,
    required List<String> previousToolCallArguments,
  }) {
    final extracted = _extractPrimaryChoice(
      payload,
      renderGoogleGroundingInMessage: renderGoogleGroundingInMessage,
    );
    final responseObject = toResponsesObject(
      requestId: requestId,
      model: model,
      payload: payload,
      renderGoogleGroundingInMessage: renderGoogleGroundingInMessage,
    );
    final streamText = payload['final_chunk'] == true && previousText.isEmpty
        ? extracted.text
        : extracted.rawText;
    final textDelta = _textDelta(previousText, streamText);
    final reasoningDelta = _textDelta(previousReasoningText, extracted.reasoningText);
    final firstTextChunk = previousText.isEmpty && streamText.isNotEmpty;
    final responseId = 'resp_$requestId';
    final messageId = 'msg_$requestId';
    final reasoningId = 'rs_$requestId';
    final events = <Map<String, Object?>>[];
    final reasoningOffset = extracted.reasoningText.isNotEmpty ? 1 : 0;
    final messageOutputIndex = reasoningOffset + extracted.toolCalls.length;
    final currentToolCallArguments = extracted.toolCalls
        .map(_toolCallArguments)
        .toList(growable: false);

    if (includePrelude) {
      events.add({
        'type': 'response.created',
        'response': {
          'id': responseId,
          'object': 'response',
          'created_at': responseObject['created_at'],
        },
      });
    }

    if (firstTextChunk) {
      events.add({
        'type': 'response.output_item.added',
        'output_index': messageOutputIndex,
        'item': {
          'id': messageId,
          'type': 'message',
          'role': 'assistant',
          'status': 'in_progress',
          'content': const [],
        },
      });
      events.add({
        'type': 'response.content_part.added',
        'item_id': messageId,
        'output_index': messageOutputIndex,
        'content_index': 0,
        'part': {'type': 'output_text', 'text': '', 'annotations': const [], 'logprobs': const []},
      });
    }

    if (reasoningDelta.isNotEmpty) {
      events.add({
        'type': 'response.reasoning_summary_text.delta',
        'item_id': reasoningId,
        'output_index': 0,
        'delta': reasoningDelta,
      });
    }

    for (var index = 0; index < extracted.toolCalls.length; index += 1) {
      final toolCall = extracted.toolCalls[index];
      final function = (toolCall['function'] as Map?)?.cast<String, Object?>() ?? const {};
      final outputIndex = reasoningOffset + index;
      final arguments = currentToolCallArguments[index];
      final previousArguments = index < previousToolCallArguments.length
          ? previousToolCallArguments[index]
          : '';

      if (index >= previousToolCallCount) {
        events.add({
          'type': 'response.output_item.added',
          'output_index': outputIndex,
          'item': {
            'id': toolCall['id'],
            'type': 'function_call',
            'call_id': toolCall['id'],
            'name': function['name'],
            'arguments': '',
            'status': 'in_progress',
          },
        });
      }

      final argumentsDelta = _toolArgumentsDelta(previousArguments, arguments);
      if (argumentsDelta.isNotEmpty && arguments != '{}') {
        events.add({
          'type': 'response.function_call_arguments.delta',
          'item_id': toolCall['id'],
          'output_index': outputIndex,
          'delta': argumentsDelta,
        });
      }
    }

    if (textDelta.isNotEmpty) {
      events.add({
        'type': 'response.output_text.delta',
        'item_id': messageId,
        'output_index': messageOutputIndex,
        'content_index': 0,
        'delta': textDelta,
        'logprobs': const [],
      });
    }

    if (payload['final_chunk'] == true) {
      if (previousText.isNotEmpty && extracted.sourcesText.isNotEmpty) {
        events.add({
          'type': 'response.output_text.delta',
          'item_id': messageId,
          'output_index': messageOutputIndex,
          'content_index': 0,
          'delta': extracted.sourcesText,
          'logprobs': const [],
        });
      }

      for (var index = 0; index < extracted.toolCalls.length; index += 1) {
        final toolCall = extracted.toolCalls[index];
        final function = (toolCall['function'] as Map?)?.cast<String, Object?>() ?? const {};
        events.add({
          'type': 'response.function_call_arguments.done',
          'item_id': toolCall['id'],
          'output_index': reasoningOffset + index,
          'arguments': function['arguments'] ?? '{}',
        });
        events.add({
          'type': 'response.output_item.done',
          'output_index': reasoningOffset + index,
          'item': {
            'id': toolCall['id'],
            'type': 'function_call',
            'call_id': toolCall['id'],
            'name': function['name'],
            'arguments': function['arguments'] ?? '{}',
            'status': 'completed',
          },
        });
      }

      final shouldEmitMessageDone = extracted.text.isNotEmpty || previousText.isNotEmpty;
      if (shouldEmitMessageDone) {
        events.add({
          'type': 'response.output_text.done',
          'item_id': messageId,
          'output_index': messageOutputIndex,
          'content_index': 0,
          'text': extracted.text,
          'logprobs': const [],
        });
        events.add({
          'type': 'response.content_part.done',
          'item_id': messageId,
          'output_index': messageOutputIndex,
          'content_index': 0,
          'part': {
            'type': 'output_text',
            'text': extracted.text,
            'annotations': const [],
            'logprobs': const [],
          },
        });
        events.add({
          'type': 'response.output_item.done',
          'output_index': messageOutputIndex,
          'item': {
            'id': messageId,
            'type': 'message',
            'role': 'assistant',
            'status': 'completed',
            if (extracted.googleGrounding.isNotEmpty) 'google_grounding': extracted.googleGrounding,
            'content': [
              {
                'type': 'output_text',
                'text': extracted.text,
                'annotations': const [],
                'logprobs': const [],
              },
            ],
          },
        });
      }
      events.add({'type': 'response.completed', 'response': responseObject});
    }

    return events;
  }

  static String currentText(Map<String, Object?> payload) {
    return _extractPrimaryChoice(payload).rawText;
  }

  static String currentReasoningText(Map<String, Object?> payload) {
    return _extractPrimaryChoice(payload).reasoningText;
  }

  static String currentFinishReason(Map<String, Object?> payload) {
    return _extractPrimaryChoice(payload).finishReason;
  }

  static String? currentTraceId(Map<String, Object?> payload) {
    return _nonEmptyString(payload['traceId']);
  }

  static String? currentUpstreamResponseId(Map<String, Object?> payload) {
    final response = _rawResponseMap(payload);
    return _nonEmptyString(response['responseId']);
  }

  static String? currentModelVersion(Map<String, Object?> payload) {
    final response = _rawResponseMap(payload);
    return _nonEmptyString(response['modelVersion']);
  }

  static int? currentPromptTokenCount(Map<String, Object?> payload) {
    return _usageIntValue(payload, 'promptTokenCount');
  }

  static int? currentCompletionTokenCount(Map<String, Object?> payload) {
    return _usageIntValue(payload, 'candidatesTokenCount');
  }

  static int? currentTotalTokenCount(Map<String, Object?> payload) {
    return _usageIntValue(payload, 'totalTokenCount');
  }

  static int? currentCachedTokenCount(Map<String, Object?> payload) {
    return _usageIntValue(payload, 'cachedContentTokenCount');
  }

  static int? currentReasoningTokenCount(Map<String, Object?> payload) {
    return _usageIntValue(payload, 'thoughtsTokenCount');
  }

  static int currentToolCallCount(Map<String, Object?> payload) {
    return _extractPrimaryChoice(payload).toolCalls.length;
  }

  static List<String> currentToolCallArguments(Map<String, Object?> payload) {
    return _extractPrimaryChoice(payload).toolCalls.map(_toolCallArguments).toList(growable: false);
  }

  static _ExtractedResponse _extractResponsePayload(
    Map<String, Object?> payload, {
    bool renderGoogleGroundingInMessage = true,
  }) {
    final response = (payload['response'] as Map?)?.cast<String, Object?>() ?? payload;
    final candidates = (response['candidates'] as List?) ?? const [];
    final extractedChoices = <_ExtractedChoice>[];

    for (final rawCandidate in candidates) {
      if (rawCandidate is! Map) {
        continue;
      }
      extractedChoices.add(
        _extractChoice(
          rawCandidate.cast<String, Object?>(),
          renderGoogleGroundingInMessage: renderGoogleGroundingInMessage,
        ),
      );
    }

    final usageMetadata =
        (response['usageMetadata'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    return _ExtractedResponse(
      choices: extractedChoices.isEmpty
          ? [_fallbackChoiceForEmptyResponse(response)]
          : extractedChoices,
      usage: {
        'prompt_tokens': usageMetadata['promptTokenCount'] ?? 0,
        'completion_tokens': usageMetadata['candidatesTokenCount'] ?? 0,
        'total_tokens': usageMetadata['totalTokenCount'] ?? 0,
        'cached_tokens': usageMetadata['cachedContentTokenCount'] ?? 0,
        'prompt_tokens_details': {'cached_tokens': usageMetadata['cachedContentTokenCount'] ?? 0},
        'completion_tokens_details': {'reasoning_tokens': usageMetadata['thoughtsTokenCount'] ?? 0},
      },
    );
  }

  static _ExtractedChoice _fallbackChoiceForEmptyResponse(Map<String, Object?> response) {
    final promptFeedback =
        (response['promptFeedback'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    if (promptFeedback.isNotEmpty) {
      final blockReasonMessage = (promptFeedback['blockReasonMessage'] as String?)?.trim();
      if (blockReasonMessage != null && blockReasonMessage.isNotEmpty) {
        return _ExtractedChoice(
          text: '[$_promptBlockedFallbackText $blockReasonMessage]',
          rawText: '[$_promptBlockedFallbackText $blockReasonMessage]',
          sourcesText: '',
          googleGrounding: const <String, Object?>{},
          reasoningText: '',
          googleThoughts: const <Map<String, Object?>>[],
          toolCalls: const <Map<String, Object?>>[],
          finishReason: 'content_filter',
        );
      }
      return const _ExtractedChoice(
        text: '[$_promptBlockedFallbackText]',
        rawText: '[$_promptBlockedFallbackText]',
        sourcesText: '',
        googleGrounding: <String, Object?>{},
        reasoningText: '',
        googleThoughts: <Map<String, Object?>>[],
        toolCalls: <Map<String, Object?>>[],
        finishReason: 'content_filter',
      );
    }

    return const _ExtractedChoice(
      text: '[Upstream returned an empty response. Please retry.]',
      rawText: '[Upstream returned an empty response. Please retry.]',
      sourcesText: '',
      googleGrounding: <String, Object?>{},
      reasoningText: '',
      googleThoughts: <Map<String, Object?>>[],
      toolCalls: <Map<String, Object?>>[],
      finishReason: 'stop',
    );
  }

  static _ExtractedChoice _extractPrimaryChoice(
    Map<String, Object?> payload, {
    bool renderGoogleGroundingInMessage = true,
  }) {
    return _extractResponsePayload(
      payload,
      renderGoogleGroundingInMessage: renderGoogleGroundingInMessage,
    ).choices.first;
  }

  static Map<String, Object?> _rawResponseMap(Map<String, Object?> payload) {
    return (payload['response'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
  }

  static Map<String, Object?> _rawUsageMetadata(Map<String, Object?> payload) {
    final response = _rawResponseMap(payload);
    return (response['usageMetadata'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
  }

  static int? _usageIntValue(Map<String, Object?> payload, String key) {
    return _parseInt(_rawUsageMetadata(payload)[key]);
  }

  static String? _nonEmptyString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  static int? _parseInt(Object? value) {
    return switch (value) {
      int integer => integer,
      num number => number.toInt(),
      String text => int.tryParse(text.trim()),
      _ => null,
    };
  }

  static _ExtractedChoice _extractChoice(
    Map<String, Object?> candidate, {
    bool renderGoogleGroundingInMessage = true,
  }) {
    final content =
        (candidate['content'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    final parts = (content['parts'] as List?) ?? const [];

    final textBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final googleThoughts = <Map<String, Object?>>[];
    final toolCalls = <Map<String, Object?>>[];

    for (final rawPart in parts) {
      if (rawPart is! Map) {
        continue;
      }
      final part = rawPart.cast<String, Object?>();
      if (part['thought'] == true) {
        final thoughtText = part['text'] as String? ?? '';
        final thoughtSignature = (part['thoughtSignature'] as String?)?.trim();
        if (thoughtText.isNotEmpty) {
          reasoningBuffer.write(thoughtText);
        }
        if (thoughtText.isNotEmpty || thoughtSignature != null) {
          googleThoughts.add({
            if (thoughtText.isNotEmpty) 'text': thoughtText,
            if (thoughtSignature != null && thoughtSignature.isNotEmpty)
              'signature': thoughtSignature,
          });
        }
        continue;
      }

      if (part['text'] is String) {
        textBuffer.write(part['text'] as String);
      }

      final functionCall = (part['functionCall'] as Map?)?.cast<String, Object?>();
      if (functionCall != null) {
        final toolIndex = toolCalls.length;
        final explicitId = (functionCall['id'] as String?)?.trim();
        toolCalls.add({
          'id': explicitId == null || explicitId.isEmpty ? 'call_${toolIndex + 1}' : explicitId,
          'type': 'function',
          'index': toolIndex,
          'function': {
            'name': functionCall['name'] as String? ?? 'tool',
            'arguments': _stringifyJson(functionCall['args']),
          },
        });
      }
    }

    var rawText = textBuffer.toString();
    final reasoningText = reasoningBuffer.toString();
    final rawFinishReason = candidate['finishReason'] as String?;
    final finishReason = _mapFinishReason(rawFinishReason);
    if (rawFinishReason != null &&
        rawText.trim().isEmpty &&
        reasoningText.trim().isEmpty &&
        toolCalls.isEmpty) {
      rawText = _emptyResponseFallbackText(
        finishReason,
        finishMessage: (candidate['finishMessage'] as String?)?.trim(),
      );
    }
    final grounding = _extractGrounding(candidate);
    final googleGrounding = _groundingToJson(grounding);
    final sourcesText = renderGoogleGroundingInMessage ? _formatGroundingSources(grounding) : '';
    final text = _formatGroundedText(
      rawText,
      grounding,
      sourcesText: sourcesText,
      renderGoogleGroundingInMessage: renderGoogleGroundingInMessage,
    );

    return _ExtractedChoice(
      text: text,
      rawText: rawText,
      sourcesText: sourcesText,
      googleGrounding: googleGrounding,
      reasoningText: reasoningText,
      googleThoughts: googleThoughts,
      toolCalls: toolCalls,
      finishReason: finishReason,
    );
  }

  static int _usageValue(Map<String, Object?> usage, String key) {
    return (usage[key] as num?)?.toInt() ?? 0;
  }

  static String _mapFinishReason(String? finishReason) {
    if (finishReason == 'MAX_TOKENS') {
      return 'length';
    }
    if (finishReason != null && _contentFilteredFinishReasons.contains(finishReason)) {
      return 'content_filter';
    }
    return 'stop';
  }

  static String _emptyResponseFallbackText(String finishReason, {String? finishMessage}) {
    if (finishMessage != null && finishMessage.isNotEmpty) {
      return '[Upstream returned no text. $finishMessage]';
    }
    switch (finishReason) {
      case 'length':
        return '[Upstream returned no text before reaching the token limit.]';
      case 'content_filter':
        return '[Upstream returned no text because the response was filtered.]';
      default:
        return '[Upstream returned an empty response. Please retry.]';
    }
  }

  static String _stringifyJson(Object? value) {
    if (value == null) {
      return '{}';
    }
    if (value is String) {
      return value;
    }
    return jsonEncode(value);
  }

  static String _toolCallArguments(Map<String, Object?> toolCall) {
    final function = (toolCall['function'] as Map?)?.cast<String, Object?>();
    return (function?['arguments'] as String?) ?? '';
  }

  static _ExtractedGrounding? _extractGrounding(Map<String, Object?> candidate) {
    final groundingMetadata =
        (candidate['groundingMetadata'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    if (groundingMetadata.isEmpty) {
      return null;
    }

    final chunks = <_GroundingChunk>[];
    for (final rawChunk in (groundingMetadata['groundingChunks'] as List?) ?? const []) {
      if (rawChunk is! Map) {
        continue;
      }
      final chunk = rawChunk.cast<String, Object?>();
      final web = (chunk['web'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
      final title = (web['title'] as String?)?.trim() ?? '';
      final uri = (web['uri'] as String?)?.trim() ?? '';
      if (title.isEmpty && uri.isEmpty) {
        continue;
      }
      chunks.add(_GroundingChunk(title: title, uri: uri));
    }

    final supports = <_GroundingSupport>[];
    for (final rawSupport in (groundingMetadata['groundingSupports'] as List?) ?? const []) {
      if (rawSupport is! Map) {
        continue;
      }
      final support = rawSupport.cast<String, Object?>();
      final segment =
          (support['segment'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
      final endIndex = _parseInt(segment['endIndex']);
      if (endIndex == null) {
        continue;
      }
      final groundingChunkIndices = ((support['groundingChunkIndices'] as List?) ?? const [])
          .map(_parseInt)
          .whereType<int>()
          .toList(growable: false);
      if (groundingChunkIndices.isEmpty) {
        continue;
      }
      supports.add(
        _GroundingSupport(endIndex: endIndex, groundingChunkIndices: groundingChunkIndices),
      );
    }

    if (chunks.isEmpty && supports.isEmpty) {
      return null;
    }
    return _ExtractedGrounding(chunks: chunks, supports: supports);
  }

  static String _formatGroundedText(
    String text,
    _ExtractedGrounding? grounding, {
    required String sourcesText,
    required bool renderGoogleGroundingInMessage,
  }) {
    if (text.isEmpty || grounding == null || !renderGoogleGroundingInMessage) {
      return text;
    }
    final withCitations = _insertGroundingCitations(text, grounding);
    return sourcesText.isEmpty ? withCitations : '$withCitations$sourcesText';
  }

  static Map<String, Object?> _groundingToJson(_ExtractedGrounding? grounding) {
    if (grounding == null || grounding.chunks.isEmpty) {
      return const <String, Object?>{};
    }

    return {
      'sources': [
        for (var index = 0; index < grounding.chunks.length; index += 1)
          {
            'index': index + 1,
            'title': grounding.chunks[index].title.isEmpty
                ? 'Untitled'
                : grounding.chunks[index].title,
            'uri': grounding.chunks[index].uri,
          },
      ],
      if (grounding.supports.isNotEmpty)
        'supports': [
          for (final support in grounding.supports)
            {
              'end_index': support.endIndex,
              'source_indices': support.groundingChunkIndices
                  .map((index) => index + 1)
                  .toList(growable: false),
            },
        ],
    };
  }

  static String _insertGroundingCitations(String text, _ExtractedGrounding grounding) {
    if (grounding.supports.isEmpty) {
      return text;
    }

    final insertions =
        grounding.supports
            .map(
              (support) => _GroundingInsertion(
                index: support.endIndex,
                marker: support.groundingChunkIndices.map((index) => '[${index + 1}]').join(),
              ),
            )
            .where((insertion) => insertion.marker.isNotEmpty)
            .toList(growable: false)
          ..sort((a, b) => b.index.compareTo(a.index));

    if (insertions.isEmpty) {
      return text;
    }

    final textBytes = utf8.encode(text);
    final parts = <List<int>>[];
    var lastIndex = textBytes.length;
    for (final insertion in insertions) {
      final position = min(max(insertion.index, 0), lastIndex);
      parts.insert(0, textBytes.sublist(position, lastIndex));
      parts.insert(0, utf8.encode(insertion.marker));
      lastIndex = position;
    }
    parts.insert(0, textBytes.sublist(0, lastIndex));

    final outputBytes = <int>[];
    for (final part in parts) {
      outputBytes.addAll(part);
    }
    return utf8.decode(outputBytes);
  }

  static String _formatGroundingSources(_ExtractedGrounding? grounding) {
    if (grounding == null || grounding.chunks.isEmpty) {
      return '';
    }

    final sourceLines = <String>[];
    for (var index = 0; index < grounding.chunks.length; index += 1) {
      final chunk = grounding.chunks[index];
      final title = chunk.title.isEmpty ? 'Untitled' : chunk.title;
      final uri = chunk.uri.isEmpty ? 'No URI' : chunk.uri;
      sourceLines.add('[${index + 1}] $title ($uri)');
    }
    return '\n\nSources:\n${sourceLines.join('\n')}';
  }

  static String _toolArgumentsDelta(String previousArguments, String currentArguments) {
    if (previousArguments.isEmpty) {
      return currentArguments;
    }
    if (currentArguments.isEmpty ||
        previousArguments == currentArguments ||
        currentArguments.length <= previousArguments.length &&
            previousArguments.startsWith(currentArguments)) {
      return '';
    }
    if (currentArguments.startsWith(previousArguments)) {
      return currentArguments.substring(previousArguments.length);
    }

    var commonPrefixLength = 0;
    final maxLength = min(previousArguments.length, currentArguments.length);
    while (commonPrefixLength < maxLength &&
        previousArguments.codeUnitAt(commonPrefixLength) ==
            currentArguments.codeUnitAt(commonPrefixLength)) {
      commonPrefixLength += 1;
    }
    return currentArguments.substring(commonPrefixLength);
  }

  static String _textDelta(String previousText, String currentText) {
    if (previousText.isNotEmpty && currentText.startsWith(previousText)) {
      return currentText.substring(previousText.length);
    }

    if (previousText.isEmpty || currentText.isEmpty) {
      return currentText;
    }

    if (previousText == currentText ||
        previousText.startsWith(currentText) ||
        previousText.contains(currentText)) {
      return '';
    }

    final previousIndex = currentText.indexOf(previousText);
    if (previousIndex >= 0) {
      return currentText.substring(previousIndex + previousText.length);
    }

    final maxOverlap = min(previousText.length, currentText.length);
    for (var overlap = maxOverlap; overlap > 0; overlap -= 1) {
      if (overlap < _minimumContinuationOverlap) {
        break;
      }
      final suffix = previousText.substring(previousText.length - overlap);
      final matchIndex = currentText.indexOf(suffix);
      if (matchIndex >= 0) {
        return currentText.substring(matchIndex + overlap);
      }
    }

    return currentText;
  }
}

class _ExtractedResponse {
  const _ExtractedResponse({required this.choices, required this.usage});

  final List<_ExtractedChoice> choices;
  final Map<String, Object?> usage;
}

class _ExtractedChoice {
  const _ExtractedChoice({
    required this.text,
    required this.rawText,
    required this.sourcesText,
    required this.googleGrounding,
    required this.reasoningText,
    required this.googleThoughts,
    required this.toolCalls,
    required this.finishReason,
  });

  final String text;
  final String rawText;
  final String sourcesText;
  final Map<String, Object?> googleGrounding;
  final String reasoningText;
  final List<Map<String, Object?>> googleThoughts;
  final List<Map<String, Object?>> toolCalls;
  final String finishReason;

  String? get reasoningSignature {
    if (googleThoughts.length != 1) {
      return null;
    }
    return googleThoughts.single['signature'] as String?;
  }
}

class _ExtractedGrounding {
  const _ExtractedGrounding({required this.chunks, required this.supports});

  final List<_GroundingChunk> chunks;
  final List<_GroundingSupport> supports;
}

class _GroundingChunk {
  const _GroundingChunk({required this.title, required this.uri});

  final String title;
  final String uri;
}

class _GroundingSupport {
  const _GroundingSupport({required this.endIndex, required this.groundingChunkIndices});

  final int endIndex;
  final List<int> groundingChunkIndices;
}

class _GroundingInsertion {
  const _GroundingInsertion({required this.index, required this.marker});

  final int index;
  final String marker;
}
