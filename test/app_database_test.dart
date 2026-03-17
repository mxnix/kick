import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/app_database.dart';

void main() {
  test('close releases drift tracking for subsequent database instances', () async {
    final messages = <String>[];
    final originalDebugPrint = driftRuntimeOptions.debugPrint;
    final originalSuppressWarnings = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.debugPrint = messages.add;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;

    try {
      final first = AppDatabase(NativeDatabase.memory());
      await first.ensureSchema();
      await first.close();

      final second = AppDatabase(NativeDatabase.memory());
      await second.ensureSchema();
      await second.close();
    } finally {
      driftRuntimeOptions.debugPrint = originalDebugPrint;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = originalSuppressWarnings;
    }

    expect(
      messages.where(
        (message) =>
            message.contains('created the database class _AttachedDatabase multiple times'),
      ),
      isEmpty,
    );
  });
}
