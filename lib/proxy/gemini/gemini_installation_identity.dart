import 'dart:io';

import 'package:uuid/uuid.dart';

typedef GeminiInstallationIdPathProvider = String? Function();

final class GeminiInstallationIdLoader {
  GeminiInstallationIdLoader({
    GeminiInstallationIdPathProvider? installationIdPathProvider,
    String Function()? createUuid,
  }) : _installationIdPathProvider = installationIdPathProvider ?? _emptyInstallationIdPathProvider,
       _createUuid = createUuid ?? const Uuid().v4;

  final GeminiInstallationIdPathProvider _installationIdPathProvider;
  final String Function() _createUuid;

  String? _cachedInstallationIdPath;
  Future<String>? _cachedInstallationId;

  Future<String> load() {
    final installationIdPath = _normalizeInstallationIdPath(_installationIdPathProvider());
    final cachedInstallationId = _cachedInstallationId;
    if (cachedInstallationId != null && installationIdPath == _cachedInstallationIdPath) {
      return cachedInstallationId;
    }

    _cachedInstallationIdPath = installationIdPath;
    final nextInstallationId = loadOrCreateGeminiInstallationId(
      installationIdPath: installationIdPath,
      createUuid: _createUuid,
    );
    _cachedInstallationId = nextInstallationId;
    return nextInstallationId;
  }
}

Future<String> loadOrCreateGeminiInstallationId({
  String? installationIdPath,
  String Function()? createUuid,
}) async {
  final normalizedInstallationIdPath = _normalizeInstallationIdPath(installationIdPath);
  final createInstallationId = createUuid ?? const Uuid().v4;
  if (normalizedInstallationIdPath == null) {
    return createInstallationId();
  }

  final file = File(normalizedInstallationIdPath);
  try {
    final existing = (await file.readAsString()).trim();
    if (existing.isNotEmpty) {
      return existing;
    }
  } on FileSystemException {
    // Fall through and create a new identifier.
  }

  final created = createInstallationId();
  await file.parent.create(recursive: true);
  await file.writeAsString(created, flush: true);
  return created;
}

String? _normalizeInstallationIdPath(String? installationIdPath) {
  final normalized = installationIdPath?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

String? _emptyInstallationIdPathProvider() => null;
