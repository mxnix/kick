import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/logging/log_sanitizer.dart';

void main() {
  test('sanitizes chat request payloads without keeping message text', () {
    final payload =
        (LogSanitizer.sanitizeJsonValue({
                  'messages': [
                    {'role': 'system', 'content': 'Sensitive system prompt'},
                    {'role': 'user', 'content': 'Sensitive user prompt'},
                  ],
                  'model': 'gemini-3-flash-preview',
                  'stream': true,
                  'api_key': 'secret',
                })
                as Map)
            .cast<String, Object?>();
    final messages = (payload['messages'] as Map).cast<String, Object?>();

    expect(payload['model'], 'gemini-3-flash-preview');
    expect(payload['stream'], isTrue);
    expect(payload['api_key'], '***');
    expect(messages['message_count'], 2);
    expect(messages['roles'], ['system', 'user']);
    expect(messages['contains_media'], isFalse);
    expect(messages['contains_tool_calls'], isFalse);
  });

  test('sanitizes serialized payload previews', () {
    final sanitized = LogSanitizer.sanitizeSerializedPayload(
      jsonEncode({'preview': 'A long generated answer', 'finish_reason': 'stop'}),
    );

    expect(sanitized, contains('"finish_reason":"stop"'));
    expect(sanitized, contains('[REDACTED preview chars=23]'));
    expect(sanitized, isNot(contains('generated answer')));
  });
}
