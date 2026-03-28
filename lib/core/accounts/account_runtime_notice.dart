enum AccountRuntimeNoticeKind { banCheckPending, termsOfServiceViolation }

class AccountRuntimeNotice {
  const AccountRuntimeNotice({required this.kind, this.actionUrl});

  final AccountRuntimeNoticeKind kind;
  final String? actionUrl;
}

const _banCheckPendingSnapshotPrefix = 'kick_notice:ban_check_pending';
const _termsOfServiceViolationSnapshotPrefix = 'kick_notice:tos_violation';

String buildBanCheckPendingSnapshot() => _banCheckPendingSnapshotPrefix;

String buildTermsOfServiceViolationSnapshot({String? actionUrl}) {
  final normalizedActionUrl = actionUrl?.trim();
  if (normalizedActionUrl == null || normalizedActionUrl.isEmpty) {
    return _termsOfServiceViolationSnapshotPrefix;
  }
  return '$_termsOfServiceViolationSnapshotPrefix|${Uri.encodeComponent(normalizedActionUrl)}';
}

AccountRuntimeNotice? parseAccountRuntimeNotice(String? snapshot) {
  final normalizedSnapshot = snapshot?.trim();
  if (normalizedSnapshot == null || normalizedSnapshot.isEmpty) {
    return null;
  }
  if (normalizedSnapshot == _banCheckPendingSnapshotPrefix) {
    return const AccountRuntimeNotice(kind: AccountRuntimeNoticeKind.banCheckPending);
  }
  if (normalizedSnapshot.startsWith(_termsOfServiceViolationSnapshotPrefix)) {
    final separatorIndex = normalizedSnapshot.indexOf('|');
    final rawActionUrl = separatorIndex >= 0
        ? normalizedSnapshot.substring(separatorIndex + 1).trim()
        : '';
    return AccountRuntimeNotice(
      kind: AccountRuntimeNoticeKind.termsOfServiceViolation,
      actionUrl: rawActionUrl.isEmpty ? null : Uri.decodeComponent(rawActionUrl),
    );
  }
  return null;
}
