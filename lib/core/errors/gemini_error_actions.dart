import '../../data/models/account_profile.dart';
import '../../proxy/gemini/gemini_code_assist_client.dart';

enum GeminiErrorActionKind { accountVerification, accountAppeal, projectConfiguration }

class GeminiErrorAction {
  const GeminiErrorAction({required this.kind, required this.url});

  final GeminiErrorActionKind kind;
  final String url;
}

GeminiErrorAction? primaryActionForError(Object error) {
  if (error is! GeminiGatewayException) {
    return null;
  }
  if (error.provider != AccountProvider.gemini) {
    return null;
  }

  final actionUrl = error.actionUrl?.trim();
  if (actionUrl == null || actionUrl.isEmpty) {
    return null;
  }

  return switch (error.detail) {
    GeminiGatewayFailureDetail.accountVerificationRequired => GeminiErrorAction(
      kind: GeminiErrorActionKind.accountVerification,
      url: actionUrl,
    ),
    GeminiGatewayFailureDetail.termsOfServiceViolation => GeminiErrorAction(
      kind: GeminiErrorActionKind.accountAppeal,
      url: actionUrl,
    ),
    GeminiGatewayFailureDetail.projectConfiguration => GeminiErrorAction(
      kind: GeminiErrorActionKind.projectConfiguration,
      url: actionUrl,
    ),
    GeminiGatewayFailureDetail.projectIdMissing ||
    GeminiGatewayFailureDetail.quotaExhausted ||
    GeminiGatewayFailureDetail.indefiniteQuotaExhausted ||
    GeminiGatewayFailureDetail.rateLimited ||
    GeminiGatewayFailureDetail.noHealthyAccountAvailable ||
    GeminiGatewayFailureDetail.reasoningConfigUnsupported ||
    null => null,
  };
}

String? accountVerificationUrlForError(Object error) {
  final action = primaryActionForError(error);
  if (action?.kind != GeminiErrorActionKind.accountVerification) {
    return null;
  }
  return action!.url;
}
