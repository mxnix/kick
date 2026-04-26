import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../data/models/account_profile.dart';
import '../../data/models/oauth_tokens.dart';
import '../account_pool/account_pool.dart';
import '../gemini/gemini_code_assist_client.dart';
import '../model_catalog.dart';
import '../openai/openai_request_parser.dart';
import 'kiro_auth_source.dart';
import 'kiro_embedded_system_prompt.dart';

const defaultKiroRequestTimeout = Duration(seconds: 90);

class KiroCodeAssistClient {
  KiroCodeAssistClient({
    http.Client? httpClient,
    Future<void> Function(Duration delay)? wait,
    GeminiRetryPolicy retryPolicy = const GeminiRetryPolicy(),
    Duration requestTimeout = defaultKiroRequestTimeout,
  }) : _http = httpClient ?? http.Client(),
       _wait = wait ?? _defaultWait,
       _retryPolicy = retryPolicy.normalized(),
       _requestTimeout = requestTimeout > Duration.zero
           ? requestTimeout
           : defaultKiroRequestTimeout,
       _fingerprint = _buildMachineFingerprint();

  final http.Client _http;
  final Future<void> Function(Duration delay) _wait;
  GeminiRetryPolicy _retryPolicy;
  final Duration _requestTimeout;
  final String _fingerprint;
  final _uuid = const Uuid();

  void updateRetryPolicy(GeminiRetryPolicy retryPolicy) {
    _retryPolicy = retryPolicy.normalized();
  }

  Future<List<String>> listModels({required ProxyRuntimeAccount account}) async {
    await _ensureFreshTokens(account);
    final discoveredModels = <String>{};
    final seenTokens = <String>{};
    var nextToken = '';

    while (true) {
      final response = await _executeWithRetry(
        () => _sendRetryable(
          method: 'GET',
          uri: _listModelsUri(account, nextToken: nextToken),
          headers: _headers(accessToken: account.tokens.accessToken),
          timeoutLabel: 'Kiro model discovery',
        ),
      );
      final body = await response.stream.bytesToString();
      final decoded = _tryDecodeJsonMap(body);

      for (final item in ((decoded['models'] as List?) ?? const [])) {
        if (item is! Map) {
          continue;
        }
        final modelId = (item.cast<String, Object?>()['modelId'] as String? ?? '').trim();
        if (modelId.isEmpty) {
          continue;
        }
        discoveredModels.add(ModelCatalog.normalizeModel(modelId));
      }
      final defaultModel = (decoded['defaultModel'] as Map?)?.cast<String, Object?>();
      final defaultModelId = (defaultModel?['modelId'] as String? ?? '').trim();
      if (defaultModelId.isNotEmpty) {
        discoveredModels.add(ModelCatalog.normalizeModel(defaultModelId));
      }

      final pageToken = (decoded['nextToken'] as String? ?? '').trim();
      if (pageToken.isEmpty || !seenTokens.add(pageToken)) {
        if (discoveredModels.isNotEmpty ||
            decoded.containsKey('models') ||
            decoded.containsKey('defaultModel') ||
            decoded.containsKey('nextToken')) {
          break;
        }
        return const <String>[];
      }
      nextToken = pageToken;
    }

    final models = discoveredModels.toList()..sort();
    return models;
  }

  Future<Map<String, Object?>> generateContent({
    required ProxyRuntimeAccount account,
    required UnifiedPromptRequest request,
    void Function(GeminiRetryEvent event)? onRetry,
  }) async {
    final resolvedModel = ModelCatalog.normalizeModel(request.model);
    final stream = await generateContentStream(
      account: account,
      request: request,
      onRetry: onRetry,
    );

    Map<String, Object?>? lastPayload;
    await for (final payload in stream) {
      lastPayload = payload;
    }

    if (lastPayload != null) {
      return lastPayload;
    }

    return _KiroResponseAccumulator(
      model: resolvedModel,
      includeReasoning: _shouldExposeReasoning(request),
    ).toPayload(finalChunk: true);
  }

  Future<Stream<Map<String, Object?>>> generateContentStream({
    required ProxyRuntimeAccount account,
    required UnifiedPromptRequest request,
    void Function(GeminiRetryEvent event)? onRetry,
  }) async {
    await _ensureFreshTokens(account);
    final resolvedModel = ModelCatalog.normalizeModel(request.model);
    final requestBody = _buildRequestBody(account: account, request: request, model: resolvedModel);
    final accumulator = _KiroResponseAccumulator(
      model: resolvedModel,
      includeReasoning: _shouldExposeReasoning(request),
    );
    final controller = StreamController<Map<String, Object?>>();

    unawaited(
      Future<void>(() async {
        try {
          final response = await _executeWithRetry(
            () => _sendRetryable(
              method: 'POST',
              uri: _generateUri(account),
              headers: _headers(accessToken: account.tokens.accessToken),
              body: jsonEncode(requestBody),
              timeoutLabel: 'Kiro streaming request',
            ),
            onRetry: onRetry,
          );

          final parser = _KiroEventStreamParser();
          await for (final chunk in response.stream) {
            final events = parser.feed(chunk);
            for (final event in events) {
              accumulator.apply(event);
              controller.add(accumulator.toPayload());
            }
          }
          if (!accumulator.hasEmittableOutput) {
            throw GeminiGatewayException(
              provider: AccountProvider.kiro,
              kind: GeminiGatewayFailureKind.serviceUnavailable,
              message: 'Kiro streaming request completed without response data.',
              statusCode: 502,
              source: GeminiGatewayFailureSource.transport,
            );
          }
          controller.add(accumulator.toPayload(finalChunk: true));
        } catch (error) {
          controller.addError(_decodeTransportError(error));
        } finally {
          await controller.close();
        }
      }),
    );

    return controller.stream;
  }

  Future<void> _ensureFreshTokens(ProxyRuntimeAccount account) async {
    if (!account.tokens.isExpired) {
      return;
    }
    if (account.tokens.refreshToken.trim().isEmpty) {
      return;
    }

    final refreshed = await _refreshTokens(account);
    account.tokens = refreshed;
  }

  Future<OAuthTokens> _refreshTokens(ProxyRuntimeAccount account) async {
    final source = await loadKiroAuthSource(sourcePath: account.credentialSourcePath);
    if (source?.usesBuilderIdRefresh == true) {
      return _refreshBuilderIdTokens(account, source!);
    }
    return _refreshDesktopTokens(account, source: source);
  }

  Future<http.StreamedResponse> _send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required String timeoutLabel,
  }) async {
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) {
      request.body = body;
    }
    return _runWithTimeout(() => _http.send(request), timeoutLabel);
  }

  Future<T> _executeWithRetry<T>(
    Future<T> Function() operation, {
    void Function(GeminiRetryEvent event)? onRetry,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await operation();
      } on GeminiGatewayException catch (error) {
        if (!_shouldRetry(error) || attempt >= _retryPolicy.maxRetries) {
          rethrow;
        }

        final retryDelay =
            error.retryAfter ??
            Duration(milliseconds: _retryPolicy.baseDelay.inMilliseconds * (1 << attempt));
        attempt += 1;
        onRetry?.call(
          GeminiRetryEvent(
            attempt: attempt,
            maxRetries: _retryPolicy.maxRetries,
            delay: retryDelay,
            error: error,
          ),
        );
        await _wait(retryDelay);
      } catch (error) {
        final decoded = _decodeTransportError(error);
        if (!_shouldRetry(decoded) || attempt >= _retryPolicy.maxRetries) {
          throw decoded;
        }
        final retryDelay =
            decoded.retryAfter ??
            Duration(milliseconds: _retryPolicy.baseDelay.inMilliseconds * (1 << attempt));
        attempt += 1;
        onRetry?.call(
          GeminiRetryEvent(
            attempt: attempt,
            maxRetries: _retryPolicy.maxRetries,
            delay: retryDelay,
            error: decoded,
          ),
        );
        await _wait(retryDelay);
      }
    }
  }

  Future<http.StreamedResponse> _sendRetryable({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required String timeoutLabel,
  }) async {
    final response = await _send(
      method: method,
      uri: uri,
      headers: headers,
      body: body,
      timeoutLabel: timeoutLabel,
    );
    if (response.statusCode < 400) {
      return response;
    }

    final responseBody = await response.stream.bytesToString();
    throw decodeKiroGatewayError(response.statusCode, responseBody);
  }

  Future<T> _runWithTimeout<T>(Future<T> Function() operation, String timeoutLabel) {
    return operation().timeout(
      _requestTimeout,
      onTimeout: () => throw GeminiGatewayException(
        provider: AccountProvider.kiro,
        kind: GeminiGatewayFailureKind.serviceUnavailable,
        message: '$timeoutLabel timed out.',
        statusCode: 504,
        source: GeminiGatewayFailureSource.transport,
      ),
    );
  }

  bool _shouldRetry(GeminiGatewayException error) {
    return switch (error.kind) {
      GeminiGatewayFailureKind.quota =>
        error.retryAfter != null && error.retryAfter! <= _retryPolicy.default429Delay,
      GeminiGatewayFailureKind.capacity || GeminiGatewayFailureKind.serviceUnavailable => true,
      GeminiGatewayFailureKind.auth ||
      GeminiGatewayFailureKind.unsupportedModel ||
      GeminiGatewayFailureKind.invalidRequest ||
      GeminiGatewayFailureKind.unknown => false,
    };
  }

  Map<String, String> _headers({required String accessToken}) {
    return {
      HttpHeaders.authorizationHeader: 'Bearer $accessToken',
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.acceptHeader: '*/*',
      HttpHeaders.userAgentHeader: 'aws-sdk-js/1.0.27 KiroIDE-0.11.107-$_fingerprint',
      'x-amz-user-agent': 'aws-sdk-js/1.0.27 KiroIDE-0.11.107-$_fingerprint',
      'x-amzn-codewhisperer-optout': 'true',
      'x-amzn-kiro-agent-mode': 'vibe',
      'amz-sdk-invocation-id': _uuid.v4(),
      'amz-sdk-request': 'attempt=1; max=3',
    };
  }

  Uri _generateUri(ProxyRuntimeAccount account) {
    final region = (account.providerRegion ?? defaultKiroRegion).trim();
    return Uri.parse('https://q.$region.amazonaws.com/generateAssistantResponse');
  }

  Uri _listModelsUri(ProxyRuntimeAccount account, {String? nextToken}) {
    final region = (account.providerRegion ?? defaultKiroRegion).trim();
    return Uri.https('q.$region.amazonaws.com', '/ListAvailableModels', {
      'origin': 'AI_EDITOR',
      if (nextToken?.trim().isNotEmpty == true) 'nextToken': nextToken!.trim(),
      if (account.providerProfileArn?.trim().isNotEmpty == true)
        'profileArn': account.providerProfileArn!.trim(),
    });
  }

  Uri _refreshUri(ProxyRuntimeAccount account) {
    final region = (account.providerRegion ?? defaultKiroRegion).trim();
    return Uri.parse('https://prod.$region.auth.desktop.kiro.dev/refreshToken');
  }

  Uri _builderIdRefreshUri(String region) {
    return Uri.parse('https://oidc.$region.amazonaws.com/token');
  }

  Map<String, Object?> _buildRequestBody({
    required ProxyRuntimeAccount account,
    required UnifiedPromptRequest request,
    required String model,
  }) {
    final normalizedTurns = _normalizeTurns(request, model: model);
    final history = <Map<String, Object?>>[];

    if (normalizedTurns.isEmpty) {
      normalizedTurns.add(const UnifiedTurn(role: 'user', parts: [UnifiedPart.text('(empty)')]));
    }

    var currentTurn = normalizedTurns.removeLast();
    Map<String, Object?>? trailingAssistantMessage;
    if (currentTurn.role == 'assistant') {
      trailingAssistantMessage = _assistantMessage(
        currentTurn,
        toolsEnabled: request.tools.isNotEmpty,
      );
      currentTurn = const UnifiedTurn(role: 'user', parts: [UnifiedPart.text('Continue')]);
    }

    for (final turn in normalizedTurns) {
      history.add(
        turn.role == 'assistant'
            ? _assistantMessage(turn, toolsEnabled: request.tools.isNotEmpty)
            : _userMessage(
                turn,
                model: model,
                includeTools: false,
                toolsEnabled: request.tools.isNotEmpty,
              ),
      );
    }
    if (trailingAssistantMessage != null) {
      history.add(trailingAssistantMessage);
    }

    final payload = <String, Object?>{
      'conversationState': {
        'chatTriggerType': 'MANUAL',
        'conversationId': _uuid.v4(),
        'currentMessage': {
          'userInputMessage': _userMessage(
            currentTurn,
            model: model,
            includeTools: true,
            toolsEnabled: request.tools.isNotEmpty,
            tools: request.tools,
          )['userInputMessage'],
        },
        if (history.isNotEmpty) 'history': history,
      },
      if (account.providerProfileArn?.trim().isNotEmpty == true)
        'profileArn': account.providerProfileArn,
    };
    return payload;
  }

  List<UnifiedTurn> _normalizeTurns(UnifiedPromptRequest request, {required String model}) {
    final merged = <UnifiedTurn>[];
    final systemInstruction = buildKiroSystemInstruction(request.systemInstruction, model: model);
    for (final turn in request.turns) {
      if (merged.isNotEmpty && merged.last.role == turn.role) {
        final last = merged.removeLast();
        merged.add(UnifiedTurn(role: last.role, parts: [...last.parts, ...turn.parts]));
      } else {
        merged.add(turn);
      }
    }

    if (systemInstruction?.trim().isNotEmpty == true) {
      final instruction = UnifiedPart.text(systemInstruction!.trim());
      if (merged.isEmpty || merged.first.role != 'user') {
        merged.insert(0, UnifiedTurn(role: 'user', parts: [instruction]));
      } else {
        final first = merged.removeAt(0);
        merged.insert(0, UnifiedTurn(role: 'user', parts: [instruction, ...first.parts]));
      }
    }

    if (merged.isNotEmpty && merged.first.role != 'user') {
      merged.insert(0, const UnifiedTurn(role: 'user', parts: [UnifiedPart.text('(empty)')]));
    }

    final alternating = <UnifiedTurn>[];
    for (final turn in merged) {
      if (alternating.isNotEmpty && alternating.last.role == turn.role) {
        alternating.add(
          UnifiedTurn(
            role: turn.role == 'assistant' ? 'user' : 'assistant',
            parts: const [UnifiedPart.text('(empty)')],
          ),
        );
      }
      alternating.add(turn);
    }
    return alternating;
  }

  Map<String, Object?> _userMessage(
    UnifiedTurn turn, {
    required String model,
    required bool includeTools,
    required bool toolsEnabled,
    List<UnifiedToolDeclaration> tools = const [],
  }) {
    final text = _userText(turn.parts, toolsEnabled: toolsEnabled);
    final toolResults = toolsEnabled ? _toolResults(turn.parts) : const <Map<String, Object?>>[];
    final images = _images(turn.parts);
    final context = <String, Object?>{};

    if (includeTools && tools.isNotEmpty) {
      context['tools'] = [
        for (final tool in tools)
          {
            'toolSpecification': {
              'name': tool.name,
              'description': tool.description.trim().isEmpty
                  ? 'Tool: ${tool.name}'
                  : tool.description,
              'inputSchema': {'json': _sanitizeSchema(tool.parameters)},
            },
          },
      ];
    }
    if (toolResults.isNotEmpty) {
      context['toolResults'] = toolResults;
    }

    return {
      'userInputMessage': {
        'content': text.isEmpty ? '(empty)' : text,
        'modelId': model,
        'origin': 'AI_EDITOR',
        if (images.isNotEmpty) 'images': images,
        if (context.isNotEmpty) 'userInputMessageContext': context,
      },
    };
  }

  Map<String, Object?> _assistantMessage(UnifiedTurn turn, {required bool toolsEnabled}) {
    final text = _assistantText(turn.parts, toolsEnabled: toolsEnabled);
    final toolUses = toolsEnabled ? _toolUses(turn.parts) : const <Map<String, Object?>>[];
    return {
      'assistantResponseMessage': {
        'content': text.isEmpty ? '(empty)' : text,
        if (toolUses.isNotEmpty) 'toolUses': toolUses,
      },
    };
  }

  String _userText(List<UnifiedPart> parts, {required bool toolsEnabled}) {
    final buffer = <String>[];
    for (final part in parts) {
      switch (part.type) {
        case UnifiedPartType.text:
        case UnifiedPartType.thought:
          final text = part.text?.trim();
          if (text != null && text.isNotEmpty) {
            buffer.add(text);
          }
          break;
        case UnifiedPartType.functionResponse:
          if (!toolsEnabled) {
            buffer.add(
              '[Tool Result: ${part.name ?? 'tool'}]\n${jsonEncode(part.arguments ?? const {})}',
            );
          }
          break;
        case UnifiedPartType.functionCall:
          if (!toolsEnabled) {
            buffer.add('[Tool: ${part.name ?? 'tool'}]\n${jsonEncode(part.arguments ?? const {})}');
          }
          break;
        case UnifiedPartType.inlineData:
        case UnifiedPartType.fileData:
          break;
      }
    }
    return buffer.join('\n\n').trim();
  }

  String _assistantText(List<UnifiedPart> parts, {required bool toolsEnabled}) {
    final buffer = <String>[];
    for (final part in parts) {
      switch (part.type) {
        case UnifiedPartType.text:
        case UnifiedPartType.thought:
          final text = part.text?.trim();
          if (text != null && text.isNotEmpty) {
            buffer.add(text);
          }
          break;
        case UnifiedPartType.functionCall:
          if (!toolsEnabled) {
            buffer.add('[Tool: ${part.name ?? 'tool'}]\n${jsonEncode(part.arguments ?? const {})}');
          }
          break;
        case UnifiedPartType.functionResponse:
          if (!toolsEnabled) {
            buffer.add(
              '[Tool Result: ${part.name ?? 'tool'}]\n${jsonEncode(part.arguments ?? const {})}',
            );
          }
          break;
        case UnifiedPartType.inlineData:
        case UnifiedPartType.fileData:
          break;
      }
    }
    return buffer.join('\n\n').trim();
  }

  List<Map<String, Object?>> _toolUses(List<UnifiedPart> parts) {
    final result = <Map<String, Object?>>[];
    for (final part in parts) {
      if (part.type != UnifiedPartType.functionCall) {
        continue;
      }
      result.add({
        'name': part.name ?? 'tool',
        'input': part.arguments ?? const <String, Object?>{},
        'toolUseId': part.callId ?? 'call_${_uuid.v4()}',
      });
    }
    return result;
  }

  List<Map<String, Object?>> _toolResults(List<UnifiedPart> parts) {
    final result = <Map<String, Object?>>[];
    for (final part in parts) {
      if (part.type != UnifiedPartType.functionResponse) {
        continue;
      }
      result.add({
        'content': [
          {'text': _toolResultText(part.arguments)},
        ],
        'status': 'success',
        'toolUseId': part.callId ?? '',
      });
    }
    return result;
  }

  String _toolResultText(Map<String, Object?>? arguments) {
    final result = arguments?['result'];
    if (result is String && result.trim().isNotEmpty) {
      return result.trim();
    }
    return jsonEncode(arguments ?? const <String, Object?>{});
  }

  List<Map<String, Object?>> _images(List<UnifiedPart> parts) {
    final images = <Map<String, Object?>>[];
    for (final part in parts) {
      if (part.type != UnifiedPartType.inlineData) {
        continue;
      }
      final mimeType = (part.mimeType ?? '').trim().toLowerCase();
      final data = (part.data ?? '').trim();
      if (!mimeType.startsWith('image/') || data.isEmpty) {
        continue;
      }
      images.add({
        'format': mimeType.split('/').last,
        'source': {'bytes': data},
      });
    }
    return images;
  }

  bool _shouldExposeReasoning(UnifiedPromptRequest request) {
    final reasoningEffort = request.reasoningEffort?.trim().toLowerCase();
    if (reasoningEffort != null && reasoningEffort.isNotEmpty) {
      return reasoningEffort != 'none' && reasoningEffort != 'minimal';
    }

    final thinkingConfig = request.googleThinkingConfig;
    if (thinkingConfig == null) {
      return false;
    }

    if (thinkingConfig['includeThoughts'] is bool) {
      return thinkingConfig['includeThoughts'] as bool;
    }
    if (thinkingConfig['include_thoughts'] is bool) {
      return thinkingConfig['include_thoughts'] as bool;
    }

    final budget =
        _parseThinkingBudget(thinkingConfig['thinkingBudget']) ??
        _parseThinkingBudget(thinkingConfig['thinking_budget']);
    if (budget != null) {
      return budget != 0;
    }

    final thinkingLevel =
        (thinkingConfig['thinkingLevel'] as String?)?.trim().toUpperCase() ??
        (thinkingConfig['thinking_level'] as String?)?.trim().toUpperCase();
    if (thinkingLevel != null && thinkingLevel.isNotEmpty) {
      return thinkingLevel != 'LOW' && thinkingLevel != 'MINIMAL';
    }

    return false;
  }

  Map<String, Object?> _sanitizeSchema(Map<String, Object?> schema) {
    final result = <String, Object?>{};
    for (final entry in schema.entries) {
      if (entry.key == 'additionalProperties') {
        continue;
      }
      if (entry.key == 'required' && entry.value is List && (entry.value as List).isEmpty) {
        continue;
      }
      if (entry.value is Map<String, Object?>) {
        result[entry.key] = _sanitizeSchema(entry.value as Map<String, Object?>);
      } else if (entry.value is Map) {
        result[entry.key] = _sanitizeSchema((entry.value as Map).cast<String, Object?>());
      } else if (entry.value is List) {
        result[entry.key] = (entry.value as List)
            .map((item) {
              if (item is Map<String, Object?>) {
                return _sanitizeSchema(item);
              }
              if (item is Map) {
                return _sanitizeSchema(item.cast<String, Object?>());
              }
              return item;
            })
            .toList(growable: false);
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  Future<OAuthTokens> _refreshDesktopTokens(
    ProxyRuntimeAccount account, {
    KiroAuthSourceSnapshot? source,
  }) async {
    final response = await _executeWithRetry(
      () => _sendRetryable(
        method: 'POST',
        uri: _refreshUri(account),
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.userAgentHeader: 'KiroIDE-0.11.107-$_fingerprint',
        },
        body: jsonEncode({'refreshToken': account.tokens.refreshToken}),
        timeoutLabel: 'Kiro token refresh',
      ),
    );
    final body = await response.stream.bytesToString();

    return _tokensFromRefreshResponse(
      account: account,
      source: source,
      body: body,
      statusCode: response.statusCode,
    );
  }

  Future<OAuthTokens> _refreshBuilderIdTokens(
    ProxyRuntimeAccount account,
    KiroAuthSourceSnapshot source,
  ) async {
    final refreshToken = account.tokens.refreshToken.trim().isNotEmpty
        ? account.tokens.refreshToken.trim()
        : source.refreshToken.trim();
    if (refreshToken.isEmpty ||
        source.clientId?.trim().isNotEmpty != true ||
        source.clientSecret?.trim().isNotEmpty != true) {
      throw GeminiGatewayException(
        provider: AccountProvider.kiro,
        kind: GeminiGatewayFailureKind.auth,
        message: 'Kiro Builder ID refresh metadata is incomplete.',
        statusCode: 401,
        source: GeminiGatewayFailureSource.transport,
      );
    }

    final response = await _executeWithRetry(
      () => _sendRetryable(
        method: 'POST',
        uri: _builderIdRefreshUri(source.effectiveRegion),
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.userAgentHeader: 'KiroIDE-0.11.107-$_fingerprint',
        },
        body: jsonEncode({
          'grantType': 'refresh_token',
          'clientId': source.clientId,
          'clientSecret': source.clientSecret,
          'refreshToken': refreshToken,
        }),
        timeoutLabel: 'Kiro Builder ID token refresh',
      ),
    );
    final body = await response.stream.bytesToString();

    final tokens = _tokensFromRefreshResponse(
      account: account,
      source: source,
      body: body,
      statusCode: response.statusCode,
    );
    if (account.credentialSourcePath?.trim().isNotEmpty == true) {
      await persistKiroAuthSourceSnapshot(
        source.copyWith(
          sourcePath: account.credentialSourcePath!.trim(),
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          expiry: tokens.expiry,
          profileArn: account.providerProfileArn,
        ),
        outputPath: account.credentialSourcePath,
      );
    }
    return tokens;
  }

  OAuthTokens _tokensFromRefreshResponse({
    required ProxyRuntimeAccount account,
    required KiroAuthSourceSnapshot? source,
    required String body,
    required int statusCode,
  }) {
    final decoded = _tryDecodeJsonMap(body);
    final accessToken = (decoded['accessToken'] as String? ?? '').trim();
    final refreshToken = (decoded['refreshToken'] as String?)?.trim();
    final expiresIn = (decoded['expiresIn'] as num?)?.toInt() ?? 3600;
    final profileArn = (decoded['profileArn'] as String?)?.trim();
    if (accessToken.isEmpty) {
      throw GeminiGatewayException(
        provider: AccountProvider.kiro,
        kind: GeminiGatewayFailureKind.auth,
        message: 'Kiro token refresh succeeded without an access token.',
        statusCode: statusCode >= 400 ? statusCode : 502,
        source: GeminiGatewayFailureSource.transport,
      );
    }

    account.providerProfileArn = profileArn ?? account.providerProfileArn ?? source?.profileArn;
    return OAuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken?.isNotEmpty == true ? refreshToken! : account.tokens.refreshToken,
      expiry: DateTime.now().add(Duration(seconds: max(expiresIn - 60, 60))),
      tokenType: 'Bearer',
      scope: null,
    );
  }
}

GeminiGatewayException decodeKiroGatewayError(int statusCode, String body) {
  final decoded = _tryDecodeJsonMap(body);
  final message = (decoded['message'] as String?)?.trim().isNotEmpty == true
      ? (decoded['message'] as String).trim()
      : (decoded['error_description'] as String?)?.trim().isNotEmpty == true
      ? (decoded['error_description'] as String).trim()
      : body.trim().isNotEmpty
      ? body.trim()
      : 'Kiro request failed.';

  final lower = message.toLowerCase();
  if (statusCode == 404 ||
      lower.contains('unsupported model') ||
      lower.contains('model not found') ||
      lower.contains('unknown model')) {
    return GeminiGatewayException(
      provider: AccountProvider.kiro,
      kind: GeminiGatewayFailureKind.unsupportedModel,
      message: message,
      statusCode: statusCode,
    );
  }
  if (statusCode == 401 || statusCode == 403) {
    return GeminiGatewayException(
      provider: AccountProvider.kiro,
      kind: GeminiGatewayFailureKind.auth,
      message: message,
      statusCode: statusCode,
    );
  }
  if (statusCode == 400 &&
      (lower.contains('invalid_grant') ||
          lower.contains('expired_token') ||
          lower.contains('token has expired') ||
          lower.contains('unauthorized'))) {
    return GeminiGatewayException(
      provider: AccountProvider.kiro,
      kind: GeminiGatewayFailureKind.auth,
      message: message,
      statusCode: statusCode,
    );
  }
  if (statusCode == 429) {
    return GeminiGatewayException(
      provider: AccountProvider.kiro,
      kind: GeminiGatewayFailureKind.quota,
      message: message,
      statusCode: statusCode,
      retryAfter: _retryAfterFromMessage(message),
    );
  }
  if (statusCode == 400) {
    return GeminiGatewayException(
      provider: AccountProvider.kiro,
      kind: GeminiGatewayFailureKind.invalidRequest,
      message: message,
      statusCode: statusCode,
    );
  }
  if (statusCode >= 500) {
    return GeminiGatewayException(
      provider: AccountProvider.kiro,
      kind: GeminiGatewayFailureKind.serviceUnavailable,
      message: message,
      statusCode: statusCode,
      retryAfter: _retryAfterFromMessage(message),
    );
  }
  return GeminiGatewayException(
    provider: AccountProvider.kiro,
    kind: GeminiGatewayFailureKind.unknown,
    message: message,
    statusCode: statusCode,
  );
}

class _KiroEvent {
  const _KiroEvent.content(this.text)
    : type = _KiroEventType.content,
      thoughtSignature = null,
      toolCall = null,
      contextUsagePercentage = null;

  const _KiroEvent.reasoning(this.text, this.thoughtSignature)
    : type = _KiroEventType.reasoning,
      toolCall = null,
      contextUsagePercentage = null;

  const _KiroEvent.toolCall(this.toolCall)
    : type = _KiroEventType.toolCall,
      text = null,
      thoughtSignature = null,
      contextUsagePercentage = null;

  const _KiroEvent.contextUsage(this.contextUsagePercentage)
    : type = _KiroEventType.contextUsage,
      text = null,
      thoughtSignature = null,
      toolCall = null;

  final _KiroEventType type;
  final String? text;
  final String? thoughtSignature;
  final Map<String, Object?>? toolCall;
  final double? contextUsagePercentage;
}

enum _KiroEventType { content, reasoning, toolCall, contextUsage }

class _KiroEventStreamParser {
  String _buffer = '';
  String? _lastContent;
  Map<String, Object?>? _currentToolCall;
  final List<Map<String, Object?>> _completedToolCalls = <Map<String, Object?>>[];

  List<_KiroEvent> feed(List<int> chunk) {
    _buffer += utf8.decode(chunk, allowMalformed: true);
    final events = <_KiroEvent>[];

    while (true) {
      final match = _nextEventStart(_buffer);
      if (match == null) {
        break;
      }
      final end = _findMatchingBrace(_buffer, match.$1);
      if (end == -1) {
        break;
      }

      final jsonText = _buffer.substring(match.$1, end + 1);
      _buffer = _buffer.substring(end + 1);
      final decoded = _tryDecodeJsonMap(jsonText);
      if (decoded.isEmpty) {
        continue;
      }

      switch (match.$2) {
        case 'content':
          final content = (decoded['content'] as String? ?? '');
          if (content.isEmpty || content == _lastContent) {
            continue;
          }
          _lastContent = content;
          events.add(_KiroEvent.content(content));
          break;
        case 'reasoning':
          final text = (decoded['text'] as String? ?? '');
          final signature = (decoded['signature'] as String?)?.trim();
          if (text.isEmpty && (signature == null || signature.isEmpty)) {
            continue;
          }
          events.add(_KiroEvent.reasoning(text, signature));
          break;
        case 'tool_start':
          _finalizeCurrentToolCall(events);
          final input = decoded['input'];
          _currentToolCall = {
            'id': (decoded['toolUseId'] as String?)?.trim().isNotEmpty == true
                ? (decoded['toolUseId'] as String).trim()
                : 'call_${const Uuid().v4()}',
            'type': 'function',
            'function': {
              'name': (decoded['name'] as String?)?.trim() ?? 'tool',
              'arguments': _toolInputChunk(input),
            },
          };
          if (decoded['stop'] == true) {
            _finalizeCurrentToolCall(events);
          }
          break;
        case 'tool_input':
          if (_currentToolCall != null) {
            final function =
                (_currentToolCall!['function'] as Map?)?.cast<String, Object?>() ??
                <String, Object?>{};
            final previous = (function['arguments'] as String?) ?? '';
            function['arguments'] = '$previous${_toolInputChunk(decoded['input'])}';
            _currentToolCall!['function'] = function;
          }
          break;
        case 'tool_stop':
          if (decoded['stop'] == true) {
            _finalizeCurrentToolCall(events);
          }
          break;
        case 'context_usage':
          final percentage = (decoded['contextUsagePercentage'] as num?)?.toDouble();
          if (percentage != null) {
            events.add(_KiroEvent.contextUsage(percentage));
          }
          break;
      }
    }

    return events;
  }

  (int, String)? _nextEventStart(String text) {
    final contentIndex = text.indexOf('{"content":');
    final toolStartIndex = text.indexOf('{"name":');
    final toolInputIndex = text.indexOf('{"input":');
    final toolStopIndex = text.indexOf('{"stop":');
    final contextUsageIndex = text.indexOf('{"contextUsagePercentage":');
    final reasoningTextIndex = text.indexOf('{"text":');
    final reasoningSignatureIndex = text.indexOf('{"signature":');
    final candidates = <({int index, String type})>[
      if (contentIndex >= 0) (index: contentIndex, type: 'content'),
      if (reasoningTextIndex >= 0) (index: reasoningTextIndex, type: 'reasoning'),
      if (reasoningSignatureIndex >= 0) (index: reasoningSignatureIndex, type: 'reasoning'),
      if (toolStartIndex >= 0) (index: toolStartIndex, type: 'tool_start'),
      if (toolInputIndex >= 0) (index: toolInputIndex, type: 'tool_input'),
      if (toolStopIndex >= 0) (index: toolStopIndex, type: 'tool_stop'),
      if (contextUsageIndex >= 0) (index: contextUsageIndex, type: 'context_usage'),
    ];
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((left, right) => left.index.compareTo(right.index));
    final best = candidates.first;
    return (best.index, best.type);
  }

  void _finalizeCurrentToolCall(List<_KiroEvent> events) {
    if (_currentToolCall == null) {
      return;
    }
    final toolCall = Map<String, Object?>.from(_currentToolCall!);
    final function = ((toolCall['function'] as Map?) ?? const {}).cast<String, Object?>();
    final arguments = (function['arguments'] as String? ?? '').trim();
    function['arguments'] = _normalizeToolArguments(arguments);
    toolCall['function'] = function;

    final key = '${function['name']}:${function['arguments']}';
    final duplicate = _completedToolCalls.any((existing) {
      final existingFunction = ((existing['function'] as Map?) ?? const {}).cast<String, Object?>();
      final existingKey = '${existingFunction['name']}:${existingFunction['arguments']}';
      return existingKey == key;
    });
    if (!duplicate) {
      _completedToolCalls.add(toolCall);
      events.add(_KiroEvent.toolCall(toolCall));
    }
    _currentToolCall = null;
  }

  String _toolInputChunk(Object? input) {
    if (input is String) {
      return input;
    }
    if (input is Map || input is List) {
      return jsonEncode(input);
    }
    return '';
  }

  String _normalizeToolArguments(String raw) {
    if (raw.isEmpty) {
      return '{}';
    }
    try {
      final decoded = jsonDecode(raw);
      return jsonEncode(decoded);
    } catch (_) {
      return '{}';
    }
  }
}

class _KiroResponseAccumulator {
  _KiroResponseAccumulator({required this.model, required this.includeReasoning});

  final String model;
  final bool includeReasoning;
  final StringBuffer _text = StringBuffer();
  final StringBuffer _reasoningText = StringBuffer();
  final List<Map<String, Object?>> _thoughts = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _toolCalls = <Map<String, Object?>>[];
  double? _contextUsagePercentage;

  bool get hasEmittableOutput => _text.isNotEmpty || _thoughts.isNotEmpty || _toolCalls.isNotEmpty;

  void apply(_KiroEvent event) {
    switch (event.type) {
      case _KiroEventType.content:
        final text = event.text;
        if (text != null && text.isNotEmpty) {
          _text.write(text);
        }
        break;
      case _KiroEventType.reasoning:
        final text = event.text;
        final thoughtSignature = event.thoughtSignature;
        if (text != null && text.isNotEmpty) {
          _reasoningText.write(text);
        }
        if (includeReasoning &&
            ((text != null && text.isNotEmpty) ||
                (thoughtSignature != null && thoughtSignature.isNotEmpty))) {
          _thoughts.add({
            'thought': true,
            if (text != null && text.isNotEmpty) 'text': text,
            if (thoughtSignature != null && thoughtSignature.isNotEmpty)
              'thoughtSignature': thoughtSignature,
          });
        }
        break;
      case _KiroEventType.toolCall:
        final toolCall = event.toolCall;
        if (toolCall != null) {
          _toolCalls.add(toolCall);
        }
        break;
      case _KiroEventType.contextUsage:
        _contextUsagePercentage = event.contextUsagePercentage;
        break;
    }
  }

  Map<String, Object?> toPayload({bool finalChunk = false}) {
    final usageMetadata = _buildUsageMetadata();
    return {
      'response': {
        'candidates': [
          {
            'content': {
              'parts': [
                for (final thought in _thoughts) thought,
                if (_text.isNotEmpty) {'text': _text.toString()},
                for (final toolCall in _toolCalls)
                  {
                    'functionCall': {
                      'id': toolCall['id'],
                      'name': ((toolCall['function'] as Map?)?['name']),
                      'args': _decodeJsonLike(((toolCall['function'] as Map?)?['arguments'])),
                    },
                  },
              ],
            },
            'finishReason': 'STOP',
          },
        ],
        'usageMetadata': usageMetadata,
      },
      if (finalChunk) 'final_chunk': true,
    };
  }

  Map<String, Object?> _buildUsageMetadata() {
    final visibleTokenCount = _estimateKiroTokenCount(_completionTokenSource());
    final reasoningTokenCount = _estimateKiroTokenCount(_reasoningText.toString());
    final completionTokenCount = visibleTokenCount + reasoningTokenCount;
    final estimatedTotalTokenCount = _contextUsagePercentage != null && _contextUsagePercentage! > 0
        ? ((_contextUsagePercentage! / 100) * _maxInputTokensForModel(model)).floor()
        : completionTokenCount;
    final totalTokenCount = max(completionTokenCount, estimatedTotalTokenCount);
    final promptTokenCount = max(0, totalTokenCount - completionTokenCount);

    return {
      'promptTokenCount': promptTokenCount,
      'candidatesTokenCount': completionTokenCount,
      'totalTokenCount': totalTokenCount,
      'cachedContentTokenCount': 0,
      'thoughtsTokenCount': reasoningTokenCount,
    };
  }

  String _completionTokenSource() {
    if (_toolCalls.isEmpty) {
      return _text.toString();
    }

    final buffer = StringBuffer(_text.toString());
    for (final toolCall in _toolCalls) {
      final function = (toolCall['function'] as Map?)?.cast<String, Object?>() ?? const {};
      final name = (function['name'] as String?)?.trim();
      final arguments = (function['arguments'] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        buffer.write('\n$name');
      }
      if (arguments != null && arguments.isNotEmpty) {
        buffer.write('\n$arguments');
      }
    }
    return buffer.toString();
  }
}

int? _parseThinkingBudget(Object? value) {
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

const int _defaultKiroMaxInputTokens = 200000;

int _estimateKiroTokenCount(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return 0;
  }

  final baseEstimate = trimmed.length ~/ 4 + 1;
  return (baseEstimate * 1.15).round();
}

int _maxInputTokensForModel(String model) {
  final normalized = ModelCatalog.normalizeModel(model);
  return switch (normalized) {
    'claude-haiku-4.5' ||
    'claude-sonnet-4' ||
    'claude-sonnet-4.5' ||
    'claude-opus-4.5' ||
    'auto' => _defaultKiroMaxInputTokens,
    _ => _defaultKiroMaxInputTokens,
  };
}

Future<void> _defaultWait(Duration delay) => Future<void>.delayed(delay);

GeminiGatewayException _decodeTransportError(Object error) {
  if (error is GeminiGatewayException) {
    return error;
  }
  if (error is SocketException || error is HttpException || error is TimeoutException) {
    return GeminiGatewayException(
      provider: AccountProvider.kiro,
      kind: GeminiGatewayFailureKind.serviceUnavailable,
      message: error.toString(),
      statusCode: 503,
      source: GeminiGatewayFailureSource.transport,
    );
  }
  return GeminiGatewayException(
    provider: AccountProvider.kiro,
    kind: GeminiGatewayFailureKind.unknown,
    message: error.toString(),
    statusCode: 500,
    source: GeminiGatewayFailureSource.transport,
  );
}

Map<String, Object?> _tryDecodeJsonMap(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
  } catch (_) {}
  return const <String, Object?>{};
}

Object? _decodeJsonLike(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) {
    return const <String, Object?>{};
  }
  try {
    return jsonDecode(raw);
  } catch (_) {
    return const <String, Object?>{};
  }
}

Duration? _retryAfterFromMessage(String message) {
  final match = RegExp(
    r'(?:retry|reset)(?:\s+\w+){0,3}\s+(?:after|in)\s+([0-9]+)\s*(seconds?|minutes?|hours?)',
    caseSensitive: false,
  ).firstMatch(message);
  if (match == null) {
    return null;
  }

  final value = int.tryParse(match.group(1) ?? '');
  final unit = (match.group(2) ?? '').toLowerCase();
  if (value == null) {
    return null;
  }
  if (unit.startsWith('hour')) {
    return Duration(hours: value);
  }
  if (unit.startsWith('minute')) {
    return Duration(minutes: value);
  }
  return Duration(seconds: value);
}

String _buildMachineFingerprint() {
  final host = Platform.localHostname.trim();
  final user =
      Platform.environment['USERNAME']?.trim() ?? Platform.environment['USER']?.trim() ?? 'kick';
  return '${host.isEmpty ? 'host' : host}-$user';
}

int _findMatchingBrace(String text, int startPos) {
  if (startPos >= text.length || text[startPos] != '{') {
    return -1;
  }

  var braceCount = 0;
  var inString = false;
  var escapeNext = false;
  for (var index = startPos; index < text.length; index += 1) {
    final char = text[index];
    if (escapeNext) {
      escapeNext = false;
      continue;
    }
    if (char == '\\' && inString) {
      escapeNext = true;
      continue;
    }
    if (char == '"') {
      inString = !inString;
      continue;
    }
    if (!inString) {
      if (char == '{') {
        braceCount += 1;
      } else if (char == '}') {
        braceCount -= 1;
        if (braceCount == 0) {
          return index;
        }
      }
    }
  }
  return -1;
}
