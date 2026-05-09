import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/theme/kick_theme.dart';
import 'package:m3e_collection/m3e_collection.dart';

void main() {
  test('fallback theme seed uses slate blue accent', () {
    expect(KickSchemes.fallbackSeedColor, const Color(0xff6b86a8));
  });

  test('fallback color schemes keep the Kick blue accent', () {
    final lightHue = HSVColor.fromColor(KickSchemes.light.primary).hue;
    final darkHue = HSVColor.fromColor(KickSchemes.dark.primary).hue;

    expect(lightHue, inInclusiveRange(200, 260));
    expect(darkHue, inInclusiveRange(200, 260));
  });

  test('theme uses bundled Google Sans by default', () {
    final theme = KickThemeData.build(KickSchemes.light);

    expect(theme.textTheme.bodyMedium?.fontFamily, KickThemeData.defaultFontFamily);
    expect(theme.textTheme.titleLarge?.fontFamily, KickThemeData.defaultFontFamily);
    expect(theme.textTheme.labelLarge?.fontFamily, KickThemeData.defaultFontFamily);
  });

  test('theme installs Kick and Material 3 Expressive extensions', () {
    final theme = KickThemeData.build(KickSchemes.light);

    expect(theme.extension<KickThemeTokens>(), isNotNull);
    expect(theme.extensions.values.whereType<M3ETheme>(), isNotEmpty);
    expect(theme.extension<KickThemeTokens>()?.panelRadius, 24);
    expect(theme.textTheme.titleLarge?.letterSpacing, 0);
  });

  test('theme can use the platform system font', () {
    final theme = KickThemeData.build(KickSchemes.light, useSystemFont: true);

    expect(theme.textTheme.bodyMedium?.fontFamily, isNot(KickThemeData.defaultFontFamily));
    expect(theme.textTheme.titleLarge?.fontFamily, isNot(KickThemeData.defaultFontFamily));
    expect(theme.textTheme.labelLarge?.fontFamily, isNot(KickThemeData.defaultFontFamily));
  });
}
