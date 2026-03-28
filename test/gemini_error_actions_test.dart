import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/errors/gemini_error_actions.dart';
import 'package:kick/proxy/gemini/gemini_code_assist_client.dart';

void main() {
  test('extracts account verification url from gateway error', () {
    final actionUrl = accountVerificationUrlForError(
      GeminiGatewayException(
        kind: GeminiGatewayFailureKind.auth,
        detail: GeminiGatewayFailureDetail.accountVerificationRequired,
        message: 'Verify your account to continue.',
        statusCode: 403,
        actionUrl: 'https://accounts.google.com/verify',
      ),
    );

    expect(actionUrl, 'https://accounts.google.com/verify');
  });

  test('extracts project configuration action details from gateway error', () {
    final action = primaryActionForError(
      GeminiGatewayException(
        kind: GeminiGatewayFailureKind.auth,
        detail: GeminiGatewayFailureDetail.projectConfiguration,
        message: 'API disabled.',
        statusCode: 403,
        actionUrl: 'https://console.developers.google.com/apis/api/cloudaicompanion.googleapis.com',
      ),
    );

    expect(action?.kind, GeminiErrorActionKind.projectConfiguration);
    expect(
      action?.url,
      'https://console.developers.google.com/apis/api/cloudaicompanion.googleapis.com',
    );
  });

  test('extracts appeal action details from terms of service violations', () {
    final action = primaryActionForError(
      GeminiGatewayException(
        kind: GeminiGatewayFailureKind.auth,
        detail: GeminiGatewayFailureDetail.termsOfServiceViolation,
        message:
            'This service has been disabled in this account for violation of Terms of Service.',
        statusCode: 403,
        actionUrl: 'https://example.com/appeal',
      ),
    );

    expect(action?.kind, GeminiErrorActionKind.accountAppeal);
    expect(action?.url, 'https://example.com/appeal');
  });

  test('ignores non verification errors', () {
    final actionUrl = accountVerificationUrlForError(
      GeminiGatewayException(
        kind: GeminiGatewayFailureKind.auth,
        detail: GeminiGatewayFailureDetail.projectConfiguration,
        message: 'Permission denied.',
        statusCode: 403,
        actionUrl: 'https://accounts.google.com/verify',
      ),
    );

    expect(actionUrl, isNull);
  });
}
