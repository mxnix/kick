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
            'parameters': {
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

  test('keeps non-leading developer notes in chat history order', () {
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
    expect(request.turns[1].role, 'user');
    expect(request.turns[1].parts.single.text, 'Late policy update.');
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
}
