import '../../analytics/android_background_session_log.dart';
import '../../l10n/kick_localizations.dart';

final RegExp _usingAccountPattern = RegExp(r'^Using account `(.+)`( \(.+\))? for `(.+)`$');

String localizeLogMessage(KickLocalizations l10n, String rawMessage) {
  final message = rawMessage.trim();
  if (message.isEmpty) {
    return rawMessage;
  }

  switch (message) {
    case 'Request received':
      return l10n.logMessageRequestReceived;
    case 'Parsed request':
      return l10n.logMessageParsedRequest;
    case 'Response completed':
      return l10n.logMessageResponseCompleted;
    case 'Streaming response aborted by client':
      return l10n.logMessageStreamClientAborted;
    case 'Retry scheduled after request failure':
      return l10n.logMessageRetryScheduled;
    case 'Retrying with another account after request failure':
      return l10n.logMessageRetryWithAnotherAccount;
    case 'Request succeeded after retries':
      return l10n.logMessageRequestSucceededAfterRetries;
    case 'Request failed after retries':
      return l10n.logMessageRequestFailedAfterRetries;
    case 'Dispatching streaming request to upstream provider':
      return l10n.logMessageDispatchingStreamingRequest;
    case 'Dispatching request to upstream provider':
      return l10n.logMessageDispatchingRequest;
    case 'Upstream provider returned a payload':
      return l10n.logMessageUpstreamPayloadReturned;
    case 'Mapped upstream payload to OpenAI chat completion':
      return l10n.logMessageMappedChatCompletion;
    case 'Proxy session summary':
      return l10n.logMessageProxySessionSummary;
    case androidBackgroundSessionStartedMessage:
      return l10n.logMessageAndroidBackgroundSessionStarted;
    case androidBackgroundSessionEndedMessage:
      return l10n.logMessageAndroidBackgroundSessionEnded;
    case androidBackgroundSessionRecoveredMessage:
      return l10n.logMessageAndroidBackgroundSessionRecovered;
  }

  final usingAccountMatch = _usingAccountPattern.firstMatch(message);
  if (usingAccountMatch != null) {
    final account = '`${usingAccountMatch.group(1)!}`${usingAccountMatch.group(2) ?? ''}';
    final model = '`${usingAccountMatch.group(3)!}`';
    return l10n.logMessageUsingAccountForModel(account, model);
  }

  return rawMessage;
}
