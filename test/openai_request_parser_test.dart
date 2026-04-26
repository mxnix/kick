import 'package:flutter_test/flutter_test.dart';
import 'package:kick/proxy/openai/openai_request_parser.dart';

void main() {
  test('parses chat completions into unified turns and system instruction', () {
    final request = OpenAiRequestParser.parseChatRequest({
      'model': 'gemini-2.5-flash',
      'stream': true,
      'temperature': 0.7,
      'stop': ['END'],
      'reasoning_effort': 'high',
      'modalities': ['text'],
      'extra_body': {
        'google': {
          'thinking_config': {'thinkingBudget': 512, 'includeThoughts': true},
        },
      },
      'messages': [
        {'role': 'system', 'content': 'You are helpful.'},
        {'role': 'developer', 'content': 'Prefer short answers.'},
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Hello'},
            {
              'type': 'image_url',
              'image_url': {'url': 'https://example.com/cat.png'},
            },
          ],
        },
        {
          'role': 'assistant',
          'content': 'Checking',
          'reasoning_content': 'Need weather lookup.',
          'reasoning_signature': 'sig_weather',
          'google_thoughts': [
            {'text': 'Need weather lookup.', 'signature': 'sig_weather'},
          ],
          'tool_calls': [
            {
              'id': 'call_1',
              'function': {'name': 'lookupWeather', 'arguments': '{"city":"Moscow"}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'call_1', 'content': 'Cold'},
      ],
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'lookupWeather',
            'description': 'Weather lookup',
            'parametersJsonSchema': {
              'type': 'object',
              'properties': {
                'city': {'type': 'string'},
              },
            },
          },
        },
      ],
      'response_format': {
        'type': 'json_schema',
        'json_schema': {
          'schema': {'type': 'object'},
        },
      },
    }, requestId: 'req_chat');

    expect(request.requestId, 'req_chat');
    expect(request.model, 'gemini-2.5-flash');
    expect(request.stream, isTrue);
    expect(request.systemInstruction, 'You are helpful.\n\nPrefer short answers.');
    expect(request.tools.single.name, 'lookupWeather');
    expect(request.jsonMode, isTrue);
    expect(request.responseSchema?['type'], 'object');
    expect(request.stopSequences, ['END']);
    expect(request.reasoningEffort, 'high');
    expect(request.responseModalities, ['text']);
    expect(request.googleThinkingConfig?['thinkingBudget'], 512);
    expect(request.googleWebSearchEnabled, isFalse);
    expect(request.turns, hasLength(3));
    expect(request.turns.first.role, 'user');
    expect(request.turns.first.parts[0].type, UnifiedPartType.text);
    expect(request.turns.first.parts[0].text, 'Hello');
    expect(request.turns.first.parts[1].type, UnifiedPartType.fileData);
    expect(request.turns.first.parts[1].fileUri, 'https://example.com/cat.png');
    expect(request.turns.first.parts[1].mimeType, 'image/png');
    expect(request.turns[1].role, 'assistant');
    expect(request.turns[1].parts.first.type, UnifiedPartType.thought);
    expect(request.turns[1].parts.first.text, 'Need weather lookup.');
    expect(request.turns[1].parts.first.thoughtSignature, 'sig_weather');
    expect(request.turns[1].parts.last.name, 'lookupWeather');
    expect(request.turns[2].parts.single.type, UnifiedPartType.functionResponse);
    expect(request.turns[2].parts.single.arguments?['result'], 'Cold');
  });

  test('parses responses input and function outputs', () {
    final request = OpenAiRequestParser.parseResponsesRequest({
      'model': 'gemini-2.5-pro',
      'instructions': 'Stay in character.',
      'stream': false,
      'max_output_tokens': 512,
      'reasoning': {'effort': 'medium'},
      'input': [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'Tell me a joke'},
            {
              'type': 'input_image',
              'image_url': {'url': 'data:image/png;base64,ZmFrZQ=='},
            },
          ],
        },
        {
          'type': 'reasoning',
          'reasoning_signature': 'sig_fact',
          'google_thoughts': [
            {'text': 'Need an external fact.', 'signature': 'sig_fact'},
          ],
          'summary': [
            {'type': 'summary_text', 'text': 'Need an external fact.'},
          ],
        },
        {
          'type': 'function_call',
          'call_id': 'call_9',
          'name': 'fetchFact',
          'arguments': '{"topic":"banana"}',
        },
        {
          'type': 'function_call_output',
          'call_id': 'call_9',
          'name': 'fetchFact',
          'output': 'Bananas are berries.',
        },
      ],
    }, requestId: 'req_resp');

    expect(request.requestId, 'req_resp');
    expect(request.model, 'gemini-2.5-pro');
    expect(request.systemInstruction, 'Stay in character.');
    expect(request.maxOutputTokens, 512);
    expect(request.reasoningEffort, 'medium');
    expect(request.googleWebSearchEnabled, isFalse);
    expect(request.turns, hasLength(4));
    expect(request.turns.first.parts.first.text, 'Tell me a joke');
    expect(request.turns.first.parts[1].type, UnifiedPartType.inlineData);
    expect(request.turns.first.parts[1].mimeType, 'image/png');
    expect(request.turns.first.parts[1].data, 'ZmFrZQ==');
    expect(request.turns[1].role, 'assistant');
    expect(request.turns[1].parts.single.type, UnifiedPartType.thought);
    expect(request.turns[1].parts.single.text, 'Need an external fact.');
    expect(request.turns[1].parts.single.thoughtSignature, 'sig_fact');
    expect(request.turns[2].parts.single.type, UnifiedPartType.functionCall);
    expect(request.turns[2].parts.single.name, 'fetchFact');
    expect(request.turns.last.parts.single.type, UnifiedPartType.functionResponse);
    expect(request.turns.last.parts.single.name, 'fetchFact');
    expect(request.turns.last.parts.single.arguments?['result'], 'Bananas are berries.');
  });

  test('parses Google thought signatures attached to OpenAI tool calls', () {
    final request = OpenAiRequestParser.parseChatRequest({
      'model': 'gemini-3.1-pro-preview',
      'messages': [
        {'role': 'user', 'content': 'Read the file'},
        {
          'role': 'assistant',
          'tool_calls': [
            {
              'id': 'call_read',
              'type': 'function',
              'extra_content': {
                'google': {'thought_signature': 'sig_read_file'},
              },
              'function': {'name': 'default_api:read_file', 'arguments': '{"path":"README.md"}'},
            },
          ],
        },
      ],
    }, requestId: 'req_tool_sig');

    final functionCall = request.turns.last.parts.single;

    expect(functionCall.type, UnifiedPartType.functionCall);
    expect(functionCall.name, 'default_api:read_file');
    expect(functionCall.thoughtSignature, 'sig_read_file');
  });

  test('keeps only leading system and developer notes in system instruction', () {
    final request = OpenAiRequestParser.parseChatRequest({
      'model': 'gemini-2.5-pro',
      'messages': [
        {'role': 'system', 'content': 'Lead instruction.'},
        {'role': 'user', 'content': 'Hello'},
        {'role': 'developer', 'content': 'Late policy update.'},
        {'role': 'assistant', 'content': 'Hi there'},
      ],
    }, requestId: 'req_late_system');

    expect(request.systemInstruction, 'Lead instruction.');
    expect(request.turns, hasLength(3));
    expect(request.turns.first.role, 'user');
    expect(request.turns.first.parts.single.text, 'Hello');
    expect(request.turns[1].role, 'user');
    expect(request.turns[1].parts.single.text, 'Late policy update.');
    expect(request.turns.last.role, 'assistant');
    expect(request.turns.last.parts.single.text, 'Hi there');
  });

  test('preserves trailing system messages as user turns after assistant prefills', () {
    final request = OpenAiRequestParser.parseChatRequest({
      'model': 'gemini-3.1-pro-preview',
      'messages': [
        {'role': 'system', 'content': 'You are a roleplay director.'},
        {'role': 'assistant', 'content': 'Previous character reply.'},
        {'role': 'assistant', 'content': '<think>'},
        {'role': 'system', 'content': 'Pause roleplay and write the memory book.'},
      ],
    }, requestId: 'req_trailing_system_after_assistant');

    expect(request.systemInstruction, 'You are a roleplay director.');
    expect(request.turns, hasLength(3));
    expect(request.turns[0].role, 'assistant');
    expect(request.turns[0].parts.single.text, 'Previous character reply.');
    expect(request.turns[1].role, 'assistant');
    expect(request.turns[1].parts.single.text, '<think>');
    expect(request.turns[2].role, 'user');
    expect(request.turns[2].parts.single.text, 'Pause roleplay and write the memory book.');
  });

  test('falls back to a user turn when chat contains only system messages', () {
    final request = OpenAiRequestParser.parseChatRequest({
      'model': 'gemini-2.5-pro',
      'messages': [
        {'role': 'system', 'content': 'Rules only.'},
      ],
    }, requestId: 'req_system_only');

    expect(request.systemInstruction, isNull);
    expect(request.turns, hasLength(1));
    expect(request.turns.single.role, 'user');
    expect(request.turns.single.parts.single.text, 'Rules only.');
  });

  test('parses google web search opt-in from extra_body', () {
    final request = OpenAiRequestParser.parseChatRequest({
      'model': 'gemini-3-flash-preview',
      'messages': [
        {'role': 'user', 'content': 'Find fresh Flutter news'},
      ],
      'extra_body': {
        'google': {'web_search': true},
      },
    }, requestId: 'req_search');

    expect(request.googleWebSearchEnabled, isTrue);
  });

  test('parses google web search opt-in from top-level compatibility flag', () {
    final request = OpenAiRequestParser.parseChatRequest({
      'model': 'gemini-3-flash-preview',
      'messages': [
        {'role': 'user', 'content': 'Find fresh Flutter news'},
      ],
      'web_search': 'true',
    }, requestId: 'req_search_top_level');

    expect(request.googleWebSearchEnabled, isTrue);
  });

  test('allows mixing google web search with function tools in chat requests', () {
    final request = OpenAiRequestParser.parseChatRequest({
      'model': 'gemini-3-flash-preview',
      'messages': [
        {'role': 'user', 'content': 'Find fresh Flutter news and summarize it'},
      ],
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'lookupWeather',
            'parameters': {'type': 'object'},
          },
        },
      ],
      'extra_body': {
        'google': {'web_search': true},
      },
    }, requestId: 'req_search_tools');

    expect(request.googleWebSearchEnabled, isTrue);
    expect(request.tools.single.name, 'lookupWeather');
  });

  test('allows mixing google web search with function tools in responses requests', () {
    final request = OpenAiRequestParser.parseResponsesRequest({
      'model': 'gemini-3-flash-preview',
      'input': 'Find fresh Flutter news and summarize it',
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'lookupWeather',
            'parameters': {'type': 'object'},
          },
        },
      ],
      'google': {'web_search': true},
    }, requestId: 'req_search_tools_responses');

    expect(request.googleWebSearchEnabled, isTrue);
    expect(request.tools.single.name, 'lookupWeather');
  });
}
