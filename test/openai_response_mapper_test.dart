import 'package:flutter_test/flutter_test.dart';
import 'package:kick/proxy/openai/openai_response_mapper.dart';

void main() {
  test('chat stream emits only fresh text delta for cumulative Gemini payloads', () {
    final firstPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Привет!'},
              ],
            },
          },
        ],
      },
    };

    final secondPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Привет! Чем я могу вам помочь?'},
              ],
            },
          },
        ],
      },
    };

    final firstEvents = OpenAiResponseMapper.toChatStreamDeltas(
      requestId: 'req_1',
      model: 'gemini-3-flash-preview',
      payload: firstPayload,
      includeRole: true,
      previousText: '',
      previousReasoningText: '',
      previousToolCallCount: 0,
    );
    final secondEvents = OpenAiResponseMapper.toChatStreamDeltas(
      requestId: 'req_1',
      model: 'gemini-3-flash-preview',
      payload: secondPayload,
      includeRole: false,
      previousText: OpenAiResponseMapper.currentText(firstPayload),
      previousReasoningText: OpenAiResponseMapper.currentReasoningText(firstPayload),
      previousToolCallCount: OpenAiResponseMapper.currentToolCallCount(firstPayload),
    );

    expect(((firstEvents[1]['choices'] as List).single as Map)['delta'], {'content': 'Привет!'});
    expect(((secondEvents.single['choices'] as List).single as Map)['delta'], {
      'content': ' Чем я могу вам помочь?',
    });
  });

  test('responses stream emits only fresh text delta for cumulative Gemini payloads', () {
    final firstPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Привет!'},
              ],
            },
          },
        ],
      },
    };

    final secondPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Привет! Чем я могу вам помочь?'},
              ],
            },
          },
        ],
      },
    };

    final firstEvents = OpenAiResponseMapper.toResponsesStreamEvents(
      requestId: 'resp_1',
      model: 'gemini-3-flash-preview',
      payload: firstPayload,
      includePrelude: true,
      previousText: '',
      previousReasoningText: '',
      previousToolCallCount: 0,
      previousToolCallArguments: const [],
    );
    final secondEvents = OpenAiResponseMapper.toResponsesStreamEvents(
      requestId: 'resp_1',
      model: 'gemini-3-flash-preview',
      payload: secondPayload,
      includePrelude: false,
      previousText: OpenAiResponseMapper.currentText(firstPayload),
      previousReasoningText: OpenAiResponseMapper.currentReasoningText(firstPayload),
      previousToolCallCount: OpenAiResponseMapper.currentToolCallCount(firstPayload),
      previousToolCallArguments: OpenAiResponseMapper.currentToolCallArguments(firstPayload),
    );

    expect(firstEvents[3]['delta'], 'Привет!');
    expect(secondEvents.single['delta'], ' Чем я могу вам помочь?');
  });

  test('chat stream trims suffix-prefix overlap between continuation passes', () {
    final previousPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'softly, her eyes'},
              ],
            },
          },
        ],
      },
    };

    final continuedPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'her eyes sparkling with warmth.'},
              ],
            },
          },
        ],
      },
    };

    final events = OpenAiResponseMapper.toChatStreamDeltas(
      requestId: 'req_overlap',
      model: 'gemini-3-flash-preview',
      payload: continuedPayload,
      includeRole: false,
      previousText: OpenAiResponseMapper.currentText(previousPayload),
      previousReasoningText: OpenAiResponseMapper.currentReasoningText(previousPayload),
      previousToolCallCount: 0,
    );

    expect(((events.single['choices'] as List).single as Map)['delta'], {
      'content': ' sparkling with warmth.',
    });
  });

  test('chat stream suppresses shorter restarted prefix during continuation', () {
    final previousPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Seraphina smiles warmly, her amber eyes glowing with'},
              ],
            },
          },
        ],
      },
    };

    final restartedPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Seraphina smiles warmly, her amber eyes'},
              ],
            },
          },
        ],
      },
    };

    final events = OpenAiResponseMapper.toChatStreamDeltas(
      requestId: 'req_restart',
      model: 'gemini-3-flash-preview',
      payload: restartedPayload,
      includeRole: false,
      previousText: OpenAiResponseMapper.currentText(previousPayload),
      previousReasoningText: OpenAiResponseMapper.currentReasoningText(previousPayload),
      previousToolCallCount: 0,
    );

    expect(events, isEmpty);
  });

  test('chat completion exposes reasoning, stable tool ids, and detailed usage', () {
    final payload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {'thought': true, 'text': 'Need weather lookup.'},
                {
                  'functionCall': {
                    'id': 'call_weather',
                    'name': 'lookupWeather',
                    'args': {'city': 'Moscow'},
                  },
                },
              ],
            },
            'finishReason': 'STOP',
          },
        ],
        'usageMetadata': {
          'promptTokenCount': 12,
          'candidatesTokenCount': 5,
          'totalTokenCount': 17,
          'cachedContentTokenCount': 2,
          'thoughtsTokenCount': 4,
        },
      },
    };

    final response = OpenAiResponseMapper.toChatCompletion(
      requestId: 'req_reasoning',
      model: 'gemini-3.1-pro-preview',
      payload: payload,
    );

    final choice = ((response['choices'] as List).single as Map).cast<String, Object?>();
    final message = (choice['message'] as Map).cast<String, Object?>();
    final toolCall = ((message['tool_calls'] as List).single as Map).cast<String, Object?>();

    expect(message['reasoning_content'], 'Need weather lookup.');
    expect(message['content'], isNull);
    expect(toolCall['id'], 'call_weather');
    expect(toolCall['index'], 0);
    expect(
      ((toolCall['function'] as Map).cast<String, Object?>())['arguments'],
      '{"city":"Moscow"}',
    );
    expect(choice['finish_reason'], 'tool_calls');
    expect((response['usage'] as Map)['cached_tokens'], 2);
    expect(
      (((response['usage'] as Map)['completion_tokens_details'] as Map)['reasoning_tokens']),
      4,
    );
  });

  test('responses stream keeps a stable message id across chunks', () {
    final firstPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Hello'},
              ],
            },
          },
        ],
      },
    };
    final secondPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'Hello there'},
              ],
            },
          },
        ],
      },
    };

    final firstEvents = OpenAiResponseMapper.toResponsesStreamEvents(
      requestId: 'resp_stable',
      model: 'gemini-3-flash-preview',
      payload: firstPayload,
      includePrelude: true,
      previousText: '',
      previousReasoningText: '',
      previousToolCallCount: 0,
      previousToolCallArguments: const [],
    );
    final secondEvents = OpenAiResponseMapper.toResponsesStreamEvents(
      requestId: 'resp_stable',
      model: 'gemini-3-flash-preview',
      payload: secondPayload,
      includePrelude: false,
      previousText: OpenAiResponseMapper.currentText(firstPayload),
      previousReasoningText: OpenAiResponseMapper.currentReasoningText(firstPayload),
      previousToolCallCount: OpenAiResponseMapper.currentToolCallCount(firstPayload),
      previousToolCallArguments: OpenAiResponseMapper.currentToolCallArguments(firstPayload),
    );

    expect(((firstEvents[1]['item'] as Map)['id']), 'msg_resp_stable');
    expect(secondEvents.single['item_id'], 'msg_resp_stable');
  });

  test('responses stream emits tool call lifecycle events', () {
    final toolPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'id': 'call_weather',
                    'name': 'lookupWeather',
                    'args': {'city': 'Moscow'},
                  },
                },
              ],
            },
          },
        ],
      },
    };

    final firstEvents = OpenAiResponseMapper.toResponsesStreamEvents(
      requestId: 'resp_tools',
      model: 'gemini-3-flash-preview',
      payload: toolPayload,
      includePrelude: true,
      previousText: '',
      previousReasoningText: '',
      previousToolCallCount: 0,
      previousToolCallArguments: const [],
    );
    final finalEvents = OpenAiResponseMapper.toResponsesStreamEvents(
      requestId: 'resp_tools',
      model: 'gemini-3-flash-preview',
      payload: {...toolPayload, 'final_chunk': true},
      includePrelude: false,
      previousText: '',
      previousReasoningText: '',
      previousToolCallCount: 1,
      previousToolCallArguments: const ['{"city":"Moscow"}'],
    );

    expect(firstEvents[0]['type'], 'response.created');
    expect(firstEvents[1]['type'], 'response.output_item.added');
    expect(((firstEvents[1]['item'] as Map)['id']), 'call_weather');
    expect(firstEvents[2]['type'], 'response.function_call_arguments.delta');
    expect(firstEvents[2]['item_id'], 'call_weather');
    expect(firstEvents[2]['delta'], '{"city":"Moscow"}');

    expect(finalEvents[0]['type'], 'response.function_call_arguments.done');
    expect(finalEvents[0]['arguments'], '{"city":"Moscow"}');
    expect(finalEvents[1]['type'], 'response.output_item.done');
    expect(((finalEvents[1]['item'] as Map)['status']), 'completed');
    expect(finalEvents[2]['type'], 'response.completed');
    final completedResponse = (finalEvents[2]['response'] as Map).cast<String, Object?>();
    final output = (completedResponse['output'] as List).cast<Map>();
    expect(output.first['type'], 'function_call');
  });

  test('responses stream emits incremental tool argument deltas across chunks', () {
    final firstPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'id': 'call_weather',
                    'name': 'lookupWeather',
                    'args': {'city': 'Mos'},
                  },
                },
              ],
            },
          },
        ],
      },
    };

    final secondPayload = <String, Object?>{
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'id': 'call_weather',
                    'name': 'lookupWeather',
                    'args': {'city': 'Moscow'},
                  },
                },
              ],
            },
          },
        ],
      },
    };

    final firstEvents = OpenAiResponseMapper.toResponsesStreamEvents(
      requestId: 'resp_args',
      model: 'gemini-3-flash-preview',
      payload: firstPayload,
      includePrelude: true,
      previousText: '',
      previousReasoningText: '',
      previousToolCallCount: 0,
      previousToolCallArguments: const [],
    );
    final secondEvents = OpenAiResponseMapper.toResponsesStreamEvents(
      requestId: 'resp_args',
      model: 'gemini-3-flash-preview',
      payload: secondPayload,
      includePrelude: false,
      previousText: '',
      previousReasoningText: '',
      previousToolCallCount: OpenAiResponseMapper.currentToolCallCount(firstPayload),
      previousToolCallArguments: OpenAiResponseMapper.currentToolCallArguments(firstPayload),
    );

    expect(firstEvents[2]['delta'], '{"city":"Mos"}');
    expect(secondEvents.single['type'], 'response.function_call_arguments.delta');
    expect(secondEvents.single['delta'], 'cow"}');
  });
}
