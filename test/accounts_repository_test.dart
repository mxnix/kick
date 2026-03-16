import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kick/data/app_database.dart';
import 'package:kick/data/models/account_profile.dart';
import 'package:kick/data/repositories/accounts_repository.dart';

void main() {
  AccountProfile buildAccount({
    required String id,
    required String label,
    required String email,
    required String projectId,
    required List<String> notSupportedModels,
    DateTime? lastUsedAt,
    int usageCount = 0,
    int errorCount = 0,
    DateTime? cooldownUntil,
    String? lastQuotaSnapshot,
    String tokenRef = 'token-ref',
  }) {
    return AccountProfile(
      id: id,
      label: label,
      email: email,
      projectId: projectId,
      enabled: true,
      priority: 1,
      notSupportedModels: notSupportedModels,
      lastUsedAt: lastUsedAt,
      usageCount: usageCount,
      errorCount: errorCount,
      cooldownUntil: cooldownUntil,
      lastQuotaSnapshot: lastQuotaSnapshot,
      tokenRef: tokenRef,
    );
  }

  test('merges runtime state without deleting unrelated accounts', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick-accounts-repo');
    addTearDown(() => tempDirectory.delete(recursive: true));

    final database = await AppDatabase.open('${tempDirectory.path}${Platform.pathSeparator}kick.sqlite');
    addTearDown(database.close);

    final repository = AccountsRepository(database);
    final persisted = buildAccount(
      id: 'primary',
      label: 'Primary',
      email: 'primary@example.com',
      projectId: 'proj-primary',
      notSupportedModels: ['user-model'],
      tokenRef: 'primary-ref',
    );
    final untouched = buildAccount(
      id: 'secondary',
      label: 'Secondary',
      email: 'secondary@example.com',
      projectId: 'proj-secondary',
      notSupportedModels: const [],
      tokenRef: 'secondary-ref',
    );

    await repository.upsertMany([persisted, untouched]);

    await repository.mergeRuntimeState([
      buildAccount(
        id: 'primary',
        label: 'Runtime label',
        email: 'runtime@example.com',
        projectId: 'runtime-project',
        notSupportedModels: ['runtime-model'],
        lastUsedAt: DateTime.parse('2026-03-16T08:00:00Z'),
        usageCount: 7,
        errorCount: 2,
        cooldownUntil: DateTime.parse('2026-03-16T09:00:00Z'),
        lastQuotaSnapshot: 'quota-hit',
        tokenRef: 'runtime-ref',
      ),
    ]);

    final accounts = await repository.readAll();
    expect(accounts, hasLength(2));

    final merged = accounts.firstWhere((account) => account.id == 'primary');
    expect(merged.label, 'Primary');
    expect(merged.email, 'primary@example.com');
    expect(merged.projectId, 'proj-primary');
    expect(merged.tokenRef, 'primary-ref');
    expect(merged.notSupportedModels, containsAll(['user-model', 'runtime-model']));
    expect(merged.usageCount, 7);
    expect(merged.errorCount, 2);
    expect(merged.lastQuotaSnapshot, 'quota-hit');

    expect(accounts.any((account) => account.id == 'secondary'), isTrue);
  });
}
