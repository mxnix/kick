import 'dart:convert';

import '../../data/models/app_log_entry.dart';

sealed class LogDisplayItem {
  const LogDisplayItem();

  String get key;
  List<AppLogEntry> get entries;
}

class SingleLogDisplayItem extends LogDisplayItem {
  const SingleLogDisplayItem(this.entry);

  final AppLogEntry entry;

  @override
  String get key => entry.id;

  @override
  List<AppLogEntry> get entries => [entry];
}

class RequestLogDisplayItem extends LogDisplayItem {
  RequestLogDisplayItem._({
    required this.requestId,
    required this.requestNumber,
    required List<AppLogEntry> entries,
    required this.primaryEntry,
    required this.effectiveLevel,
    required this.retryCount,
    required this.model,
    required this.kiroCreditsTotal,
    required this.kiroCreditUnit,
    required this.kiroCreditUnitPlural,
  }) : _entries = List.unmodifiable(entries);

  final String requestId;
  final int requestNumber;
  final List<AppLogEntry> _entries;
  final AppLogEntry primaryEntry;
  final AppLogLevel effectiveLevel;
  final int retryCount;
  final String? model;
  final num? kiroCreditsTotal;
  final String? kiroCreditUnit;
  final String? kiroCreditUnitPlural;

  @override
  String get key => 'request-$requestId';

  @override
  List<AppLogEntry> get entries => _entries;
}

List<LogDisplayItem> buildLogDisplayItems(List<AppLogEntry> entries) {
  final items = <LogDisplayItem>[];
  final requestGroups = <String, _RequestLogGroupBuilder>{};
  var requestNumber = 0;

  for (final entry in entries) {
    final payloadData = _payloadDataForEntry(entry);
    final requestId = payloadData.requestId;
    if (requestId == null) {
      items.add(SingleLogDisplayItem(entry));
      continue;
    }

    var group = requestGroups[requestId];
    if (group == null) {
      requestNumber += 1;
      group = _RequestLogGroupBuilder(requestId: requestId, requestNumber: requestNumber);
      requestGroups[requestId] = group;
      items.add(group);
    }
    group.add(entry, payloadData);
  }

  return items
      .map((item) => item is _RequestLogGroupBuilder ? item.build() : item)
      .toList(growable: false);
}

class _RequestLogGroupBuilder extends LogDisplayItem {
  _RequestLogGroupBuilder({required this.requestId, required this.requestNumber});

  final String requestId;
  final int requestNumber;
  final List<_RequestLogGroupMember> _members = <_RequestLogGroupMember>[];
  var _effectiveLevel = AppLogLevel.info;
  var _retryCount = 0;
  num? _kiroCreditsTotal;
  String? _kiroCreditUnit;
  String? _kiroCreditUnitPlural;

  @override
  String get key => 'request-$requestId';

  @override
  List<AppLogEntry> get entries => _members.map((member) => member.entry).toList(growable: false);

  void add(AppLogEntry entry, _LogEntryPayloadData payloadData) {
    _members.add(_RequestLogGroupMember(entry, payloadData));
    _effectiveLevel = _strongerLevel(_effectiveLevel, entry.level);

    final retryCount = payloadData.retryCount;
    if (retryCount != null && retryCount > _retryCount) {
      _retryCount = retryCount.round();
    }
    if (entry.message == 'Retry scheduled after request failure' ||
        entry.message == 'Retrying with another account after request failure') {
      _retryCount = _retryCount == 0 ? 1 : _retryCount;
    }

    final credits = payloadData.kiroCreditsTotal;
    if (credits != null) {
      _kiroCreditsTotal = (_kiroCreditsTotal ?? 0) + credits;
    }
    if ((payloadData.kiroCreditUnit ?? '').isNotEmpty) {
      _kiroCreditUnit = payloadData.kiroCreditUnit;
    }
    if ((payloadData.kiroCreditUnitPlural ?? '').isNotEmpty) {
      _kiroCreditUnitPlural = payloadData.kiroCreditUnitPlural;
    }
  }

  RequestLogDisplayItem build() {
    final primaryMember = _selectPrimaryMember(_members);
    return RequestLogDisplayItem._(
      requestId: requestId,
      requestNumber: requestNumber,
      entries: entries,
      primaryEntry: primaryMember.entry,
      effectiveLevel: _effectiveLevel,
      retryCount: _retryCount,
      model: primaryMember.payloadData.model,
      kiroCreditsTotal: _kiroCreditsTotal,
      kiroCreditUnit: _kiroCreditUnit,
      kiroCreditUnitPlural: _kiroCreditUnitPlural,
    );
  }
}

class _RequestLogGroupMember {
  const _RequestLogGroupMember(this.entry, this.payloadData);

  final AppLogEntry entry;
  final _LogEntryPayloadData payloadData;
}

class _LogEntryPayloadData {
  const _LogEntryPayloadData({
    this.requestId,
    this.model,
    this.retryCount,
    this.kiroCreditsTotal,
    this.kiroCreditUnit,
    this.kiroCreditUnitPlural,
  });

  final String? requestId;
  final String? model;
  final num? retryCount;
  final num? kiroCreditsTotal;
  final String? kiroCreditUnit;
  final String? kiroCreditUnitPlural;
}

_RequestLogGroupMember _selectPrimaryMember(List<_RequestLogGroupMember> members) {
  for (final member in members) {
    if (member.entry.level == AppLogLevel.error) {
      return member;
    }
  }
  for (final member in members) {
    if (member.entry.message == 'Response completed' ||
        member.entry.message == 'Request succeeded after retries' ||
        member.entry.message == 'Request failed after retries') {
      return member;
    }
  }
  return members.first;
}

AppLogLevel _strongerLevel(AppLogLevel current, AppLogLevel next) {
  if (current == AppLogLevel.error || next == AppLogLevel.error) {
    return AppLogLevel.error;
  }
  if (current == AppLogLevel.warning || next == AppLogLevel.warning) {
    return AppLogLevel.warning;
  }
  return AppLogLevel.info;
}

_LogEntryPayloadData _payloadDataForEntry(AppLogEntry entry) {
  final maskedPayload = _decodeLogPayload(entry.maskedPayload);
  final maskedRequestId = _payloadString(maskedPayload, 'request_id');
  final rawRequestId = maskedRequestId?.isNotEmpty == true
      ? null
      : _payloadString(_decodeLogPayload(entry.rawPayload), 'request_id');

  return _LogEntryPayloadData(
    requestId: maskedRequestId?.isNotEmpty == true ? maskedRequestId : rawRequestId,
    model: _payloadString(maskedPayload, 'model'),
    retryCount: _payloadNumber(maskedPayload, 'retry_count'),
    kiroCreditsTotal: _payloadNumber(maskedPayload, 'kiro_credits_total'),
    kiroCreditUnit: _payloadString(maskedPayload, 'kiro_credit_unit'),
    kiroCreditUnitPlural: _payloadString(maskedPayload, 'kiro_credit_unit_plural'),
  );
}

Map<String, Object?> _decodeLogPayload(String? payload) {
  final trimmed = payload?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return const <String, Object?>{};
  }

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {
    return const <String, Object?>{};
  }
  return const <String, Object?>{};
}

String? _payloadString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

num? _payloadNumber(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is num) {
    return value;
  }
  return null;
}
