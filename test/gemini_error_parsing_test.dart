import 'package:flutter_test/flutter_test.dart';
import 'package:kick/proxy/gemini/gemini_code_assist_client.dart';

void main() {
  test('parses retry delay from plain quota message', () {
    final error = decodeGeminiGatewayError(
      429,
      '{"error":{"message":"You have exhausted your capacity on this model. Your quota will reset after 41s."}}',
    );

    expect(error.kind, GeminiGatewayFailureKind.quota);
    expect(error.retryAfter, const Duration(seconds: 41));
  });

  test('parses structured cloud code quota details', () {
    final error = decodeGeminiGatewayError(429, '''
      {
        "error": {
          "code": 429,
          "message": "Rate limit exceeded.",
          "details": [
            {
              "@type": "type.googleapis.com/google.rpc.ErrorInfo",
              "reason": "RATE_LIMIT_EXCEEDED",
              "domain": "cloudcode-pa.googleapis.com",
              "metadata": {
                "quota_limit": "GenerateRequestsPerMinutePerProjectPerModel"
              }
            },
            {
              "@type": "type.googleapis.com/google.rpc.RetryInfo",
              "retryDelay": "34.5s"
            }
          ]
        }
      }
      ''');

    expect(error.kind, GeminiGatewayFailureKind.quota);
    expect(error.retryAfter, const Duration(milliseconds: 34500));
  });

  test('treats validation required as auth issue', () {
    final error = decodeGeminiGatewayError(403, '''
      {
        "error": {
          "code": 403,
          "message": "Validation required.",
          "details": [
            {
              "@type": "type.googleapis.com/google.rpc.ErrorInfo",
              "reason": "VALIDATION_REQUIRED",
              "domain": "cloudcode-pa.googleapis.com"
            }
          ]
        }
      }
      ''');

    expect(error.kind, GeminiGatewayFailureKind.auth);
    expect(error.detail, GeminiGatewayFailureDetail.accountVerificationRequired);
    expect(error.retryAfter, const Duration(minutes: 5));
  });

  test('treats project access denial as configuration issue', () {
    final error = decodeGeminiGatewayError(403, '''
      {
        "error": {
          "code": 403,
          "message": "Permission denied on resource project demo-project.",
          "details": [
            {
              "@type": "type.googleapis.com/google.rpc.ErrorInfo",
              "reason": "SERVICE_DISABLED",
              "domain": "googleapis.com",
              "metadata": {
                "consumer": "projects/1234567890",
                "service": "cloudcode-pa.googleapis.com",
                "activationUrl": "https://console.developers.google.com/apis/api/cloudaicompanion.googleapis.com/overview?project=demo-project"
              }
            },
            {
              "@type": "type.googleapis.com/google.rpc.Help",
              "links": [
                {
                  "description": "Google developers console",
                  "url": "https://console.developers.google.com/apis/api/cloudaicompanion.googleapis.com/overview?project=demo-project"
                }
              ]
            }
          ]
        }
      }
      ''');

    expect(error.kind, GeminiGatewayFailureKind.auth);
    expect(error.detail, GeminiGatewayFailureDetail.projectConfiguration);
    expect(error.upstreamReason, 'SERVICE_DISABLED');
    expect(
      error.actionUrl,
      'https://console.developers.google.com/apis/api/cloudaicompanion.googleapis.com/overview?project=demo-project',
    );
  });

  test('treats 429 no capacity as capacity issue', () {
    final error = decodeGeminiGatewayError(
      429,
      '{"error":{"message":"There is no capacity available for this request. Please retry in 12s."}}',
    );

    expect(error.kind, GeminiGatewayFailureKind.capacity);
    expect(error.retryAfter, const Duration(seconds: 12));
  });

  test('parses quota exhausted retry hints with hours and minutes', () {
    final error = decodeGeminiGatewayError(
      429,
      '{"error":{"message":"QUOTA_EXHAUSTED. Please retry in 2h 15m 30s."}}',
    );

    expect(error.kind, GeminiGatewayFailureKind.quota);
    expect(error.detail, GeminiGatewayFailureDetail.quotaExhausted);
    expect(error.retryAfter, const Duration(hours: 2, minutes: 15, seconds: 30));
  });

  test('does not invent retry delay for quota exhausted without timer', () {
    final error = decodeGeminiGatewayError(429, '''
      {
        "error": {
          "code": 429,
          "message": "Resource has been exhausted (e.g. check quota).",
          "details": [
            {
              "@type": "type.googleapis.com/google.rpc.ErrorInfo",
              "reason": "QUOTA_EXHAUSTED",
              "domain": "googleapis.com"
            }
          ]
        }
      }
      ''');

    expect(error.kind, GeminiGatewayFailureKind.quota);
    expect(error.detail, GeminiGatewayFailureDetail.quotaExhausted);
    expect(error.retryAfter, isNull);
  });

  test('treats thinking config rejection as invalid request detail', () {
    final error = decodeGeminiGatewayError(
      400,
      '{"error":{"message":"Invalid argument: thinking_budget and thinking_level are not supported for this model."}}',
    );

    expect(error.kind, GeminiGatewayFailureKind.invalidRequest);
    expect(error.detail, GeminiGatewayFailureDetail.reasoningConfigUnsupported);
  });

  test('treats bad project id as invalid request detail', () {
    final error = decodeGeminiGatewayError(
      400,
      '{"error":{"message":"Bad Request: project id is invalid for consumer projects/1234567890."}}',
    );

    expect(error.kind, GeminiGatewayFailureKind.invalidRequest);
    expect(error.detail, GeminiGatewayFailureDetail.projectIdMissing);
  });

  test('treats missing project id hidden behind 500 as configuration issue', () {
    final error = decodeGeminiGatewayError(
      500,
      'Could not discover a valid Google Cloud Project ID because no Gemini OAuth credentials were loaded. Configure PROJECT_ID explicitly or provide valid OAuth credentials.',
    );

    expect(error.kind, GeminiGatewayFailureKind.invalidRequest);
    expect(error.detail, GeminiGatewayFailureDetail.projectIdMissing);
  });
}
