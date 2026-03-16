import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/errors/user_facing_error_formatter.dart';
import 'package:kick/l10n/kick_localizations.dart';
import 'package:kick/proxy/gemini/gemini_code_assist_client.dart';

void main() {
  final l10n = lookupKickLocalizations();

  test('formats account verification errors distinctly', () {
    final message = formatUserFacingError(
      l10n,
      GeminiGatewayException(
        kind: GeminiGatewayFailureKind.auth,
        detail: GeminiGatewayFailureDetail.accountVerificationRequired,
        message: 'Verify your account to continue.',
        statusCode: 403,
        retryAfter: const Duration(minutes: 5),
      ),
    );

    expect(message, l10n.errorGoogleAccountVerificationRequired);
  });

  test('formats quota exhausted retries with explicit delay', () {
    final message = formatUserFacingError(
      l10n,
      GeminiGatewayException(
        kind: GeminiGatewayFailureKind.quota,
        detail: GeminiGatewayFailureDetail.quotaExhausted,
        message: 'QUOTA_EXHAUSTED. Please retry in 1h 20m.',
        statusCode: 429,
        retryAfter: const Duration(hours: 1, minutes: 20),
      ),
    );

    expect(message, l10n.errorQuotaExhaustedRetry('1 ч 20 мин'));
  });

  test('formats raw Google project access errors distinctly', () {
    final message = formatUserFacingMessage(
      l10n,
      'Permission denied on resource project demo-project at cloudcode-pa.googleapis.com.',
    );

    expect(message, l10n.errorGoogleProjectAccessDenied);
  });

  test('formats missing project id errors distinctly', () {
    final message = formatUserFacingMessage(
      l10n,
      'Could not discover a valid Google Cloud Project ID because no Gemini OAuth credentials were loaded. Configure PROJECT_ID explicitly or provide valid OAuth credentials.',
    );

    expect(message, l10n.errorGoogleProjectIdMissing);
  });

  test('formats raw thinking config errors distinctly', () {
    final message = formatUserFacingMessage(
      l10n,
      'Invalid argument: thinking_budget and thinking_level are not supported.',
    );

    expect(message, l10n.errorReasoningConfigRejected);
  });
}
