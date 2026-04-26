import 'package:flutter_test/flutter_test.dart';
import 'package:kick/proxy/openai/thought_signature_cache.dart';

void main() {
  test('restores cached signatures on chat tool calls that dropped extra content', () {
    final cache = OpenAiThoughtSignatureCache();
    cache.rememberToolCalls([
      {
        'id': 'call_read',
        'type': 'function',
        'extra_content': {
          'google': {'thought_signature': 'sig_read_file'},
        },
        'function': {'name': 'default_api:read_file', 'arguments': '{"path":"README.md"}'},
      },
    ]);

    final request = <String, Object?>{
      'messages': [
        {
          'role': 'assistant',
          'tool_calls': [
            {
              'id': 'call_read',
              'type': 'function',
              'function': {'name': 'default_api:read_file', 'arguments': '{"path":"README.md"}'},
            },
          ],
        },
      ],
    };

    expect(cache.enrichChatRequest(request), isTrue);

    final message = ((request['messages'] as List).single as Map).cast<String, Object?>();
    final toolCall = ((message['tool_calls'] as List).single as Map).cast<String, Object?>();
    final extraContent = (toolCall['extra_content'] as Map).cast<String, Object?>();
    final google = (extraContent['google'] as Map).cast<String, Object?>();

    expect(google['thought_signature'], 'sig_read_file');
  });

  test('uses fingerprint matching for generic generated tool call ids', () {
    final cache = OpenAiThoughtSignatureCache();
    cache.rememberToolCalls([
      {
        'id': 'call_1',
        'type': 'function',
        'extra_content': {
          'google': {'thought_signature': 'sig_expected'},
        },
        'function': {'name': 'lookup', 'arguments': '{"city":"Moscow"}'},
      },
    ]);

    final matchingRequest = <String, Object?>{
      'messages': [
        {
          'role': 'assistant',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'lookup', 'arguments': '{"city":"Moscow"}'},
            },
          ],
        },
      ],
    };
    final mismatchedRequest = <String, Object?>{
      'messages': [
        {
          'role': 'assistant',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'lookup', 'arguments': '{"city":"Paris"}'},
            },
          ],
        },
      ],
    };

    expect(cache.enrichChatRequest(matchingRequest), isTrue);
    expect(cache.enrichChatRequest(mismatchedRequest), isFalse);
  });
}
