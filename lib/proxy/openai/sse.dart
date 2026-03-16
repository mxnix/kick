import 'dart:convert';

String encodeSseEvent(Object? data, {String? event}) {
  final buffer = StringBuffer();
  if (event != null && event.isNotEmpty) {
    buffer.writeln('event: $event');
  }
  final encoded = data is String ? data : jsonEncode(data);
  for (final line in encoded.split('\n')) {
    buffer.writeln('data: $line');
  }
  buffer.writeln();
  return buffer.toString();
}
