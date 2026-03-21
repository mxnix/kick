import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/theme/kick_theme.dart';

void main() {
  test('fallback theme seed uses slate blue accent', () {
    expect(KickSchemes.fallbackSeedColor, const Color(0xff6b86a8));
  });

  test('theme uses bundled Google Sans by default', () {
    final theme = KickThemeData.build(KickSchemes.light);

    expect(theme.textTheme.bodyMedium?.fontFamily, KickThemeData.defaultFontFamily);
    expect(theme.textTheme.titleLarge?.fontFamily, KickThemeData.defaultFontFamily);
    expect(theme.textTheme.labelLarge?.fontFamily, KickThemeData.defaultFontFamily);
  });
}
