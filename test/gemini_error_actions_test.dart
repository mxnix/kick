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
