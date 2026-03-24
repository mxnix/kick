import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../core/logging/log_sanitizer.dart';
import '../../data/models/oauth_tokens.dart';
import '../account_pool/account_pool.dart';
import '../model_catalog.dart';
import '../openai/openai_request_parser.dart';
import 'gemini_auth_constants.dart';
import 'gemini_client_fingerprint.dart';
import 'gemini_installation_identity.dart';

enum GeminiGatewayFailureKind {
  auth,
  quota,
  capacity,
  serviceUnavailable,
  unsupportedModel,
  invalidRequest,
  unknown,
}

enum GeminiGatewayFailureDetail {
  accountVerificationRequired,
  projectIdMissing,
  projectConfiguration,
  quotaExhausted,
  rateLimited,
  reasoningConfigUnsupported,
  noHealthyAccountAvailable,
}

enum GeminiGatewayFailureSource { upstream, transport, accountPool, proxy }

Object? _sanitizeGatewayResponseBody(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  try {
    return LogSanitizer.sanitizeJsonValue(jsonDecode(trimmed));
  } catch (_) {
    final sanitized = LogSanitizer.sanitizeText(trimmed);
    return sanitized.isEmpty ? null : sanitized;
  }
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
    this.upstreamReason,
    this.source = GeminiGatewayFailureSource.upstream,
    this.sanitizedResponseBody,
    this.rawResponseBody,
  });

  final GeminiGatewayFailureKind kind;
  final String message;
  final int statusCode;
  final String? quotaSnapshot;
  final Duration? retryAfter;
  final GeminiGatewayFailureDetail? detail;
  final String? actionUrl;
  final String? upstreamReason;
  final GeminiGatewayFailureSource source;
  final Object? sanitizedResponseBody;
  final String? rawResponseBody;

  @override
  String toString() => 'GeminiGatewayException($statusCode, $kind, $message)';
}

class GeminiRetryPolicy {
  const GeminiRetryPolicy({
    this.maxRetries = 10,
    this.baseDelay = const Duration(seconds: 1),
    this.default429Delay = const Duration(seconds: 30),
  });

  final int maxRetries;
  final Duration baseDelay;
  final Duration default429Delay;

  GeminiRetryPolicy normalized() {
    final normalizedMaxRetries = switch (maxRetries) {
      < 0 => 0,
      > 20 => 20,
      _ => maxRetries,
    };
    final normalized429Delay = switch (default429Delay.inSeconds) {
      <= 0 => const Duration(seconds: 30),
      > 3600 => const Duration(hours: 1),
      _ => Duration(seconds: default429Delay.inSeconds),
    };
    return GeminiRetryPolicy(
      maxRetries: normalizedMaxRetries,
      baseDelay: baseDelay > Duration.zero ? baseDelay : const Duration(seconds: 1),
      default429Delay: normalized429Delay,
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

class _GeminiRequestCanceledException implements Exception {
  const _GeminiRequestCanceledException();
}

class _RequestCancellation {
  final Completer<void> _abortCompleter = Completer<void>();

  Future<void> get trigger => _abortCompleter.future;
  bool get isCanceled => _abortCompleter.isCompleted;

  void cancel() {
    if (!_abortCompleter.isCompleted) {
      _abortCompleter.complete();
    }
  }

  void throwIfCanceled() {
    if (isCanceled) {
      throw const _GeminiRequestCanceledException();
    }
  }
}

const _cloudCodeDomains = <String>{
  'cloudcode-pa.googleapis.com',
  'staging-cloudcode-pa.googleapis.com',
  'autopush-cloudcode-pa.googleapis.com',
};
const defaultGeminiRequestMaxRetries = 10;
const defaultGeminiBaseRetryDelay = Duration(seconds: 1);
const defaultGeminiRequestTimeout = Duration(seconds: 90);
const _maxTransientRequestRetries = 3;
const _maxRetryable429Delay = Duration(minutes: 1);
const _maxRetryableTransientDelay = Duration(minutes: 5);
const _gemini3DefaultTopK = 64;
const _gemini3ShortTextMaxOutputTokens = 256;
const defaultGeminiMaxOutputTokens = 8192;
const _continuationPrompt = 'Please continue from where you left off.';
const _continuationTailLength = 180;
const _maxContinuationPasses = 12;
const _minimumContinuationOverlap = 6;
const _fallbackOnboardTierId = 'legacy-tier';
const _projectDiscoveryPollDelay = Duration(seconds: 2);
const _projectDiscoveryMaxPollAttempts = 15;
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
  final sanitizedResponseBody = _sanitizeGatewayResponseBody(body);
  final rawResponseBody = body.trim().isEmpty ? null : body;
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
  final actionUrl = _gatewayActionUrl(errorMetadata, help);
  final isProjectIdMissing = _looksLikeMissingProjectIdError(lower);

  if (statusCode == 404 ||
      lower.contains('unsupported model') ||
      lower.contains('not found model') ||
      lower.contains('model not found')) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.unsupportedModel,
      message: message,
      statusCode: statusCode,
      sanitizedResponseBody: sanitizedResponseBody,
      rawResponseBody: rawResponseBody,
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
      upstreamReason: errorReason,
      detail: isAccountVerificationRequired
          ? GeminiGatewayFailureDetail.accountVerificationRequired
          : isProjectIdMissing
          ? GeminiGatewayFailureDetail.projectIdMissing
          : isAuthProjectConfigurationError
          ? GeminiGatewayFailureDetail.projectConfiguration
          : null,
      retryAfter: isAccountVerificationRequired ? const Duration(minutes: 5) : null,
      actionUrl: actionUrl,
      sanitizedResponseBody: sanitizedResponseBody,
      rawResponseBody: rawResponseBody,
    );
  }

  if (isProjectConfigurationError) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.invalidRequest,
      message: message,
      statusCode: statusCode == 0 ? 400 : statusCode,
      upstreamReason: errorReason,
      detail: isProjectIdMissing
          ? GeminiGatewayFailureDetail.projectIdMissing
          : GeminiGatewayFailureDetail.projectConfiguration,
      actionUrl: actionUrl,
      sanitizedResponseBody: sanitizedResponseBody,
      rawResponseBody: rawResponseBody,
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
      retryAfter: retryAfter,
      sanitizedResponseBody: sanitizedResponseBody,
      rawResponseBody: rawResponseBody,
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
      upstreamReason: errorReason,
      detail: isQuotaExhausted
          ? GeminiGatewayFailureDetail.quotaExhausted
          : GeminiGatewayFailureDetail.rateLimited,
      retryAfter: retryAfter,
      sanitizedResponseBody: sanitizedResponseBody,
      rawResponseBody: rawResponseBody,
    );
  }

  if (hasCapacityPressure || lower.contains('capacity')) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.capacity,
      message: message,
      statusCode: statusCode == 0 ? 503 : statusCode,
      retryAfter: retryAfter,
      sanitizedResponseBody: sanitizedResponseBody,
      rawResponseBody: rawResponseBody,
    );
  }

  if (statusCode == 503 || statusCode >= 500 || lower.contains('unavailable')) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.serviceUnavailable,
      message: message,
      statusCode: statusCode == 0 ? 503 : statusCode,
      retryAfter: retryAfter,
      sanitizedResponseBody: sanitizedResponseBody,
      rawResponseBody: rawResponseBody,
    );
  }

  if (statusCode == 400) {
    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.invalidRequest,
      message: message,
      statusCode: statusCode,
      upstreamReason: errorReason,
      detail: _looksLikeReasoningConfigError(lower)
          ? GeminiGatewayFailureDetail.reasoningConfigUnsupported
          : _looksLikeProjectConfigurationError(statusCode, lower, errorReason, errorMetadata)
          ? GeminiGatewayFailureDetail.projectConfiguration
          : null,
      actionUrl: _looksLikeProjectConfigurationError(statusCode, lower, errorReason, errorMetadata)
          ? actionUrl
          : null,
      sanitizedResponseBody: sanitizedResponseBody,
      rawResponseBody: rawResponseBody,
    );
  }

  return GeminiGatewayException(
    kind: GeminiGatewayFailureKind.unknown,
    message: message,
    statusCode: statusCode,
    retryAfter: retryAfter,
    upstreamReason: errorReason,
    sanitizedResponseBody: sanitizedResponseBody,
    rawResponseBody: rawResponseBody,
  );
}

class GeminiCodeAssistClient {
  GeminiCodeAssistClient({
    required Future<void> Function(ProxyRuntimeAccount account, OAuthTokens tokens) onTokensUpdated,
    Future<void> Function(ProxyRuntimeAccount account, String projectId)? onProjectIdResolved,
    http.Client? httpClient,
    Future<void> Function(Duration delay)? wait,
    String Function()? createSessionId,
    GeminiInstallationIdLoader? privilegedUserIdLoader,
    bool warmupEnabled = false,
    GeminiRetryPolicy retryPolicy = const GeminiRetryPolicy(),
    Duration requestTimeout = defaultGeminiRequestTimeout,
  }) : _onTokensUpdated = onTokensUpdated,
       _onProjectIdResolved = onProjectIdResolved ?? _noopProjectIdResolved,
       _http = httpClient ?? http.Client(),
       _wait = wait ?? _defaultWait,
       _createSessionId = createSessionId ?? const Uuid().v4,
       _privilegedUserIdLoader = privilegedUserIdLoader ?? GeminiInstallationIdLoader(),
       _warmupEnabled = warmupEnabled,
       _retryPolicy = retryPolicy.normalized(),
       _requestTimeout = requestTimeout > Duration.zero
           ? requestTimeout
           : defaultGeminiRequestTimeout;

  final Future<void> Function(ProxyRuntimeAccount account, OAuthTokens tokens) _onTokensUpdated;
  final Future<void> Function(ProxyRuntimeAccount account, String projectId) _onProjectIdResolved;
  final http.Client _http;
  final Future<void> Function(Duration delay) _wait;
  final String Function() _createSessionId;
  final GeminiInstallationIdLoader _privilegedUserIdLoader;
  final bool _warmupEnabled;
  GeminiRetryPolicy _retryPolicy;
  final Duration _requestTimeout;
  final Set<String> _warmupAttemptedKeys = <String>{};

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
    final resolvedProjectId = await _ensureResolvedProjectId(
      account,
      headerModel: resolvedModel,
      onRetry: onRetry,
    );
    _scheduleWarmupIfNeeded(account: account, headerModel: resolvedModel);
    final baseRequestBody = _buildRequestBody(request, resolvedModel: resolvedModel);
    final sessionState = _createSessionState(baseRequestBody);
    return _generateWithContinuation(
      account: account,
      model: resolvedModel,
      projectId: resolvedProjectId,
      baseRequestBody: baseRequestBody,
      sessionState: sessionState,
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
    final resolvedProjectId = await _ensureResolvedProjectId(
      account,
      headerModel: resolvedModel,
      onRetry: onRetry,
    );
    _scheduleWarmupIfNeeded(account: account, headerModel: resolvedModel);
    final baseRequestBody = _buildRequestBody(request, resolvedModel: resolvedModel);
    final sessionState = _createSessionState(baseRequestBody);
    StreamIterator<Map<String, Object?>>? payloadIterator;
    var canceled = false;
    final cancellation = _RequestCancellation();
    final controller = StreamController<Map<String, Object?>>(
      onCancel: () async {
        canceled = true;
        cancellation.cancel();
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
                projectId: resolvedProjectId,
                requestBody: currentRequestBody,
                sessionState: sessionState,
                cancellation: cancellation,
              ),
              onRetry: onRetry,
              cancellation: cancellation,
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
          if (!canceled && error is! _GeminiRequestCanceledException) {
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
    required Map<String, Object?> baseRequestBody,
    required _CodeAssistSessionState sessionState,
    void Function(GeminiRetryEvent event)? onRetry,
  }) async {
    var currentRequestBody = baseRequestBody;
    var accumulatedText = '';
    late Map<String, Object?> lastPayload;

    for (var pass = 0; pass <= _maxContinuationPasses; pass++) {
      final accumulatedBeforePass = accumulatedText;
      await _ensureFreshTokens(account);
      lastPayload = await _executeWithRetry(
        () => _sendUnaryRequest(
          accessToken: account.tokens.accessToken,
          model: model,
          projectId: projectId,
          requestBody: currentRequestBody,
          sessionState: sessionState,
          timeoutLabel: 'Gemini request',
        ),
        onRetry: onRetry,
      );

      final generatedText = _extractGeneratedText(lastPayload);
      if (generatedText.isNotEmpty) {
        accumulatedText = pass == 0
            ? generatedText
            : _appendContinuationText(accumulatedBeforePass, generatedText);
      }

      final shouldContinue =
          _extractFinishReason(lastPayload) == 'MAX_TOKENS' &&
          accumulatedText.isNotEmpty &&
          accumulatedText != accumulatedBeforePass &&
          pass < _maxContinuationPasses;
      if (!shouldContinue) {
        return accumulatedText.isEmpty
            ? lastPayload
            : _withAccumulatedText(lastPayload, accumulatedText);
      }

      currentRequestBody = _buildContinuationRequestBody(
        baseRequestBody: baseRequestBody,
        accumulatedText: accumulatedText,
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
    final sessionId = _createSessionId();
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
          case UnifiedPartType.thought:
            final thoughtText = (part.text ?? '').trim();
            final thoughtSignature = part.thoughtSignature?.trim();
            if (thoughtText.isNotEmpty || thoughtSignature?.isNotEmpty == true) {
              parts.add({
                'thought': true,
                if (thoughtText.isNotEmpty) 'text': thoughtText,
                if (thoughtSignature != null && thoughtSignature.isNotEmpty)
                  'thoughtSignature': thoughtSignature,
              });
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

    final tools = <Map<String, Object?>>[];
    if (request.tools.isNotEmpty) {
      tools.add({
        'functionDeclarations': [
          for (final tool in request.tools)
            {'name': tool.name, 'description': tool.description, 'parameters': tool.parameters},
        ],
      });
    }
    if (request.googleWebSearchEnabled) {
      tools.add({'googleSearch': const <String, Object?>{}});
    }

    return {
      'contents': contents,
      if (request.systemInstruction != null)
        'systemInstruction': {
          'role': 'user',
          'parts': [
            {'text': request.systemInstruction},
          ],
        },
      if (tools.isNotEmpty) 'tools': tools,
      if (request.tools.isNotEmpty) ...{'toolConfig': _buildToolConfig(request.toolChoice)},
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

  void _scheduleWarmupIfNeeded({
    required ProxyRuntimeAccount account,
    required String headerModel,
  }) {
    if (!_warmupEnabled) {
      return;
    }
    final key = _warmupKey(account);
    if (!_warmupAttemptedKeys.add(key)) {
      return;
    }
    final warmupRequests = <Future<void>>[
      _postWarmupRequest(
        method: 'loadCodeAssist',
        accessToken: account.tokens.accessToken,
        headerModel: headerModel,
        body: {
          'metadata': {
            'ideType': geminiCodeAssistIdeType,
            'platform': geminiCodeAssistPlatformUnspecified,
            'pluginType': geminiCodeAssistPluginType,
          },
        },
      ),
      _postWarmupRequest(
        method: 'listExperiments',
        accessToken: account.tokens.accessToken,
        headerModel: headerModel,
        body: {
          'project': account.projectId,
          'metadata': buildCodeAssistClientMetadata(account.projectId),
        },
      ),
    ];
    unawaited(
      Future.wait(
        warmupRequests.map(
          (warmup) => warmup.catchError((_) {
            return;
          }),
        ),
      ),
    );
  }

  Uri _methodUri(String method) {
    return Uri.parse('$geminiCodeAssistEndpoint/$geminiCodeAssistApiVersion:$method');
  }

  Future<Map<String, String>> _headers(String accessToken, {required String model}) async {
    return buildGeminiCodeAssistHeaders(
      accessToken: accessToken,
      model: model,
      privilegedUserId: await _privilegedUserIdLoader.load(),
    );
  }

  Future<void> _postWarmupRequest({
    required String method,
    required String accessToken,
    required String headerModel,
    required Map<String, Object?> body,
  }) async {
    final response = await _runWithRequestTimeout(
      () async => _http.post(
        _methodUri(method),
        headers: await _headers(accessToken, model: headerModel),
        body: jsonEncode(body),
      ),
      'Gemini warmup request',
    );
    if (response.statusCode >= 400) {
      throw decodeGeminiGatewayError(response.statusCode, response.body);
    }
  }

  Future<Map<String, Object?>> _sendUnaryRequest({
    required String accessToken,
    required String model,
    required String projectId,
    required Map<String, Object?> requestBody,
    required _CodeAssistSessionState sessionState,
    String timeoutLabel = 'Gemini request',
  }) async {
    final request = http.Request('POST', _methodUri('generateContent'))
      ..headers.addAll(await _headers(accessToken, model: model))
      ..body = jsonEncode(
        _buildRequestEnvelope(
          model: model,
          projectId: projectId,
          requestBody: requestBody,
          sessionState: sessionState,
        ),
      );
    final response = await _runWithRequestTimeout(() => _http.send(request), timeoutLabel);
    final body = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      throw decodeGeminiGatewayError(response.statusCode, body);
    }
    final decoded = _tryDecodeJsonMap(body);
    if (decoded.isNotEmpty) {
      return decoded;
    }
    throw GeminiGatewayException(
      kind: GeminiGatewayFailureKind.unknown,
      message: 'Unexpected Gemini response shape.',
      statusCode: 502,
      source: GeminiGatewayFailureSource.transport,
      sanitizedResponseBody: _sanitizeGatewayResponseBody(body),
      rawResponseBody: body.trim().isEmpty ? null : body,
    );
  }

  Future<http.StreamedResponse> _sendStreamRequest({
    required String accessToken,
    required String model,
    required String projectId,
    required Map<String, Object?> requestBody,
    required _CodeAssistSessionState sessionState,
    _RequestCancellation? cancellation,
    String timeoutLabel = 'Gemini streaming request',
  }) async {
    final headers = await _headers(accessToken, model: model);
    final httpRequest =
        http.AbortableRequest(
            'POST',
            _methodUri('streamGenerateContent').replace(queryParameters: {'alt': 'sse'}),
            abortTrigger: cancellation?.trigger,
          )
          ..headers.addAll(<String, String>{...headers, HttpHeaders.acceptHeader: '*/*'})
          ..body = jsonEncode(
            _buildRequestEnvelope(
              model: model,
              projectId: projectId,
              requestBody: requestBody,
              sessionState: sessionState,
            ),
          );
    final response = await _runWithRequestTimeout(() => _http.send(httpRequest), timeoutLabel);
    if (response.statusCode >= 400) {
      final body = await response.stream.bytesToString();
      throw decodeGeminiGatewayError(response.statusCode, body);
    }
    return response;
  }

  Future<String> _ensureResolvedProjectId(
    ProxyRuntimeAccount account, {
    required String headerModel,
    void Function(GeminiRetryEvent event)? onRetry,
  }) async {
    final currentProjectId = account.projectId.trim();
    if (currentProjectId.isNotEmpty) {
      return currentProjectId;
    }

    final resolvedProjectId = await _executeWithRetry(
      () => _discoverProjectId(accessToken: account.tokens.accessToken, headerModel: headerModel),
      onRetry: onRetry,
    );
    if (resolvedProjectId.isEmpty) {
      throw GeminiGatewayException(
        kind: GeminiGatewayFailureKind.invalidRequest,
        message: 'Could not discover a valid Google Cloud project ID for this account.',
        statusCode: 400,
        detail: GeminiGatewayFailureDetail.projectIdMissing,
      );
    }

    account.projectId = resolvedProjectId;
    await _onProjectIdResolved(account, resolvedProjectId);
    return resolvedProjectId;
  }

  Future<String> _discoverProjectId({
    required String accessToken,
    required String headerModel,
  }) async {
    final setup = await _loadCodeAssistSetup(accessToken: accessToken, headerModel: headerModel);
    if (setup.projectId.isNotEmpty) {
      return setup.projectId;
    }

    final onboardRequest = <String, Object?>{
      'tierId': setup.tierId,
      'metadata': _buildSetupMetadata(),
    };
    for (var attempt = 0; attempt < _projectDiscoveryMaxPollAttempts; attempt++) {
      final response = await _callJsonMethod(
        method: 'onboardUser',
        accessToken: accessToken,
        headerModel: headerModel,
        body: onboardRequest,
        timeoutLabel: 'Gemini project discovery',
      );
      if (response['done'] == true) {
        final payload =
            (response['response'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
        return _extractProjectId(payload['cloudaicompanionProject']);
      }
      if (attempt + 1 < _projectDiscoveryMaxPollAttempts) {
        await _wait(_projectDiscoveryPollDelay);
      }
    }

    return '';
  }

  Future<_LoadCodeAssistSetup> _loadCodeAssistSetup({
    required String accessToken,
    required String headerModel,
  }) async {
    final response = await _callJsonMethod(
      method: 'loadCodeAssist',
      accessToken: accessToken,
      headerModel: headerModel,
      body: {'metadata': _buildSetupMetadata()},
      timeoutLabel: 'Gemini project discovery',
    );
    return _LoadCodeAssistSetup(
      projectId: _extractProjectId(response['cloudaicompanionProject']),
      tierId: _extractDefaultTierId(response['allowedTiers']),
    );
  }

  Future<Map<String, Object?>> _callJsonMethod({
    required String method,
    required String accessToken,
    required String headerModel,
    required Map<String, Object?> body,
    required String timeoutLabel,
  }) async {
    final request = http.Request('POST', _methodUri(method))
      ..headers.addAll(await _headers(accessToken, model: headerModel))
      ..body = jsonEncode(body);
    final response = await _runWithRequestTimeout(() => _http.send(request), timeoutLabel);
    final rawBody = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      throw decodeGeminiGatewayError(response.statusCode, rawBody);
    }
    final decoded = _tryDecodeJsonMap(rawBody);
    if (decoded.isNotEmpty || rawBody.trim().isEmpty) {
      return decoded;
    }
    throw GeminiGatewayException(
      kind: GeminiGatewayFailureKind.unknown,
      message: 'Unexpected Gemini response shape.',
      statusCode: 502,
      source: GeminiGatewayFailureSource.transport,
      sanitizedResponseBody: _sanitizeGatewayResponseBody(rawBody),
      rawResponseBody: rawBody,
    );
  }

  Map<String, String> _buildSetupMetadata() {
    return const <String, String>{
      'ideType': geminiCodeAssistIdeType,
      'platform': geminiCodeAssistPlatformUnspecified,
      'pluginType': geminiCodeAssistPluginType,
    };
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
            final trimmedLine = line.trim();
            if (line.startsWith('data: ')) {
              buffer.add(line.substring(6).trim());
              continue;
            }
            if (line.isEmpty && buffer.isNotEmpty) {
              _emitBufferedChunk(controller, buffer);
              buffer.clear();
            }
            if (buffer.isEmpty && (trimmedLine.startsWith('{') || trimmedLine.startsWith('['))) {
              // Some tests and intermediary adapters return a bare JSON payload instead of SSE.
              buffer.add(trimmedLine);
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
    _RequestCancellation? cancellation,
  }) async {
    GeminiGatewayException? lastError;
    for (var attempt = 0; attempt <= _retryPolicy.maxRetries; attempt++) {
      try {
        cancellation?.throwIfCanceled();
        return await operation();
      } catch (error) {
        if (error is _GeminiRequestCanceledException || error is http.RequestAbortedException) {
          throw const _GeminiRequestCanceledException();
        }
        cancellation?.throwIfCanceled();
        final gatewayError = _decodeTransportError(error);
        lastError = gatewayError;
        if (!_shouldRetryRequest(gatewayError, attempt)) {
          throw gatewayError;
        }
        final delay = _retryDelayFor(gatewayError, attempt);
        cancellation?.throwIfCanceled();
        onRetry?.call(
          GeminiRetryEvent(
            attempt: attempt + 1,
            maxRetries: _retryLimitFor(gatewayError),
            delay: delay,
            error: gatewayError,
          ),
        );
        await _waitForRetryDelay(delay, cancellation: cancellation);
      }
    }

    throw lastError ??
        GeminiGatewayException(
          kind: GeminiGatewayFailureKind.unknown,
          message: 'Gemini request failed after retries.',
          statusCode: 500,
        );
  }

  Future<void> _waitForRetryDelay(Duration delay, {_RequestCancellation? cancellation}) async {
    if (cancellation == null) {
      await _wait(delay);
      return;
    }

    await Future.any<void>(<Future<void>>[_wait(delay), cancellation.trigger]);
    cancellation.throwIfCanceled();
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
      case GeminiGatewayFailureKind.serviceUnavailable:
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
    if (error.statusCode == 429) {
      return _retryPolicy.default429Delay;
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
      case GeminiGatewayFailureKind.serviceUnavailable:
        return min(_retryPolicy.maxRetries, _maxTransientRequestRetries);
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
        kind: GeminiGatewayFailureKind.serviceUnavailable,
        message: message,
        statusCode: 503,
        source: GeminiGatewayFailureSource.transport,
      );
    }

    if (error is SocketException) {
      return GeminiGatewayException(
        kind: GeminiGatewayFailureKind.serviceUnavailable,
        message: 'Network error while contacting Gemini Code Assist: ${error.message}',
        statusCode: 503,
        source: GeminiGatewayFailureSource.transport,
      );
    }

    if (error is http.ClientException) {
      return GeminiGatewayException(
        kind: GeminiGatewayFailureKind.serviceUnavailable,
        message: 'HTTP client error while contacting Gemini Code Assist: ${error.message}',
        statusCode: 503,
        source: GeminiGatewayFailureSource.transport,
      );
    }

    if (error is HttpException) {
      return GeminiGatewayException(
        kind: GeminiGatewayFailureKind.serviceUnavailable,
        message: 'HTTP error while contacting Gemini Code Assist: ${error.message}',
        statusCode: 503,
        source: GeminiGatewayFailureSource.transport,
      );
    }

    return GeminiGatewayException(
      kind: GeminiGatewayFailureKind.unknown,
      message: error.toString(),
      statusCode: 500,
      source: GeminiGatewayFailureSource.proxy,
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
    required Map<String, Object?> requestBody,
    required _CodeAssistSessionState sessionState,
  }) {
    final existingSessionId = (requestBody['session_id'] as String?)?.trim();
    final sessionId = existingSessionId?.isNotEmpty == true
        ? existingSessionId!
        : sessionState.sessionId;
    final normalizedRequest = _deepCopyJsonMap(requestBody)..['session_id'] = sessionId;

    return {
      'model': model,
      'project': projectId,
      'user_prompt_id': _buildCodeAssistPromptId(
        sessionId,
        turnIndex: sessionState.nextTurnIndex(),
      ),
      'request': normalizedRequest,
    };
  }

  _CodeAssistSessionState _createSessionState(Map<String, Object?> requestBody) {
    final existingSessionId = (requestBody['session_id'] as String?)?.trim();
    final sessionId = existingSessionId?.isNotEmpty == true
        ? existingSessionId!
        : _createSessionId();
    requestBody['session_id'] = sessionId;
    return _CodeAssistSessionState(sessionId);
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
        return _buildGemini3ThinkingConfigFromReasoningEffort(model, reasoningEffort);
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
    if (googleThinkingConfig != null) {
      if (!_modelSupportsThinking(model)) {
        return null;
      }

      if (_isGemini3Model(model)) {
        return _normalizeGemini3ThinkingConfig(googleThinkingConfig);
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

    if (_shouldDisableThinkingByDefault(request, model)) {
      return const {'thinkingBudget': 0, 'includeThoughts': false};
    }

    if (_shouldConstrainGemini3ThinkingByDefault(request, model)) {
      return {'thinkingLevel': _defaultGemini3ThinkingLevel(model)};
    }

    return null;
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

  bool _shouldDisableThinkingByDefault(UnifiedPromptRequest request, String model) {
    return _isGemini25FlashModel(model) &&
        request.tools.isEmpty &&
        request.responseModalities == null &&
        _isTextOnlyRequest(request);
  }

  bool _shouldConstrainGemini3ThinkingByDefault(UnifiedPromptRequest request, String model) {
    final maxOutputTokens = request.maxOutputTokens;
    return _isGemini3Model(model) &&
        request.tools.isEmpty &&
        request.responseModalities == null &&
        maxOutputTokens != null &&
        maxOutputTokens <= _gemini3ShortTextMaxOutputTokens &&
        _isTextOnlyRequest(request);
  }

  bool _isTextOnlyRequest(UnifiedPromptRequest request) {
    for (final turn in request.turns) {
      for (final part in turn.parts) {
        if (part.type != UnifiedPartType.text) {
          return false;
        }
      }
    }
    return true;
  }

  bool _isGemini3Model(String model) {
    final normalized = model.toLowerCase();
    return normalized.contains('gemini-3') || normalized.contains('gemini3');
  }

  bool _isGemini3FlashModel(String model) {
    final normalized = model.toLowerCase();
    return _isGemini3Model(normalized) && normalized.contains('flash');
  }

  String _defaultGemini3ThinkingLevel(String model) {
    return _isGemini3FlashModel(model) ? 'MINIMAL' : 'LOW';
  }

  Map<String, Object?>? _buildGemini3ThinkingConfigFromReasoningEffort(
    String model,
    String reasoningEffort,
  ) {
    final thinkingLevel = switch (reasoningEffort) {
      'auto' => null,
      'none' || 'minimal' => _isGemini3FlashModel(model) ? 'MINIMAL' : 'LOW',
      'low' => 'LOW',
      'medium' => _isGemini3FlashModel(model) ? 'MEDIUM' : 'LOW',
      'high' => 'HIGH',
      _ => null,
    };
    return thinkingLevel == null ? null : {'thinkingLevel': thinkingLevel};
  }

  Map<String, Object?>? _normalizeGemini3ThinkingConfig(Map<String, Object?> googleThinkingConfig) {
    final thinkingConfig = <String, Object?>{};
    final thinkingLevel =
        (googleThinkingConfig['thinkingLevel'] as String?)?.trim() ??
        (googleThinkingConfig['thinking_level'] as String?)?.trim();
    if (thinkingLevel != null && thinkingLevel.isNotEmpty) {
      thinkingConfig['thinkingLevel'] = thinkingLevel.toUpperCase();
    }

    final budget =
        _parseInteger(googleThinkingConfig['thinkingBudget']) ??
        _parseInteger(googleThinkingConfig['thinking_budget']);
    if (budget != null && !thinkingConfig.containsKey('thinkingLevel')) {
      thinkingConfig['thinkingBudget'] = budget;
    }

    if (googleThinkingConfig['includeThoughts'] is bool) {
      thinkingConfig['includeThoughts'] = googleThinkingConfig['includeThoughts'] as bool;
    } else if (googleThinkingConfig['include_thoughts'] is bool) {
      thinkingConfig['includeThoughts'] = googleThinkingConfig['include_thoughts'] as bool;
    }

    return thinkingConfig.isEmpty ? null : thinkingConfig;
  }

  bool _isGemini25Model(String model) {
    final normalized = model.toLowerCase();
    return normalized.contains('2.5');
  }

  bool _isGemini25FlashModel(String model) {
    final normalized = model.toLowerCase();
    return _isGemini25Model(normalized) && normalized.contains('flash');
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

Future<void> _noopProjectIdResolved(ProxyRuntimeAccount account, String projectId) async {}

Map<String, Object?> _deepCopyJsonMap(Map<String, Object?> source) {
  final decoded = jsonDecode(jsonEncode(source));
  if (decoded is Map<String, dynamic>) {
    return decoded.cast<String, Object?>();
  }
  return <String, Object?>{};
}

String _buildCodeAssistPromptId(String sessionId, {required int turnIndex}) {
  return '$sessionId########$turnIndex';
}

String _warmupKey(ProxyRuntimeAccount account) {
  final accountId = account.id.trim().isEmpty ? account.tokenRef : account.id;
  return '$accountId:${account.projectId}';
}

final class _LoadCodeAssistSetup {
  const _LoadCodeAssistSetup({required this.projectId, required this.tierId});

  final String projectId;
  final String tierId;
}

final class _CodeAssistSessionState {
  _CodeAssistSessionState(this.sessionId);

  final String sessionId;
  int _turnCounter = 0;

  int nextTurnIndex() => _turnCounter++;
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

String _extractProjectId(Object? value) {
  if (value is String) {
    return value.trim();
  }
  if (value is Map) {
    return (value['id'] as String? ?? '').trim();
  }
  return '';
}

String _extractDefaultTierId(Object? value) {
  if (value is! List) {
    return _fallbackOnboardTierId;
  }

  for (final rawTier in value) {
    if (rawTier is! Map) {
      continue;
    }
    if (rawTier['isDefault'] != true) {
      continue;
    }
    final tierId = (rawTier['id'] as String? ?? '').trim();
    if (tierId.isNotEmpty) {
      return tierId;
    }
  }

  return _fallbackOnboardTierId;
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

String? _gatewayActionUrl(Map<String, Object?> metadata, Map<String, Object?>? help) {
  for (final key in const ['validation_url', 'activationUrl', 'activation_url']) {
    final url = metadata[key] as String?;
    if (url != null && url.trim().isNotEmpty) {
      return url.trim();
    }
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
