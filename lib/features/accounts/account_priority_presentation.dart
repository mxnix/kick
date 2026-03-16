import '../../core/accounts/account_priority.dart';
import '../../l10n/kick_localizations.dart';

String accountPriorityLabel(KickLocalizations l10n, int value) {
  return switch (AccountPriorityLevel.fromStoredValue(value)) {
    AccountPriorityLevel.primary => l10n.priorityLevelPrimary,
    AccountPriorityLevel.normal => l10n.priorityLevelNormal,
    AccountPriorityLevel.reserve => l10n.priorityLevelReserve,
  };
}
