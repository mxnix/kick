import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/l10n/kick_localizations.dart';

void main() {
  testWidgets('resolves supported locales from the system locale list', (tester) async {
    addTearDown(() => setKickLocaleOverride(null));
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.binding.platformDispatcher.localesTestValue = const <Locale>[
      Locale('en', 'US'),
      Locale('ru', 'RU'),
    ];

    final l10n = lookupKickLocalizations();

    expect(l10n.localeName, 'en');
  });

  testWidgets('falls back to English when the system locale is unsupported', (tester) async {
    addTearDown(() => setKickLocaleOverride(null));
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.binding.platformDispatcher.localesTestValue = const <Locale>[Locale('de', 'DE')];

    final l10n = lookupKickLocalizations();

    expect(l10n.localeName, 'en');
  });

  testWidgets('prefers the explicit locale override over system locales', (tester) async {
    addTearDown(() => setKickLocaleOverride(null));
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.binding.platformDispatcher.localesTestValue = const <Locale>[Locale('en', 'US')];
    setKickLocaleOverride(const Locale('ru'));

    final l10n = lookupKickLocalizations();

    expect(l10n.localeName, 'ru');
  });

  test('desktop integration labels are platform-neutral', () {
    final en = lookupKickLocalizations(const Locale('en'));
    final ru = lookupKickLocalizations(const Locale('ru'));

    expect(en.windowsLaunchAtStartupTitle, isNot(contains('Windows')));
    expect(en.windowsTraySubtitle, isNot(contains('Windows')));
    expect(ru.windowsLaunchAtStartupTitle, isNot(contains('Windows')));
    expect(ru.windowsTraySubtitle, isNot(contains('Windows')));
  });
}
