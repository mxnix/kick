import 'package:flutter_test/flutter_test.dart';
import 'package:kick/proxy/openai/sse.dart';

void main() {
  test('encodes named SSE event with multiline payload', () {
    final encoded = encodeSseEvent('line one\nline two', event: 'response.output_text.delta');

    expect(
      encoded,
      'event: response.output_text.delta\n'
      'data: line one\n'
      'data: line two\n'
      '\n',
    );
  });

  test('encodes object payload as json', () {
    final encoded = encodeSseEvent({'ok': true, 'count': 2});

    expect(encoded, startsWith('data: {"ok":true,"count":2}\n'));
    expect(encoded, endsWith('\n\n'));
  });
}
