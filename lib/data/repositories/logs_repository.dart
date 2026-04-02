import 'package:drift/drift.dart';

import '../../core/logging/log_sanitizer.dart';
import '../app_database.dart';
import '../models/app_log_entry.dart';
import '../models/app_settings.dart';

class LogsRepository {
  LogsRepository(this._database, {int retentionLimit = defaultLogRetentionCount})
    : _retentionLimit = normalizeLogRetentionCount(retentionLimit);

  final AppDatabase _database;
  int _retentionLimit;

  Future<List<AppLogEntry>> readAll({
    int? limit = 300,
    int offset = 0,
    String query = '',
    AppLogLevel? level,
    String? category,
    Iterable<String> excludedCategories = const <String>[],
  }) async {
    final parts = _buildQueryParts(
      query: query,
      level: level,
      category: category,
      excludedCategories: excludedCategories,
    );
    final sql = StringBuffer('SELECT * FROM logs${parts.whereClause} ORDER BY timestamp DESC');
    final variables = <Variable>[...parts.variables];

    if (limit != null) {
      sql.write(' LIMIT ?${parts.nextIndex}');
      variables.add(Variable<int>(limit));
      if (offset > 0) {
        sql.write(' OFFSET ?${parts.nextIndex + 1}');
        variables.add(Variable<int>(offset));
      }
    } else if (offset > 0) {
      sql.write(' LIMIT -1 OFFSET ?${parts.nextIndex}');
      variables.add(Variable<int>(offset));
    }

    final rows = await _database.customSelect(sql.toString(), variables: variables).get();
    return rows.map((row) => AppLogEntry.fromDatabaseMap(row.data)).toList(growable: false);
  }

  Future<int> count({
    String query = '',
    AppLogLevel? level,
    String? category,
    Iterable<String> excludedCategories = const <String>[],
  }) async {
    final parts = _buildQueryParts(
      query: query,
      level: level,
      category: category,
      excludedCategories: excludedCategories,
    );
    final row = await _database
        .customSelect(
          'SELECT COUNT(*) AS total FROM logs${parts.whereClause}',
          variables: parts.variables,
        )
        .getSingle();
    return row.read<int>('total');
  }

  Future<List<String>> readCategories({
    Iterable<String> excludedCategories = const <String>[],
  }) async {
    final normalizedExcludedCategories = _normalizeCategories(excludedCategories);
    final clauses = <String>["TRIM(category) != ''"];
    final variables = <Variable>[];
    if (normalizedExcludedCategories.isNotEmpty) {
      final placeholders = List.generate(
        normalizedExcludedCategories.length,
        (index) => '?${index + 1}',
      ).join(', ');
      clauses.add('category NOT IN ($placeholders)');
      variables.addAll(normalizedExcludedCategories.map(Variable<String>.new));
    }

    final rows = await _database.customSelect('''
          SELECT DISTINCT category
          FROM logs
          WHERE ${clauses.join(' AND ')}
          ORDER BY category COLLATE NOCASE
          ''', variables: variables).get();
    return rows
        .map((row) => row.read<String>('category').trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> setRetentionLimit(int retentionLimit) async {
    _retentionLimit = normalizeLogRetentionCount(retentionLimit);
    await _pruneToRetentionLimit();
  }

  Future<void> insert(AppLogEntry entry) async {
    final sanitizedMessage = LogSanitizer.sanitizeText(entry.message);
    final sanitizedMaskedPayload = LogSanitizer.sanitizeSerializedPayload(entry.maskedPayload);

    await _database.customInsert(
      '''
      INSERT INTO logs (
        id, timestamp, level, category, route, message, masked_payload, raw_payload
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
      ''',
      variables: [
        Variable<String>(entry.id),
        Variable<String>(entry.timestamp.toIso8601String()),
        Variable<String>(entry.level.name),
        Variable<String>(entry.category),
        Variable<String>(entry.route ?? ''),
        Variable<String>(sanitizedMessage),
        Variable<String>(sanitizedMaskedPayload ?? ''),
        Variable<String>(entry.rawPayload ?? ''),
      ],
    );

    await _pruneToRetentionLimit();
  }

  Future<void> clear() async {
    await _database.customStatement('DELETE FROM logs');
  }

  Future<void> scrubSensitiveEntries({required bool clearRawPayload}) async {
    final entries = await readAll(limit: null);
    if (entries.isEmpty) {
      return;
    }

    await _database.transaction(() async {
      for (final entry in entries) {
        final sanitizedMessage = LogSanitizer.sanitizeText(entry.message);
        final sanitizedMaskedPayload = LogSanitizer.sanitizeSerializedPayload(entry.maskedPayload);
        final nextRawPayload = clearRawPayload ? '' : (entry.rawPayload ?? '');
        final currentRawPayload = entry.rawPayload ?? '';
        final nextMaskedPayload = sanitizedMaskedPayload ?? '';
        final currentMaskedPayload = entry.maskedPayload ?? '';

        if (sanitizedMessage == entry.message &&
            nextMaskedPayload == currentMaskedPayload &&
            nextRawPayload == currentRawPayload) {
          continue;
        }

        await _database.customStatement(
          'UPDATE logs SET message = ?1, masked_payload = ?2, raw_payload = ?3 WHERE id = ?4',
          [sanitizedMessage, nextMaskedPayload, nextRawPayload, entry.id],
        );
      }
    });
  }

  Future<void> _pruneToRetentionLimit() async {
    final rows = await _database
        .customSelect(
          'SELECT id FROM logs ORDER BY timestamp DESC LIMIT -1 OFFSET ?1',
          variables: [Variable<int>(_retentionLimit)],
        )
        .get();
    final idsToDelete = rows.map((row) => row.read<String>('id')).toList(growable: false);
    if (idsToDelete.isEmpty) {
      return;
    }

    final placeholders = List.generate(idsToDelete.length, (index) => '?${index + 1}').join(', ');
    await _database.customStatement('DELETE FROM logs WHERE id IN ($placeholders)', idsToDelete);
  }

  _LogQueryParts _buildQueryParts({
    required String query,
    required AppLogLevel? level,
    required String? category,
    required Iterable<String> excludedCategories,
  }) {
    final clauses = <String>[];
    final variables = <Variable>[];
    var nextIndex = 1;

    if (level != null) {
      clauses.add('level = ?$nextIndex');
      variables.add(Variable<String>(level.name));
      nextIndex += 1;
    }

    final normalizedCategory = category?.trim();
    if (normalizedCategory != null && normalizedCategory.isNotEmpty) {
      clauses.add('category = ?$nextIndex');
      variables.add(Variable<String>(normalizedCategory));
      nextIndex += 1;
    }

    final normalizedExcludedCategories = _normalizeCategories(excludedCategories);
    if (normalizedExcludedCategories.isNotEmpty) {
      final placeholders = List.generate(
        normalizedExcludedCategories.length,
        (index) => '?${nextIndex + index}',
      ).join(', ');
      clauses.add('category NOT IN ($placeholders)');
      variables.addAll(normalizedExcludedCategories.map(Variable<String>.new));
      nextIndex += normalizedExcludedCategories.length;
    }

    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isNotEmpty) {
      clauses.add('''
        (
          LOWER(message) LIKE ?$nextIndex ESCAPE '\\'
          OR LOWER(category) LIKE ?$nextIndex ESCAPE '\\'
          OR LOWER(COALESCE(route, '')) LIKE ?$nextIndex ESCAPE '\\'
          OR LOWER(COALESCE(masked_payload, '')) LIKE ?$nextIndex ESCAPE '\\'
        )
      ''');
      variables.add(Variable<String>('%${_escapeLikePattern(normalizedQuery)}%'));
      nextIndex += 1;
    }

    final whereClause = clauses.isEmpty ? '' : ' WHERE ${clauses.join(' AND ')}';
    return _LogQueryParts(whereClause: whereClause, variables: variables, nextIndex: nextIndex);
  }

  List<String> _normalizeCategories(Iterable<String> categories) {
    return categories
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String _escapeLikePattern(String value) {
    return value.replaceAll('\\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
  }
}

class _LogQueryParts {
  const _LogQueryParts({
    required this.whereClause,
    required this.variables,
    required this.nextIndex,
  });

  final String whereClause;
  final List<Variable> variables;
  final int nextIndex;
}
