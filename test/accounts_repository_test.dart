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
    String? googleSubjectId,
    String? avatarUrl,
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
      googleSubjectId: googleSubjectId,
      avatarUrl: avatarUrl,
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

    final database = await AppDatabase.open(
      '${tempDirectory.path}${Platform.pathSeparator}kick.sqlite',
    );
    addTearDown(database.close);

    final repository = AccountsRepository(database);
    final persisted = buildAccount(
      id: 'primary',
      label: 'Primary',
      email: 'primary@example.com',
      projectId: 'proj-primary',
      notSupportedModels: ['user-model'],
      googleSubjectId: 'google-subject-primary',
      avatarUrl: 'https://example.com/avatar-primary.png',
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
        googleSubjectId: 'runtime-subject',
        avatarUrl: 'https://example.com/runtime.png',
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
    expect(merged.googleSubjectId, 'google-subject-primary');
    expect(merged.avatarUrl, 'https://example.com/avatar-primary.png');
    expect(merged.tokenRef, 'primary-ref');
    expect(merged.notSupportedModels, ['user-model']);
    expect(merged.runtimeNotSupportedModels, ['runtime-model']);
    expect(merged.effectiveNotSupportedModels, containsAll(['user-model', 'runtime-model']));
    expect(merged.usageCount, 7);
    expect(merged.errorCount, 2);
    expect(merged.lastQuotaSnapshot, 'quota-hit');

    expect(accounts.any((account) => account.id == 'secondary'), isTrue);
  });

  test('persists auto-discovered project id from runtime when stored value is empty', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('kick-accounts-repo');
    addTearDown(() => tempDirectory.delete(recursive: true));

    final database = await AppDatabase.open(
      '${tempDirectory.path}${Platform.pathSeparator}kick.sqlite',
    );
    addTearDown(database.close);

    final repository = AccountsRepository(database);
    await repository.upsert(
      buildAccount(
        id: 'primary',
        label: 'Primary',
        email: 'primary@example.com',
        projectId: '',
        notSupportedModels: const [],
        tokenRef: 'primary-ref',
      ),
    );

    await repository.mergeRuntimeState([
      buildAccount(
        id: 'primary',
        label: 'Runtime label',
        email: 'runtime@example.com',
        projectId: 'runtime-project',
        notSupportedModels: const [],
        tokenRef: 'runtime-ref',
      ),
    ]);

    final accounts = await repository.readAll();
    expect(accounts, hasLength(1));
    expect(accounts.single.projectId, 'runtime-project');
  });
}
