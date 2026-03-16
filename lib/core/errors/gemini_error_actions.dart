import '../../proxy/gemini/gemini_code_assist_client.dart';

String? accountVerificationUrlForError(Object error) {
  if (error is! GeminiGatewayException) {
    return null;
  }

  if (error.detail != GeminiGatewayFailureDetail.accountVerificationRequired) {
    return null;
  }

  final actionUrl = error.actionUrl?.trim();
  if (actionUrl == null || actionUrl.isEmpty) {
    return null;
  }

  return actionUrl;
}
