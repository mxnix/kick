import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/features/accounts/account_editor_dialog.dart';
import 'package:kick/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('expands advanced account settings without throwing', (tester) async {
    await tester.pumpWidget(const _TestApp());

    await tester.tap(find.text('Открыть диалог'));
    await tester.pumpAndSettle();

    expect(find.text('Расширенные настройки'), findsOneWidget);

    await tester.tap(find.text('Расширенные настройки'));
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
