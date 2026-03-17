import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../data/models/oauth_tokens.dart';
import '../account_pool/account_pool.dart';
import '../model_catalog.dart';
import '../openai/openai_request_parser.dart';
import 'gemini_auth_constants.dart';

enum GeminiGatewayFailureKind { auth, quota, capacity, unsupportedModel, invalidRequest, unknown }

enum GeminiGatewayFailureDetail {
  accountVerificationRequired,
  projectIdMissing,
  projectConfiguration,
  quotaExhausted,
  rateLimited,
  reasoningConfigUnsupported,
}

class GeminiGatewayException implements Exception {
  GeminiGatewayException({
    required this.kind,
    required this.message,
    required this.statusCode,
    this.quotaSnapshot,
    this.retryAfter,
    this.detail,
    this.actionUrl,
  });

  final GeminiGatewayFailureKind kind;
  final String message;
  final int statusCode;
  final String? quotaSnapshot;
  final Duration? retryAfter;
  final GeminiGatewayFailureDetail? detail;
  final String? actionUrl;

  @override
  String toString() => 'GeminiGatewayException($statusCode, $kind, $message)';
}

class GeminiRetryPolicy {
  const GeminiRetryPolicy({this.maxRetries = 10, this.baseDelay = const Duration(seconds: 1)});

  final int maxRetries;
  final Duration baseDelay;

  GeminiRetryPolicy normalized() {
    final normalizedMaxRetries = switch (maxRetries) {
      < 0 => 0,
      > 20 => 20,
      _ => maxRetries,
    };
    return GeminiRetryPolicy(
      maxRetries: normalizedMaxRetries,
      baseDelay: baseDelay > Duration.zero ? baseDelay : const Duration(seconds: 1),
    );
  }
}

class GeminiRetryEvent {
  const GeminiRetryEvent({
    required this.attempt,
    required this.maxRetries,
    required this.delay,
    required this.error,
  });

  final int attempt;
  final int maxRetries;
  final Duration delay;
  final GeminiGatewayException error;
}

const _cloudCodeDomains = <String>{
  'cloudcode-pa.googleapis.com',
  'staging-cloudcode-pa.googleapis.com',
  'autopush-cloudcode-pa.googleapis.com',
};
const defaultGeminiRequestMaxRetries = 10;
const defaultGeminiBaseRetryDelay = Duration(seconds: 1);
const _maxTransientRequestRetries = 3;
const _maxRetryable429Delay = Duration(minutes: 1);
const _maxRetryableTransientDelay = Duration(minutes: 5);
const _gemini3DefaultTopK = 64;
const defaultGeminiMaxOutputTokens = 8192;
const _continuationPrompt = 'Please continue from where you left off.';
const _continuationTailLength = 180;
const _maxContinuationPasses = 12;
const _minimumContinuationOverlap = 6;
const _defaultSafetySettings = [
  {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'OFF'},
  {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'OFF'},
  {'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold': 'OFF'},
  {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'OFF'},
  {'category': 'HARM_CATEGORY_CIVIC_INTEGRITY', 'threshold': 'OFF'},
];

GeminiGatewayException decodeGeminiGatewayError(int statusCode, String body) {
  final decoded = _tryDecodeJsonMap(body);
  final error = ((decoded['error'] as Map?) ?? decoded).cast<String, Object?>();
  final message = (error['message'] as String?)?.trim().isNotEmpty == true
      ? (error['message'] as String).trim()
      : body;
  final details = ((error['details'] as List?) ?? const [])
      .whereType<Map>()
      .map((detail) => detail.cast<String, Object?>())
      .toList(growable: false);
  final errorInfo = _typedDetail(details, 'type.googleapis.com/google.rpc.ErrorInfo');
  final help = _typedDetail(details, 'type.googleapis.com/google.rpc.Help');
  final retryInfo = _typedDetail(details, 'type.googleapis.com/google.rpc.RetryInfo');
  final quotaFailure = _typedDetail(details, 'type.googleapis.com/google.rpc.QuotaFailure');
  final errorReason = errorInfo?['reason'] as String?;
  final errorDomain = _sanitizeDomain(errorInfo?['domain'] as String?);
  final errorMetadata = ((errorInfo?['metadata'] as Map?) ?? const <String, Object?>{})
      .cast<String, Object?>();
  final lower = message.toLowerCase();
  final quotaSnapshot = decoded['quota']?.toString();
  final actionUrl = _accountVerificationUrl(errorMetadata, help);
  final isProjectIdMissing = _looksLikeMissingProjectIdError(lower);

  if (statusCode == 404 ||
      lower.contains('unsupported model') ||
      lower.contains('not found model') ||
      lower.contains('model not found')) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.unsupportedModel,
      message: message,
      statusCode: statusCode,
    );
  }

  final isAccountVerificationRequired =
      statusCode == 403 &&
      errorReason == 'VALIDATION_REQUIRED' &&
      errorDomain != null &&
      _cloudCodeDomains.contains(errorDomain);
  final isProjectConfigurationError = _looksLikeProjectConfigurationError(
    statusCode,
    lower,
    errorReason,
    errorMetadata,
  );
  final isAuthProjectConfigurationError = statusCode == 403 && isProjectConfigurationError;

  if (statusCode == 401 || isAccountVerificationRequired || isAuthProjectConfigurationError) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.auth,
      message: message,
      statusCode: statusCode,
      detail: isAccountVerificationRequired
          ? GeminiGatewayFailureDetail.accountVerificationRequired
          : isProjectIdMissing
          ? GeminiGatewayFailureDetail.projectIdMissing
          : isAuthProjectConfigurationError
          ? GeminiGatewayFailureDetail.projectConfiguration
          : null,
      retryAfter: isAccountVerificationRequired ? const Duration(minutes: 5) : null,
      actionUrl: actionUrl,
    );
  }

  if (isProjectConfigurationError) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.invalidRequest,
      message: message,
      statusCode: statusCode == 0 ? 400 : statusCode,
      detail: isProjectIdMissing
          ? GeminiGatewayFailureDetail.projectIdMissing
          : GeminiGatewayFailureDetail.projectConfiguration,
    );
  }

  final retryAfter = _retryAfterFromRetryInfo(retryInfo) ?? _retryAfterFromMessage(message);
  final quotaLimit = (errorMetadata['quota_limit'] as String?)?.toLowerCase() ?? '';
  final hasDailyQuota =
      _quotaFailureMatches(quotaFailure, 'perday') ||
      _quotaFailureMatches(quotaFailure, 'daily') ||
      quotaLimit.contains('perday') ||
      quotaLimit.contains('daily') ||
      errorReason == 'QUOTA_EXHAUSTED' ||
      errorReason == 'INSUFFICIENT_G1_CREDITS_BALANCE';
  final hasShortQuota =
      _quotaFailureMatches(quotaFailure, 'perminute') ||
      _quotaFailureMatches(quotaFailure, 'perhour') ||
      quotaLimit.contains('perminute') ||
      quotaLimit.contains('perhour') ||
      errorReason == 'RATE_LIMIT_EXCEEDED' ||
      lower.contains('reset after') ||
      lower.contains('please retry in');
  final isQuotaExhausted =
      hasDailyQuota ||
      lower.contains('quota_exhausted') ||
      lower.contains('quota exhausted') ||
      lower.contains('exhausted your capacity on this model') ||
      lower.contains('resource has been exhausted');
  final hasCapacityPressure =
      lower.contains('no capacity') ||
      lower.contains('capacity temporarily unavailable') ||
      lower.contains('model is overloaded') ||
      lower.contains('server overloaded') ||
      (lower.contains('capacity') && !lower.contains('quota'));

  if (statusCode == 429 && hasCapacityPressure) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.capacity,
      message: message,
      statusCode: statusCode,
      retryAfter: retryAfter ?? const Duration(seconds: 30),
    );
  }

  if (statusCode == 429 ||
      statusCode == 499 ||
      lower.contains('quota') ||
      lower.contains('resource exhausted') ||
      hasDailyQuota ||
      hasShortQuota) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.quota,
      message: message,
      statusCode: statusCode == 0 ? 429 : statusCode,
      quotaSnapshot: quotaSnapshot,
      detail: isQuotaExhausted
          ? GeminiGatewayFailureDetail.quotaExhausted
          : GeminiGatewayFailureDetail.rateLimited,
      retryAfter: retryAfter ?? (hasShortQuota ? const Duration(minutes: 1) : null),
    );
  }

  if (statusCode == 503 ||
      statusCode >= 500 ||
      hasCapacityPressure ||
      lower.contains('capacity') ||
      lower.contains('unavailable')) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.capacity,
      message: message,
      statusCode: statusCode == 0 ? 503 : statusCode,
      retryAfter: retryAfter,
    );
  }

  if (statusCode == 400) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.invalidRequest,
      message: message,
      statusCode: statusCode,
      detail: _looksLikeReasoningConfigError(lower)
          ? GeminiGatewayFailureDetail.reasoningConfigUnsupported
          : _looksLikeProjectConfigurationError(statusCode, lower, errorReason, errorMetadata)
          ? GeminiGatewayFailureDetail.projectConfiguration
          : null,
    );
  }

  return GeminiGatewayException(
    kind: GeminiGatewayFailureKind.unknown,
    message: message,
    statusCode: statusCode,
    retryAfter: retryAfter,
  );
}

class GeminiCodeAssistClient {
  GeminiCodeAssistClient({
    required Future<void> Function(ProxyRuntimeAccount account, OAuthTokens tokens) onTokensUpdated,
    http.Client? httpClient,
    Future<void> Function(Duration delay)? wait,
    GeminiRetryPolicy retryPolicy = const GeminiRetryPolicy(),
    Duration requestTimeout = const Duration(seconds: 45),
  }) : _onTokensUpdated = onTokensUpdated,
       _http = httpClient ?? http.Client(),
       _wait = wait ?? _defaultWait,
       _retryPolicy = retryPolicy.normalized(),
       _requestTimeout = requestTimeout > Duration.zero
           ? requestTimeout
           : const Duration(seconds: 45);

  final Future<void> Function(ProxyRuntimeAccount account, OAuthTokens tokens) _onTokensUpdated;
  final http.Client _http;
  final Future<void> Function(Duration delay) _wait;
  GeminiRetryPolicy _retryPolicy;
  final Duration _requestTimeout;
  int _promptSequence = 0;

  void updateRetryPolicy(GeminiRetryPolicy retryPolicy) {
    _retryPolicy = retryPolicy.normalized();
  }

  Future<Map<String, Object?>> generateContent({
    required ProxyRuntimeAccount account,
    required UnifiedPromptRequest request,
    void Function(GeminiRetryEvent event)? onRetry,
  }) async {
    await _ensureFreshTokens(account);
    final resolvedModel = ModelCatalog.normalizeModel(request.model);
    final baseRequestBody = _buildRequestBody(request, resolvedModel: resolvedModel);
    return _generateWithContinuation(
      account: account,
      model: resolvedModel,
      projectId: account.projectId,
      requestId: request.requestId,
      baseRequestBody: baseRequestBody,
      onRetry: onRetry,
    );
  }

  Future<Stream<Map<String, Object?>>> generateContentStream({
    required ProxyRuntimeAccount account,
    required UnifiedPromptRequest request,
    void Function(GeminiRetryEvent event)? onRetry,
  }) async {
    await _ensureFreshTokens(account);
    final resolvedModel = ModelCatalog.normalizeModel(request.model);
    final baseRequestBody = _buildRequestBody(request, resolvedModel: resolvedModel);
    StreamIterator<Map<String, Object?>>? payloadIterator;
    var canceled = false;
    final controller = StreamController<Map<String, Object?>>(
      onCancel: () async {
        canceled = true;
        await payloadIterator?.cancel();
      },
    );
    unawaited(
      Future<void>(() async {
        var currentRequestBody = baseRequestBody;
        var accumulatedText = '';
        try {
          for (var pass = 0; pass <= _maxContinuationPasses; pass++) {
            if (canceled) {
              break;
            }
            final accumulatedBeforePass = accumulatedText;
            await _ensureFreshTokens(account);
            if (canceled) {
              break;
            }
            final response = await _executeWithRetry(
              () => _sendStreamRequest(
                accessToken: account.tokens.accessToken,
                model: resolvedModel,
                projectId: account.projectId,
                promptSeed: request.requestId,
                requestBody: currentRequestBody,
              ),
              onRetry: onRetry,
            );

            Map<String, Object?>? lastPayload;
            final iterator = StreamIterator<Map<String, Object?>>(_streamResponse(response));
            payloadIterator = iterator;
            try {
              while (!canceled && await iterator.moveNext()) {
                final rawPayload = iterator.current;
                final generatedText = _extractGeneratedText(rawPayload);
                final mergedText = pass == 0
                    ? generatedText
                    : _appendContinuationText(accumulatedBeforePass, generatedText);
                final emittedPayload = mergedText == generatedText
                    ? rawPayload
                    : _withAccumulatedText(rawPayload, mergedText);
                lastPayload = emittedPayload;
                controller.add(emittedPayload);
              }
            } finally {
              await iterator.cancel();
              if (identical(payloadIterator, iterator)) {
                payloadIterator = null;
              }
            }

            if (canceled) {
              break;
            }

            if (lastPayload == null) {
              break;
            }

            final mergedText = _extractGeneratedText(lastPayload);
            if (mergedText.isNotEmpty) {
              accumulatedText = mergedText;
            }

            final shouldContinue =
                _extractFinishReason(lastPayload) == 'MAX_TOKENS' &&
                accumulatedText.isNotEmpty &&
                accumulatedText != accumulatedBeforePass &&
                pass < _maxContinuationPasses;
            if (!shouldContinue) {
              break;
            }

            currentRequestBody = _buildContinuationRequestBody(
              baseRequestBody: baseRequestBody,
              accumulatedText: accumulatedText,
            );
          }
        } catch (error) {
          if (!canceled) {
            controller.addError(_decodeTransportError(error));
          }
        } finally {
          payloadIterator = null;
          if (!controller.isClosed) {
            await controller.close();
          }
        }
      }),
    );
    return controller.stream;
  }

  Future<Map<String, Object?>> _generateWithContinuation({
    required ProxyRuntimeAccount account,
    required String model,
    required String projectId,
    required String requestId,
    required Map<String, Object?> baseRequestBody,
    void Function(GeminiRetryEvent event)? onRetry,
  }) async {
    var currentRequestBody = baseRequestBody;
    var accumulatedText = '';
    Map<String, Object?>? lastPayload;

    for (var pass = 0; pass <= _maxContinuationPasses; pass++) {
      final accumulatedBeforePass = accumulatedText;
      await _ensureFreshTokens(account);
      final payload = await _executeWithRetry(
        () => _sendUnaryRequest(
          accessToken: account.tokens.accessToken,
          model: model,
          projectId: projectId,
          promptSeed: requestId,
          requestBody: currentRequestBody,
        ),
        onRetry: onRetry,
      );
      lastPayload = payload;

      final generatedText = _extractGeneratedText(payload);
      if (generatedText.isNotEmpty) {
        accumulatedText = pass == 0
            ? generatedText
            : _appendContinuationText(accumulatedBeforePass, generatedText);
      }

      final shouldContinue =
          _extractFinishReason(payload) == 'MAX_TOKENS' &&
          accumulatedText.isNotEmpty &&
          accumulatedText != accumulatedBeforePass &&
          pass < _maxContinuationPasses;
      if (!shouldContinue) {
        return accumulatedText.isEmpty ? payload : _withAccumulatedText(payload, accumulatedText);
      }

      currentRequestBody = _buildContinuationRequestBody(
        baseRequestBody: baseRequestBody,
        accumulatedText: accumulatedText,
      );
    }

    if (lastPayload == null) {
      throw GeminiGatewayException(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Gemini continuation finished without a payload.',
        statusCode: 500,
      );
    }

    return accumulatedText.isEmpty
        ? lastPayload
        : _withAccumulatedText(lastPayload, accumulatedText);
  }

  Map<String, Object?> _buildRequestBody(
    UnifiedPromptRequest request, {
    required String resolvedModel,
  }) {
    final sessionId = _buildCodeAssistSessionId(request.requestId);
    final contents = <Map<String, Object?>>[];
    for (final turn in request.turns) {
      final role = turn.role == 'assistant' ? 'model' : 'user';
      final parts = <Map<String, Object?>>[];
      for (final part in turn.parts) {
        switch (part.type) {
          case UnifiedPartType.text:
            if ((part.text ?? '').trim().isNotEmpty) {
              parts.add({'text': part.text!.trim()});
            }
            break;
          case UnifiedPartType.functionCall:
            parts.add({
              'functionCall': {
                'name': part.name,
                'args': part.arguments ?? const <String, Object?>{},
              },
            });
            break;
          case UnifiedPartType.functionResponse:
            parts.add({
              'functionResponse': {
                'name': part.name,
                'response': part.arguments ?? const <String, Object?>{},
              },
            });
            break;
          case UnifiedPartType.inlineData:
            if ((part.data ?? '').isNotEmpty) {
              parts.add({
                'inlineData': {
                  'mimeType': part.mimeType ?? 'application/octet-stream',
                  'data': part.data,
                },
              });
            }
            break;
          case UnifiedPartType.fileData:
            if ((part.fileUri ?? '').isNotEmpty) {
              parts.add({
                'fileData': {
                  'mimeType': part.mimeType ?? 'application/octet-stream',
                  'fileUri': part.fileUri,
                },
              });
            }
            break;
        }
      }
      if (parts.isEmpty) {
        continue;
      }
      if (contents.isNotEmpty && contents.last['role'] == role) {
        final mergedParts = List<Object?>.from((contents.last['parts'] as List?) ?? const []);
        mergedParts.addAll(parts);
        contents.last['parts'] = mergedParts;
      } else {
        contents.add({'role': role, 'parts': parts});
      }
    }

    final generationConfig = <String, Object?>{};
    if (request.temperature != null) {
      generationConfig['temperature'] = request.temperature;
    }
    if (request.topP != null) {
      generationConfig['topP'] = request.topP;
    }
    generationConfig['maxOutputTokens'] = request.maxOutputTokens ?? defaultGeminiMaxOutputTokens;
    if (_isGemini3Model(resolvedModel)) {
      generationConfig['topK'] = _gemini3DefaultTopK;
    }
    if (request.stopSequences case final stopSequences? when stopSequences.isNotEmpty) {
      generationConfig['stopSequences'] = stopSequences;
    }
    if (request.jsonMode) {
      generationConfig['responseMimeType'] = 'application/json';
    }
    if (request.responseSchema != null) {
      generationConfig['responseSchema'] = request.responseSchema;
    }
    if (_buildThinkingConfig(request, resolvedModel) case final thinkingConfig?
        when thinkingConfig.isNotEmpty) {
      generationConfig['thinkingConfig'] = thinkingConfig;
    }
    if (_resolveResponseModalities(request, resolvedModel) case final responseModalities?
        when responseModalities.isNotEmpty) {
      generationConfig['responseModalities'] = responseModalities;
    }

    final tools = request.tools.isEmpty
        ? null
        : [
            {
              'functionDeclarations': [
                for (final tool in request.tools)
                  {
                    'name': tool.name,
                    'description': tool.description,
                    'parameters': tool.parameters,
                  },
              ],
            },
          ];

    return {
      'contents': contents,
      if (request.systemInstruction != null)
        'systemInstruction': {
          'role': 'user',
          'parts': [
            {'text': request.systemInstruction},
          ],
        },
      if (tools case final resolvedTools?) ...{
        'tools': resolvedTools,
        'toolConfig': _buildToolConfig(request.toolChoice),
      },
      if (generationConfig.isNotEmpty) 'generationConfig': generationConfig,
      'safetySettings': _defaultSafetySettings,
      'session_id': sessionId,
    };
  }

  Map<String, Object?> _buildToolConfig(Object? toolChoice) {
    if (toolChoice is String) {
      switch (toolChoice) {
        case 'required':
          return {
            'functionCallingConfig': {'mode': 'ANY'},
          };
        case 'none':
          return {
            'functionCallingConfig': {'mode': 'NONE'},
          };
        default:
          return {
            'functionCallingConfig': {'mode': 'AUTO'},
          };
      }
    }

    if (toolChoice is Map) {
      final function =
          (toolChoice['function'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
      final name = function['name'] as String?;
      if (name != null && name.isNotEmpty) {
        return {
          'functionCallingConfig': {
            'mode': 'ANY',
            'allowedFunctionNames': [name],
          },
        };
      }
    }

    return {
      'functionCallingConfig': {'mode': 'AUTO'},
    };
  }

  Future<void> _ensureFreshTokens(ProxyRuntimeAccount account) async {
    if (!account.tokens.isExpired) {
      return;
    }

    final refreshed = await _refreshTokens(account.tokens);
    account.tokens = refreshed;
    await _onTokensUpdated(account, refreshed);
  }

  Future<OAuthTokens> _refreshTokens(OAuthTokens tokens) async {
    final response = await _runWithRequestTimeout(
      () => _http.post(
        Uri.https('oauth2.googleapis.com', '/token'),
        headers: {HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded'},
        body: {
          'client_id': geminiOAuthClientId,
          'client_secret': geminiOAuthClientSecret,
          'refresh_token': tokens.refreshToken,
          'grant_type': 'refresh_token',
        },
      ),
      'Gemini OAuth token refresh',
    );
    if (response.statusCode >= 400) {
      throw decodeGeminiGatewayError(response.statusCode, response.body);
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return OAuthTokens(
      accessToken: payload['access_token'] as String? ?? '',
      refreshToken: tokens.refreshToken,
      expiry: DateTime.now().add(Duration(seconds: payload['expires_in'] as int? ?? 3600)),
      tokenType: payload['token_type'] as String? ?? 'Bearer',
      scope: payload['scope'] as String?,
    );
  }

  Uri _methodUri(String method) {
    return Uri.parse('$geminiCodeAssistEndpoint/$geminiCodeAssistApiVersion:$method');
  }

  Map<String, String> _headers(String accessToken, {required String model}) {
    return {
      HttpHeaders.authorizationHeader: 'Bearer $accessToken',
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.userAgentHeader: _buildGeminiCliUserAgent(model),
    };
  }

  Map<String, Object?> _decodeResponse(http.Response response) {
    if (response.statusCode >= 400) {
      throw decodeGeminiGatewayError(response.statusCode, response.body);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw GeminiGatewayException(
        kind: GeminiGatewayFailureKind.unknown,
        message: 'Unexpected Gemini response shape.',
        statusCode: response.statusCode,
      );
    }
    return decoded.cast<String, Object?>();
  }

  Future<Map<String, Object?>> _sendUnaryRequest({
    required String accessToken,
    required String model,
    required String projectId,
    required String promptSeed,
    required Map<String, Object?> requestBody,
  }) async {
    final response = await _runWithRequestTimeout(
      () => _http.post(
        _methodUri('generateContent'),
        headers: _headers(accessToken, model: model),
        body: jsonEncode(
          _buildRequestEnvelope(
            model: model,
            projectId: projectId,
            promptSeed: promptSeed,
            requestBody: requestBody,
          ),
        ),
      ),
      'Gemini request',
    );
    return _decodeResponse(response);
  }

  Future<http.StreamedResponse> _sendStreamRequest({
    required String accessToken,
    required String model,
    required String projectId,
    required String promptSeed,
    required Map<String, Object?> requestBody,
  }) async {
    final httpRequest =
        http.Request(
            'POST',
            _methodUri('streamGenerateContent').replace(queryParameters: {'alt': 'sse'}),
          )
          ..headers.addAll(_headers(accessToken, model: model))
          ..body = jsonEncode(
            _buildRequestEnvelope(
              model: model,
              projectId: projectId,
              promptSeed: promptSeed,
              requestBody: requestBody,
            ),
          );
    final response = await _runWithRequestTimeout(
      () => _http.send(httpRequest),
      'Gemini streaming request',
    );
    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      throw decodeGeminiGatewayError(response.statusCode, body);
    }
    return response;
  }

  Stream<Map<String, Object?>> _streamResponse(http.StreamedResponse response) {
    StreamIterator<String>? lineIterator;
    final controller = StreamController<Map<String, Object?>>(
      onCancel: () async {
        await lineIterator?.cancel();
      },
    );
    unawaited(
      Future<void>(() async {
        try {
          final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
          lineIterator = StreamIterator<String>(lines);
          final buffer = <String>[];
          while (await lineIterator!.moveNext()) {
            final line = lineIterator!.current;
            if (line.startsWith('data: ')) {
              buffer.add(line.substring(6).trim());
              continue;
            }
            if (line.isEmpty && buffer.isNotEmpty) {
              _emitBufferedChunk(controller, buffer);
              buffer.clear();
            }
          }
          if (buffer.isNotEmpty) {
            _emitBufferedChunk(controller, buffer);
          }
        } catch (error) {
          controller.addError(_decodeTransportError(error));
        } finally {
          lineIterator = null;
          if (!controller.isClosed) {
            await controller.close();
          }
        }
      }),
    );
    return controller.stream;
  }

  void _emitBufferedChunk(StreamController<Map<String, Object?>> controller, List<String> buffer) {
    final chunk = buffer.join('\n');
    try {
      final decoded = jsonDecode(chunk);
      if (decoded is Map<String, dynamic>) {
        controller.add(decoded.cast<String, Object?>());
      }
    } on FormatException {
      // Gemini SSE occasionally includes non-JSON noise between data frames.
      // Ignore those chunks so an otherwise valid stream can continue.
    }
  }

  Future<T> _executeWithRetry<T>(
    Future<T> Function() operation, {
    void Function(GeminiRetryEvent event)? onRetry,
  }) async {
    GeminiGatewayException? lastError;
    for (var attempt = 0; attempt <= _retryPolicy.maxRetries; attempt++) {
      try {
        return await operation();
      } catch (error) {
        final gatewayError = _decodeTransportError(error);
        lastError = gatewayError;
        if (!_shouldRetryRequest(gatewayError, attempt)) {
          throw gatewayError;
        }
        final delay = _retryDelayFor(gatewayError, attempt);
        onRetry?.call(
          GeminiRetryEvent(
            attempt: attempt + 1,
            maxRetries: _retryLimitFor(gatewayError),
            delay: delay,
            error: gatewayError,
          ),
        );
        await _wait(delay);
      }
    }

    throw lastError ??
        GeminiGatewayException(
          kind: GeminiGatewayFailureKind.unknown,
          message: 'Gemini request failed after retries.',
          statusCode: 500,
        );
  }

  bool _shouldRetryRequest(GeminiGatewayException error, int attempt) {
    final retryLimit = _retryLimitFor(error);
    if (attempt >= retryLimit) {
      return false;
    }

    if (_exceedsRetryDelayWindow(error)) {
      return false;
    }

    switch (error.kind) {
      case GeminiGatewayFailureKind.quota:
      case GeminiGatewayFailureKind.capacity:
        return true;
      case GeminiGatewayFailureKind.unknown:
        return error.statusCode >= 500;
      case GeminiGatewayFailureKind.auth:
      case GeminiGatewayFailureKind.unsupportedModel:
      case GeminiGatewayFailureKind.invalidRequest:
        return false;
    }
  }

  Duration _retryDelayFor(GeminiGatewayException error, int attempt) {
    final hintedDelay = error.retryAfter;
    if (hintedDelay != null && hintedDelay > Duration.zero) {
      return hintedDelay;
    }

    final multiplier = 1 << attempt;
    return Duration(milliseconds: _retryPolicy.baseDelay.inMilliseconds * multiplier);
  }

  int _retryLimitFor(GeminiGatewayException error) {
    switch (error.kind) {
      case GeminiGatewayFailureKind.quota:
        return _retryPolicy.maxRetries;
      case GeminiGatewayFailureKind.capacity:
        return _isNoCapacityFailure(error)
            ? _retryPolicy.maxRetries
            : min(_retryPolicy.maxRetries, _maxTransientRequestRetries);
      case GeminiGatewayFailureKind.unknown:
        return error.statusCode >= 500
            ? min(_retryPolicy.maxRetries, _maxTransientRequestRetries)
            : 0;
      case GeminiGatewayFailureKind.auth:
      case GeminiGatewayFailureKind.unsupportedModel:
      case GeminiGatewayFailureKind.invalidRequest:
        return 0;
    }
  }

  bool _exceedsRetryDelayWindow(GeminiGatewayException error) {
    final retryAfter = error.retryAfter;
    if (retryAfter == null) {
      return false;
    }

    if (error.statusCode == 429 && !_isNoCapacityFailure(error)) {
      return retryAfter >= _maxRetryable429Delay;
    }

    return retryAfter > _maxRetryableTransientDelay;
  }

  bool _isNoCapacityFailure(GeminiGatewayException error) {
    return error.kind == GeminiGatewayFailureKind.capacity &&
        error.message.toLowerCase().contains('no capacity');
  }

  GeminiGatewayException _decodeTransportError(Object error) {
    if (error is GeminiGatewayException) {
      return error;
    }

    if (error is TimeoutException) {
      final message = (error.message?.toString().trim().isNotEmpty == true)
          ? error.message!.toString().trim()
          : 'Timed out while contacting Gemini Code Assist.';
      return GeminiGatewayException(
        kind: GeminiGatewayFailureKind.capacity,
        message: message,
        statusCode: 503,
      );
    }

    if (error is SocketException) {
      return GeminiGatewayException(
        kind: GeminiGatewayFailureKind.capacity,
        message: 'Network error while contacting Gemini Code Assist: ${error.message}',
        statusCode: 503,
      );
    }

    if (error is http.ClientException) {
      return GeminiGatewayException(
        kind: GeminiGatewayFailureKind.capacity,
        message: 'HTTP client error while contacting Gemini Code Assist: ${error.message}',
        statusCode: 503,
      );
    }

    if (error is HttpException) {
      return GeminiGatewayException(
        kind: GeminiGatewayFailureKind.capacity,
        message: 'HTTP error while contacting Gemini Code Assist: ${error.message}',
        statusCode: 503,
      );
    }

    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.unknown,
      message: error.toString(),
      statusCode: 500,
    );
  }

  Future<T> _runWithRequestTimeout<T>(Future<T> Function() operation, String label) {
    return operation().timeout(
      _requestTimeout,
      onTimeout: () =>
          throw TimeoutException('$label timed out while contacting Gemini Code Assist.'),
    );
  }

  Map<String, Object?> _buildRequestEnvelope({
    required String model,
    required String projectId,
    required String promptSeed,
    required Map<String, Object?> requestBody,
  }) {
    final existingSessionId = (requestBody['session_id'] as String?)?.trim();
    final sessionId = existingSessionId?.isNotEmpty == true
        ? existingSessionId!
        : _buildCodeAssistSessionId(promptSeed);
    final normalizedRequest = _deepCopyJsonMap(requestBody)..['session_id'] = sessionId;

    return {
      'model': model,
      'project': projectId,
      'user_prompt_id': _buildCodeAssistPromptId(
        sessionId,
        promptSeed,
        sequence: _nextPromptSequence(),
      ),
      'request': normalizedRequest,
    };
  }

  int _nextPromptSequence() {
    _promptSequence += 1;
    return _promptSequence;
  }

  Map<String, Object?> _buildContinuationRequestBody({
    required Map<String, Object?> baseRequestBody,
    required String accumulatedText,
  }) {
    final requestBody = _deepCopyJsonMap(baseRequestBody);
    final contents = ((requestBody['contents'] as List?) ?? const [])
        .map((item) => item is Map ? item.cast<String, Object?>() : <String, Object?>{})
        .toList(growable: true);
    contents.add({
      'role': 'model',
      'parts': [
        {'text': accumulatedText},
      ],
    });
    contents.add({
      'role': 'user',
      'parts': [
        {'text': _buildContinuationPrompt(accumulatedText)},
      ],
    });
    requestBody['contents'] = contents;
    return requestBody;
  }

  String _extractGeneratedText(Map<String, Object?> payload) {
    final response = ((payload['response'] as Map?) ?? payload).cast<String, Object?>();
    final candidate = _firstCandidate(response);
    final content = ((candidate['content'] as Map?) ?? const <String, Object?>{})
        .cast<String, Object?>();
    final parts = (content['parts'] as List?) ?? const [];
    final buffer = StringBuffer();
    for (final rawPart in parts) {
      if (rawPart is! Map) {
        continue;
      }
      final part = rawPart.cast<String, Object?>();
      if (part['text'] is String) {
        buffer.write(part['text'] as String);
      }
    }
    return buffer.toString();
  }

  String? _extractFinishReason(Map<String, Object?> payload) {
    final response = ((payload['response'] as Map?) ?? payload).cast<String, Object?>();
    final candidate = _firstCandidate(response);
    return candidate['finishReason'] as String?;
  }

  Map<String, Object?> _withAccumulatedText(Map<String, Object?> payload, String accumulatedText) {
    final copy = _deepCopyJsonMap(payload);
    final response = ((copy['response'] as Map?) ?? copy).cast<String, Object?>();
    final candidate = _firstCandidate(response);
    if (candidate.isEmpty) {
      return copy;
    }

    final content = ((candidate['content'] as Map?) ?? const <String, Object?>{})
        .cast<String, Object?>();
    final rawParts = (content['parts'] as List?) ?? const [];
    final nonTextParts = <Map<String, Object?>>[];
    for (final rawPart in rawParts) {
      if (rawPart is! Map) {
        continue;
      }
      final part = rawPart.cast<String, Object?>();
      if (part['text'] is! String) {
        nonTextParts.add(part);
      }
    }

    content['parts'] = [
      if (accumulatedText.isNotEmpty) {'text': accumulatedText},
      ...nonTextParts,
    ];
    candidate['content'] = content;
    final candidates = ((response['candidates'] as List?) ?? const []).toList(growable: true);
    if (candidates.isNotEmpty) {
      candidates[0] = candidate;
      response['candidates'] = candidates;
    }
    return copy;
  }

  Map<String, Object?> _firstCandidate(Map<String, Object?> response) {
    final candidates = (response['candidates'] as List?) ?? const [];
    if (candidates.isEmpty || candidates.first is! Map) {
      return <String, Object?>{};
    }
    return (candidates.first as Map).cast<String, Object?>();
  }

  String _appendContinuationText(String accumulatedText, String nextText) {
    if (accumulatedText.isEmpty) {
      return nextText;
    }
    if (nextText.isEmpty) {
      return accumulatedText;
    }

    if (accumulatedText == nextText ||
        accumulatedText.startsWith(nextText) ||
        accumulatedText.contains(nextText)) {
      return accumulatedText;
    }

    final accumulatedIndex = nextText.indexOf(accumulatedText);
    if (accumulatedIndex >= 0) {
      return _appendContinuationSuffix(
        accumulatedText,
        nextText.substring(accumulatedIndex + accumulatedText.length),
      );
    }

    final maxOverlap = min(accumulatedText.length, nextText.length);
    for (var overlap = maxOverlap; overlap > 0; overlap--) {
      if (overlap < _minimumContinuationOverlap) {
        break;
      }
      final suffix = accumulatedText.substring(accumulatedText.length - overlap);
      final matchIndex = nextText.indexOf(suffix);
      if (matchIndex >= 0) {
        return _appendContinuationSuffix(accumulatedText, nextText.substring(matchIndex + overlap));
      }
    }

    if (_trailingWordOverlap(accumulatedText, nextText) case final mergedText?) {
      return mergedText;
    }

    if (_looksLikeDirectContinuation(nextText)) {
      return _appendContinuationSuffix(accumulatedText, nextText);
    }

    return accumulatedText;
  }

  String _appendContinuationSuffix(String accumulatedText, String suffix) {
    if (accumulatedText.isEmpty || suffix.isEmpty) {
      return accumulatedText + suffix;
    }

    if (_shouldInsertContinuationSpace(accumulatedText, suffix)) {
      return '$accumulatedText $suffix';
    }

    return accumulatedText + suffix;
  }

  bool _shouldInsertContinuationSpace(String accumulatedText, String suffix) {
    if (accumulatedText.isEmpty || suffix.isEmpty) {
      return false;
    }

    final last = accumulatedText.substring(accumulatedText.length - 1);
    final first = suffix[0];
    if (RegExp(r'\s').hasMatch(last) || RegExp(r'\s').hasMatch(first)) {
      return false;
    }

    if (',.;:!?)]}'.contains(first)) {
      return false;
    }

    final lastWordLike = _isLetterOrDigit(last) || '"\'”’)]}'.contains(last);
    final firstWordLike = _isLetterOrDigit(first) || '"\'“‘([{'.contains(first);
    return lastWordLike && firstWordLike;
  }

  String? _trailingWordOverlap(String accumulatedText, String nextText) {
    final trailingWord = _trailingWord(accumulatedText);
    if (trailingWord.isEmpty ||
        !nextText.startsWith(trailingWord) ||
        nextText.length <= trailingWord.length) {
      return null;
    }

    return _appendContinuationSuffix(accumulatedText, nextText.substring(trailingWord.length));
  }

  Map<String, Object?>? _buildThinkingConfig(UnifiedPromptRequest request, String model) {
    final reasoningEffort = request.reasoningEffort?.trim().toLowerCase();
    if (reasoningEffort != null && reasoningEffort.isNotEmpty && _modelSupportsThinking(model)) {
      if (_isGemini3Model(model)) {
        return switch (reasoningEffort) {
          'none' => null,
          'auto' => {'includeThoughts': true},
          'low' || 'medium' || 'high' => {'thinkingLevel': reasoningEffort.toUpperCase()},
          _ => null,
        };
      }

      return switch (reasoningEffort) {
        'none' => {'thinkingBudget': 0, 'includeThoughts': false},
        'auto' => {'includeThoughts': true},
        'low' => {'thinkingBudget': 1024, 'includeThoughts': true},
        'medium' => {'thinkingBudget': 8192, 'includeThoughts': true},
        'high' => {'thinkingBudget': 24576, 'includeThoughts': true},
        _ => null,
      };
    }

    final googleThinkingConfig = request.googleThinkingConfig;
    if (googleThinkingConfig == null || !_modelSupportsThinking(model) || _isGemini3Model(model)) {
      return null;
    }

    final thinkingConfig = <String, Object?>{};
    final budget =
        _parseInteger(googleThinkingConfig['thinkingBudget']) ??
        _parseInteger(googleThinkingConfig['thinking_budget']);
    if (budget != null) {
      thinkingConfig['thinkingBudget'] = budget;
    }

    if (googleThinkingConfig['includeThoughts'] is bool) {
      thinkingConfig['includeThoughts'] = googleThinkingConfig['includeThoughts'] as bool;
    } else if (googleThinkingConfig['include_thoughts'] is bool) {
      thinkingConfig['includeThoughts'] = googleThinkingConfig['include_thoughts'] as bool;
    } else if (budget != null && budget != 0) {
      thinkingConfig['includeThoughts'] = true;
    }

    return thinkingConfig.isEmpty ? null : thinkingConfig;
  }

  List<String>? _resolveResponseModalities(UnifiedPromptRequest request, String model) {
    if (request.responseModalities case final explicitModalities?
        when explicitModalities.isNotEmpty) {
      final normalized = explicitModalities
          .map(_normalizeResponseModality)
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      return normalized.isEmpty ? null : normalized;
    }

    if (request.tools.isEmpty && _shouldForceTextResponseModality(model)) {
      return const ['TEXT'];
    }
    return null;
  }

  bool _modelSupportsThinking(String model) {
    final normalized = model.toLowerCase();
    return _isGemini3Model(normalized) ||
        normalized.contains('2.5') ||
        normalized.contains('thinking') ||
        normalized.contains('2.0-flash-thinking');
  }

  bool _isGemini3Model(String model) {
    final normalized = model.toLowerCase();
    return normalized.contains('gemini-3') || normalized.contains('gemini3');
  }

  bool _shouldForceTextResponseModality(String model) {
    final normalized = model.toLowerCase();
    return normalized.contains('2.5') ||
        normalized.contains('thinking') ||
        normalized.contains('2.0-flash-thinking');
  }

  String? _normalizeResponseModality(String modality) {
    return switch (modality.trim().toLowerCase()) {
      'text' => 'TEXT',
      'image' => 'IMAGE',
      _ => null,
    };
  }

  int? _parseInteger(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}

Future<void> _defaultWait(Duration delay) => Future<void>.delayed(delay);

Map<String, Object?> _deepCopyJsonMap(Map<String, Object?> source) {
  final decoded = jsonDecode(jsonEncode(source));
  if (decoded is Map<String, dynamic>) {
    return decoded.cast<String, Object?>();
  }
  return <String, Object?>{};
}

String _buildCodeAssistSessionId(String requestId) {
  final normalized = requestId.trim();
  return normalized.isEmpty ? 'session-unknown' : 'session-$normalized';
}

String _buildCodeAssistPromptId(String sessionId, String requestId, {int? sequence}) {
  final normalized = requestId.trim();
  final seed = normalized.isEmpty ? '${DateTime.now().millisecondsSinceEpoch}' : normalized;
  if (sequence == null || sequence <= 1) {
    return '$sessionId########$seed';
  }
  return '$sessionId########${seed}_$sequence';
}

String _buildGeminiCliUserAgent(String model) {
  final resolvedModel = model.trim().isEmpty ? 'unknown' : model.trim();
  final operatingSystem = Platform.operatingSystem;
  return '$geminiCodeAssistUserAgentPrefix/$resolvedModel ($operatingSystem)';
}

String _buildContinuationPrompt(String accumulatedText) {
  final tail = accumulatedText.length <= _continuationTailLength
      ? accumulatedText
      : accumulatedText.substring(accumulatedText.length - _continuationTailLength);
  final prompt = StringBuffer(_continuationPrompt)
    ..write(' Continue exactly from the next token after the previous assistant text.')
    ..write(' Do not restart, repeat, translate, summarize, or paraphrase.')
    ..write('\nLast text suffix:\n')
    ..write(tail);
  return prompt.toString();
}

bool _looksLikeDirectContinuation(String nextText) {
  final trimmed = nextText.trimLeft();
  if (trimmed.isEmpty) {
    return false;
  }

  final first = trimmed[0];
  if (first == '*' || first == '•' || first == '-' || first == '—') {
    return false;
  }

  if (_isLowercaseLetter(first)) {
    return true;
  }

  return ',.;:!?)]}"\''.contains(first);
}

bool _isLowercaseLetter(String value) {
  if (value.isEmpty) {
    return false;
  }
  final lower = value.toLowerCase();
  final upper = value.toUpperCase();
  return value == lower && lower != upper;
}

bool _isLetterOrDigit(String value) {
  if (value.isEmpty) {
    return false;
  }
  final lower = value.toLowerCase();
  final upper = value.toUpperCase();
  return lower != upper || RegExp(r'^\d$').hasMatch(value);
}

String _trailingWord(String value) {
  if (value.isEmpty) {
    return '';
  }

  var end = value.length - 1;
  while (end >= 0 && !_isLetterOrDigit(value[end])) {
    end -= 1;
  }
  if (end < 0) {
    return '';
  }

  var start = end;
  while (start >= 0 && _isLetterOrDigit(value[start])) {
    start -= 1;
  }
  return value.substring(start + 1, end + 1);
}

Map<String, Object?> _tryDecodeJsonMap(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded.cast<String, Object?>();
    }
  } catch (_) {}
  return const <String, Object?>{};
}

Map<String, Object?>? _typedDetail(List<Map<String, Object?>> details, String type) {
  for (final detail in details) {
    if (detail['@type'] == type) {
      return detail;
    }
  }
  return null;
}

Duration? _retryAfterFromRetryInfo(Map<String, Object?>? retryInfo) {
  return _parseProtoDuration(retryInfo?['retryDelay'] as String?);
}

Duration? _retryAfterFromMessage(String message) {
  for (final match in RegExp(
    r'(?:retry|reset)(?:\s+\w+){0,3}\s+(?:after|in)\s+([^.;,\n]+)',
    caseSensitive: false,
  ).allMatches(message)) {
    final duration = _parseFlexibleDuration(match.group(1));
    if (duration != null) {
      return duration;
    }
  }

  if (!RegExp(r'(retry|reset)', caseSensitive: false).hasMatch(message)) {
    return null;
  }

  return _parseFlexibleDuration(message);
}

Duration? _parseProtoDuration(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }

  if (raw.endsWith('ms')) {
    final milliseconds = double.tryParse(raw.substring(0, raw.length - 2));
    if (milliseconds == null) {
      return null;
    }
    return Duration(milliseconds: milliseconds.round());
  }

  if (raw.endsWith('s')) {
    final seconds = double.tryParse(raw.substring(0, raw.length - 1));
    if (seconds == null) {
      return null;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  return null;
}

Duration? _parseFlexibleDuration(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }

  final normalized = raw.toLowerCase();
  final matches = RegExp(
    r'([0-9]+(?:\.[0-9]+)?)\s*(ms|milliseconds?|s|sec(?:onds?)?|m|mins?|minutes?|h|hr|hrs|hours?|d|days?)\b',
    caseSensitive: false,
  ).allMatches(normalized);

  var totalMilliseconds = 0.0;
  var found = false;
  for (final match in matches) {
    final value = double.tryParse(match.group(1) ?? '');
    final unit = match.group(2)?.toLowerCase();
    if (value == null || unit == null) {
      continue;
    }

    found = true;
    totalMilliseconds += switch (unit) {
      'ms' || 'millisecond' || 'milliseconds' => value,
      's' || 'sec' || 'second' || 'seconds' => value * 1000,
      'm' || 'min' || 'mins' || 'minute' || 'minutes' => value * 60 * 1000,
      'h' || 'hr' || 'hrs' || 'hour' || 'hours' => value * 60 * 60 * 1000,
      'd' || 'day' || 'days' => value * 24 * 60 * 60 * 1000,
      _ => 0,
    };
  }

  if (!found) {
    return _parseProtoDuration(raw.trim());
  }

  return Duration(milliseconds: totalMilliseconds.round());
}

bool _quotaFailureMatches(Map<String, Object?>? quotaFailure, String pattern) {
  final violations = (quotaFailure?['violations'] as List?) ?? const [];
  return violations.whereType<Map>().any((violation) {
    final quotaId = ((violation['quotaId'] as String?) ?? '').toLowerCase();
    return quotaId.contains(pattern);
  });
}

String? _sanitizeDomain(String? domain) {
  if (domain == null || domain.isEmpty) {
    return null;
  }
  return domain.replaceAll(RegExp(r'[^a-zA-Z0-9.\-]'), '');
}

bool _looksLikeReasoningConfigError(String message) {
  return message.contains('thinking_budget') ||
      message.contains('thinking level') ||
      message.contains('thinking_level') ||
      message.contains('reasoning effort');
}

bool _looksLikeMissingProjectIdError(String message) {
  return message.contains('could not discover a valid google cloud project id') ||
      message.contains('configure project_id explicitly') ||
      message.contains('configure project id explicitly') ||
      message.contains('no gemini oauth credentials were loaded') ||
      message.contains('project id is invalid');
}

bool _looksLikeProjectConfigurationError(
  int statusCode,
  String message,
  String? errorReason,
  Map<String, Object?> metadata,
) {
  if (_looksLikeMissingProjectIdError(message)) {
    return true;
  }

  final quotaLimit = (metadata['quota_limit'] as String?)?.toLowerCase() ?? '';
  if (quotaLimit.isNotEmpty) {
    return false;
  }

  final service = (metadata['service'] as String?)?.toLowerCase() ?? '';
  final consumer = (metadata['consumer'] as String?)?.toLowerCase() ?? '';
  final hasProjectHint =
      message.contains('project id') ||
      message.contains('project_id') ||
      message.contains('consumer') ||
      message.contains('api has not been used') ||
      message.contains('service disabled') ||
      message.contains('access not configured') ||
      message.contains('permission denied') ||
      message.contains('forbidden');

  if (statusCode == 400 && hasProjectHint) {
    return true;
  }

  if (statusCode != 403) {
    return false;
  }

  return errorReason == 'CONSUMER_INVALID' ||
      errorReason == 'SERVICE_DISABLED' ||
      errorReason == 'ACCESS_TOKEN_SCOPE_INSUFFICIENT' ||
      errorReason == 'IAM_PERMISSION_DENIED' ||
      hasProjectHint ||
      service.contains('cloudcode') ||
      consumer.contains('projects/');
}

String? _accountVerificationUrl(Map<String, Object?> metadata, Map<String, Object?>? help) {
  final validationUrl = metadata['validation_url'] as String?;
  if (validationUrl != null && validationUrl.trim().isNotEmpty) {
    return validationUrl.trim();
  }

  final links = (help?['links'] as List?) ?? const [];
  for (final link in links.whereType<Map>()) {
    final url = (link['url'] as String?)?.trim();
    if (url != null && url.isNotEmpty) {
      return url;
    }
  }

  return null;
}
