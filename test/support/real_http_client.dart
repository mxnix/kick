import 'dart:io';

Future<T> runWithRealHttpClient<T>(Future<T> Function() body) {
  return HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());
}

class _RealHttpOverrides extends HttpOverrides {
  _RealHttpOverrides();
}
