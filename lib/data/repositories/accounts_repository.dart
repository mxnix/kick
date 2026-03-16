import 'package:drift/drift.dart';

import '../app_database.dart';
import '../models/account_profile.dart';

class AccountsRepository {
  AccountsRepository(this._database);

  final AppDatabase _database;

  Future<List<AccountProfile>> readAll() async {
    final rows = await _database
        .customSelect('SELECT * FROM accounts ORDER BY priority DESC, label COLLATE NOCASE ASC')
        .get();
    return rows.map((row) => AccountProfile.fromDatabaseMap(row.data)).toList(growable: false);
  }

  Future<void> upsert(AccountProfile account) async {
    await _database.customInsert('''
      INSERT INTO accounts (
        id, label, email, project_id, enabled, priority, not_supported_models,
        last_used_at, usage_count, error_count, cooldown_until,
        last_quota_snapshot, token_ref
      ) VALUES (
        ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13
      )
      ON CONFLICT(id) DO UPDATE SET
        label = excluded.label,
        email = excluded.email,
        project_id = excluded.project_id,
        enabled = excluded.enabled,
        priority = excluded.priority,
        not_supported_models = excluded.not_supported_models,
        last_used_at = excluded.last_used_at,
        usage_count = excluded.usage_count,
        error_count = excluded.error_count,
        cooldown_until = excluded.cooldown_until,
        last_quota_snapshot = excluded.last_quota_snapshot,
        token_ref = excluded.token_ref
      ''', variables: _accountVariables(account));
  }

  Future<void> upsertMany(List<AccountProfile> accounts) async {
    await _database.transaction(() async {
      for (final account in accounts) {
        await upsert(account);
      }
    });
  }

  Future<void> delete(String accountId) async {
    await _database.customStatement('DELETE FROM accounts WHERE id = ?1', [accountId]);
  }

  Future<void> replaceAll(List<AccountProfile> accounts) async {
    await _database.transaction(() async {
      await _database.customStatement('DELETE FROM accounts');
      for (final account in accounts) {
        await upsert(account);
      }
    });
  }

  Future<void> mergeRuntimeState(List<AccountProfile> runtimeAccounts) async {
    if (runtimeAccounts.isEmpty) {
      return;
    }

    final existingById = {
      for (final account in await readAll()) account.id: account,
    };

    await _database.transaction(() async {
      for (final runtimeAccount in runtimeAccounts) {
        final current = existingById[runtimeAccount.id];
        if (current == null) {
          continue;
        }

        await upsert(
          current.copyWith(
            notSupportedModels: _mergeNotSupportedModels(
              current.notSupportedModels,
              runtimeAccount.notSupportedModels,
            ),
            lastUsedAt: runtimeAccount.lastUsedAt,
            clearLastUsedAt: runtimeAccount.lastUsedAt == null,
            usageCount: runtimeAccount.usageCount,
            errorCount: runtimeAccount.errorCount,
            cooldownUntil: runtimeAccount.cooldownUntil,
            clearCooldown: runtimeAccount.cooldownUntil == null,
            lastQuotaSnapshot: runtimeAccount.lastQuotaSnapshot,
            clearQuotaSnapshot: runtimeAccount.lastQuotaSnapshot == null,
          ),
        );
      }
    });
  }

  List<Variable> _accountVariables(AccountProfile account) {
    final map = account.toDatabaseMap();
    return [
      Variable<String>(map['id'] as String),
      Variable<String>(map['label'] as String),
      Variable<String>(map['email'] as String),
      Variable<String>(map['project_id'] as String),
      Variable<int>((map['enabled'] as int?) ?? 1),
      Variable<int>((map['priority'] as int?) ?? 0),
      Variable<String>(map['not_supported_models'] as String? ?? ''),
      Variable<String>((map['last_used_at'] as String?) ?? ''),
      Variable<int>((map['usage_count'] as int?) ?? 0),
      Variable<int>((map['error_count'] as int?) ?? 0),
      Variable<String>((map['cooldown_until'] as String?) ?? ''),
      Variable<String>((map['last_quota_snapshot'] as String?) ?? ''),
      Variable<String>(map['token_ref'] as String),
    ];
  }

  List<String> _mergeNotSupportedModels(List<String> current, List<String> runtime) {
    final merged = <String>{...current, ...runtime};
    return merged.toList(growable: false);
  }
}
