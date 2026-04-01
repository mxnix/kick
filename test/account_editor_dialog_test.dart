import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/features/accounts/account_editor_dialog.dart';
import 'package:kick/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('expands advanced account settings without throwing', (tester) async {
    await tester.pumpWidget(const _TestApp());

    await tester.tap(find.text('Открыть диалог'));
    await tester.pumpAndSettle();

    expect(find.text('Расширенные настройки'), findsOneWidget);

    final advancedSettings = find.byType(ExpansionTile);
    await tester.ensureVisible(advancedSettings);
    await tester.tap(advancedSettings);
    await tester.pumpAndSettle();

    expect(find.text('Недоступные модели'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('allows submitting the dialog without project id', (tester) async {
    await tester.pumpWidget(const _TestApp());

    await tester.tap(find.text('Открыть диалог'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Продолжить'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Укажите ID проекта'), findsNothing);
  });

  testWidgets('shows only browser authorization fields for kiro and stretches provider selector', (
    tester,
  ) async {
    await tester.pumpWidget(const _TestApp());

    await tester.tap(find.text('Открыть диалог'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kiro'));
    await tester.pumpAndSettle();

    expect(find.text('Способ подключения'), findsNothing);
    expect(find.text('Локальная сессия'), findsNothing);
    expect(find.text('Локальный источник Kiro'), findsNothing);
    expect(find.text('Ссылка Builder ID'), findsOneWidget);
    expect(find.text('Регион AWS'), findsOneWidget);
    expect(find.text('Обычно менять не нужно.'), findsOneWidget);
    expect(find.text('Обычно оставьте значение us-east-1.'), findsOneWidget);

    final providerSelector = find.byWidgetPredicate(
      (widget) => widget is SegmentedButton<AccountProvider>,
    );
    final field = find.byType(TextField).first;
    expect(tester.getSize(providerSelector).width, closeTo(tester.getSize(field).width, 0.1));
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () {
                showAccountEditorDialog(context);
              },
              child: const Text('Открыть диалог'),
            ),
          ),
        ),
      ),
    );
  }
}
