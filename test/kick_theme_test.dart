import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/theme/kick_theme.dart';

void main() {
  test('theme does not force Google Sans fallbacks', () {
    final theme = KickThemeData.build(KickSchemes.light);
    final fallback = theme.textTheme.bodyMedium?.fontFamilyFallback ?? const <String>[];

    expect(theme.textTheme.bodyMedium?.fontFamily, isNot('Google Sans Text'));
    expect(fallback, isNot(contains('Google Sans Text')));
    expect(fallback, isNot(contains('Google Sans')));
  });
}
