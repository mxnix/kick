import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/logging/log_sanitizer.dart';
import '../account_pool/account_pool.dart';
import '../gemini/gemini_code_assist_client.dart';
import '../model_catalog.dart';
import '../openai/openai_request_parser.dart';
import '../openai/openai_response_mapper.dart';
import '../openai/sse.dart';
import 'proxy_cors.dart';

const _maxRequestBodyBytes = 20 * 1024 * 1024;

@pragma('vm:entry-point')
Future<void> proxyIsolateMain(SendPort sendPort) async {
  final commands = ReceivePort();
  final host = _ProxyIsolateHost(sendPort);
  sendPort.send({'type': 'ready', 'port': commands.sendPort});
  await for (final message in commands) {
    if (message is! Map) {
      continue;
    }
    final shouldContinue = await host.handle(message.cast<String, Object?>());
    if (!shouldContinue) {
      commands.close();
    }
  }
}

class _ProxyIsolateHost {
  _ProxyIsolateHost(this._sendPort)
    : _client = GeminiCodeAssistClient(
        onTokensUpdated: (account, tokens) async {
          _sendPort.send({
            'type': 'token_updated',
            'payload': {'token_ref': account.tokenRef, 'tokens': tokens.toJson()},
          });
        },
      );

  final SendPort _sendPort;
  final GeminiCodeAssistClient _client;
  final _uuid = const Uuid();

  Map<String, Object?>? _settings;
  ModelCatalog _catalog = ModelCatalog(customModels: const []);
  GeminiAccountPool _pool = GeminiAccountPool(<ProxyRuntimeAccount>[]);
  HttpServer? _server;
  DateTime? _startedAt;
  int _requestCount = 0;
  String? _lastRuntimeError;

  bool get _allowLan => _settings?['allow_lan'] == true;
  String get _configuredHost => _settings?['host'] as String? ?? '127.0.0.1';

  Future<bool> handle(Map<String, Object?> message) async {
    switch (message['type']) {
      case 'configure':
        final payload =
            (message['payload'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
        final previousSettings = _settings;
        _settings = (payload['settings'] as Map?)?.cast<String, Object?>();
        final accounts = ((payload['accounts'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => ProxyRuntimeAccount.fromJson(item.cast<String, Object?>()))
            .toList(growable: true);
        _pool = GeminiAccountPool(accounts);
        _catalog = ModelCatalog(
          customModels: ((_settings?['custom_models'] as List?) ?? const []).cast<String>(),
        );
        _client.updateRetryPolicy(
          GeminiRetryPolicy(
            maxRetries: _settings?['request_max_retries'] as int? ?? defaultGeminiRequestMaxRetries,
          ),
        );
        await _publishAccounts();
        if (_server != null &&
            _shouldRestartServerForConfigurationChange(previousSettings, _settings)) {
          await _restartServer();
        } else {
          _publishStatus();
        }
        return true;
      case 'start':
        await _startServer();
        return true;
      case 'stop':
        await _stopServer();
        return true;
      case 'shutdown':
        await _stopServer();
        return false;
    }
    return true;
  }

  Future<void> _startServer() async {
    if (_settings == null) {
      _lastRuntimeError = 'Proxy is not configured yet.';
      await _logFailure(
        category: 'proxy.runtime',
        route: '/runtime/start',
        message: _lastRuntimeError!,
        stackTrace: StackTrace.current,
      );
      _publishStatus();
      return;
    }

    if (_server != null) {
      await _restartServer();
      return;
    }

    final handler = Pipeline()
        .addMiddleware(_errorMiddleware(this))
        .addMiddleware(_corsMiddleware(this))
        .addHandler(_router.call);
    final host = _allowLan ? '0.0.0.0' : _configuredHost;
    final port = _settings?['port'] as int? ?? 3000;
    try {
      _server = await shelf_io.serve(handler, host, port);
      _startedAt = DateTime.now();
      _lastRuntimeError = null;
    } catch (error, stackTrace) {
      _lastRuntimeError = error.toString();
      await _logFailure(
        category: 'proxy.runtime',
        route: '/runtime/start',
        message: _lastRuntimeError!,
        stackTrace: stackTrace,
      );
    }
    _publishStatus();
  }

  Future<void> _restartServer() async {
    await _stopServer();
    await _startServer();
  }

  Future<void> _stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _startedAt = null;
    _publishStatus();
  }

  Router get _router {
    final router = Router();
    router.options('/<ignored|.*>', (Request request) => Response.ok(''));
    router.get('/health', (Request request) {
      return _jsonResponse({
        'ok': true,
        'running': _server != null,
        'active_accounts': _pool.accounts.where((item) => item.enabled).length,
        'healthy_accounts': _healthyAccountCount(),
      });
    });
    router.get('/v1/models', (Request request) {
      final authResult = _authorizeRequest(request);
      if (authResult != null) {
        return authResult;
      }
      return _jsonResponse(_catalog.toOpenAiModelList());
    });
    router.post('/v1/chat/completions', _handleChatCompletions);
    router.post('/v1/responses', _handleResponses);
    return router;
  }

  Future<Response> _handleChatCompletions(Request request) async {
    final authResult = _authorizeRequest(request);
    if (authResult != null) {
      return authResult;
    }

    final route = request.requestedUri.path;
    final body = await _readJson(request);
    if (body == null) {
      return _errorResponse(400, 'invalid_request_error', 'Request body must be valid JSON.');
    }
    final requestId = _uuid.v4().replaceAll('-', '');
    UnifiedPromptRequest? prompt;
    _RequestRetryTracker? retryTracker;

    try {
      final resolvedPrompt = prompt = OpenAiRequestParser.parseChatRequest(
        body,
        requestId: requestId,
      );
      retryTracker = _RequestRetryTracker.fromRequest(resolvedPrompt);
      if (!_catalog.contains(resolvedPrompt.model)) {
        return _errorResponse(
          400,
          'model_not_found',
          'Model `${resolvedPrompt.model}` is not available in KiCk.',
        );
      }

      await _logRequest('chat.completions', request, body);
      await _logPromptSummary(resolvedPrompt, route: route);
      if (resolvedPrompt.stream) {
        await _logTrace(
          category: 'chat.completions',
          route: route,
          message: 'Dispatching streaming request to Gemini gateway',
          details: _requestContextPayload(prompt: resolvedPrompt),
        );
        var previousText = '';
        var previousReasoningText = '';
        var previousToolCallCount = 0;
        final stream = await _executeStreamRequest(
          resolvedPrompt,
          route: route,
          retryTracker: retryTracker,
          mapper: (payload, includePrelude) {
            final events = OpenAiResponseMapper.toChatStreamDeltas(
              requestId: resolvedPrompt.requestId,
              model: resolvedPrompt.model,
              payload: payload,
              includeRole: includePrelude,
              previousText: previousText,
              previousReasoningText: previousReasoningText,
              previousToolCallCount: previousToolCallCount,
            );
            previousText = OpenAiResponseMapper.currentText(payload);
            previousReasoningText = OpenAiResponseMapper.currentReasoningText(payload);
            previousToolCallCount = OpenAiResponseMapper.currentToolCallCount(payload);
            return events;
          },
          doneEvent: () => encodeSseEvent('[DONE]'),
        );
        return Response.ok(stream, headers: _sseHeaders());
      }

      await _logTrace(
        category: 'chat.completions',
        route: route,
        message: 'Dispatching request to Gemini gateway',
        details: _requestContextPayload(prompt: resolvedPrompt),
      );
      final payload = await _executeNonStreamRequest(resolvedPrompt, retryTracker: retryTracker);
      await _logTrace(
        category: 'chat.completions',
        route: route,
        message: 'Gemini gateway returned a payload',
        details: _requestContextPayload(prompt: resolvedPrompt),
      );
      final responseBody = OpenAiResponseMapper.toChatCompletion(
        requestId: resolvedPrompt.requestId,
        model: resolvedPrompt.model,
        payload: payload,
      );
      await _logTrace(
        category: 'chat.completions',
        route: route,
        message: 'Mapped Gemini payload to OpenAI chat completion',
        details: _requestContextPayload(prompt: resolvedPrompt),
      );
      await _logResponsePreview(
        category: 'chat.completions',
        route: route,
        payload: payload,
        details: _requestContextPayload(prompt: resolvedPrompt),
      );
      await _logRetryOutcome(
        category: 'chat.completions',
        route: route,
        request: resolvedPrompt,
        tracker: retryTracker,
        succeeded: true,
      );
      _emitRequestRetriedAnalytics(
        request: resolvedPrompt,
        route: route,
        tracker: retryTracker,
        succeeded: true,
      );
      return _jsonResponse(responseBody);
    } on _RequestBodyTooLargeException catch (error, stackTrace) {
      await _logFailure(
        category: 'chat.completions',
        route: route,
        message: error.message,
        stackTrace: stackTrace,
      );
      return _errorResponse(413, 'request_too_large', error.message);
    } on FormatException catch (error, stackTrace) {
      await _logFailure(
        category: 'chat.completions',
        route: route,
        message: error.message,
        stackTrace: stackTrace,
      );
      return _errorResponse(400, 'invalid_request_error', error.message);
    } on GeminiGatewayException catch (error, stackTrace) {
      if (prompt != null) {
        _emitRequestFailedAnalytics(request: prompt, route: route, error: error);
        _emitRequestRetriedAnalytics(
          request: prompt,
          route: route,
          tracker: retryTracker,
          succeeded: false,
          error: error,
        );
        await _logRetryOutcome(
          category: 'chat.completions',
          route: route,
          request: prompt,
          tracker: retryTracker,
          succeeded: false,
          error: error,
        );
      }
      await _logFailure(
        category: 'chat.completions',
        route: route,
        message: error.message,
        stackTrace: stackTrace,
        details: _failureContextPayload(prompt: prompt, error: error),
      );
      return _gatewayErrorResponse(error);
    } catch (error, stackTrace) {
      final gatewayError = GeminiGatewayException(
        kind: GeminiGatewayFailureKind.unknown,
        message: error.toString(),
        statusCode: 500,
      );
      if (prompt != null) {
        _emitRequestFailedAnalytics(request: prompt, route: route, error: gatewayError);
        _emitRequestRetriedAnalytics(
          request: prompt,
          route: route,
          tracker: retryTracker,
          succeeded: false,
          error: gatewayError,
        );
        await _logRetryOutcome(
          category: 'chat.completions',
          route: route,
          request: prompt,
          tracker: retryTracker,
          succeeded: false,
          error: gatewayError,
        );
      }
      await _logFailure(
        category: 'chat.completions',
        route: route,
        message: error.toString(),
        stackTrace: stackTrace,
        details: _failureContextPayload(prompt: prompt, error: gatewayError),
      );
      return _errorResponse(500, 'proxy_error', error.toString());
    }
  }

  Future<Response> _handleResponses(Request request) async {
    final authResult = _authorizeRequest(request);
    if (authResult != null) {
      return authResult;
    }

    final route = request.requestedUri.path;
    final body = await _readJson(request);
    if (body == null) {
      return _errorResponse(400, 'invalid_request_error', 'Request body must be valid JSON.');
    }
    final requestId = _uuid.v4().replaceAll('-', '');
    UnifiedPromptRequest? prompt;
    _RequestRetryTracker? retryTracker;

    try {
      final resolvedPrompt = prompt = OpenAiRequestParser.parseResponsesRequest(
        body,
        requestId: requestId,
      );
      retryTracker = _RequestRetryTracker.fromRequest(resolvedPrompt);
      if (!_catalog.contains(resolvedPrompt.model)) {
        return _errorResponse(
          400,
          'model_not_found',
          'Model `${resolvedPrompt.model}` is not available in KiCk.',
        );
      }

      await _logRequest('responses', request, body);
      await _logPromptSummary(resolvedPrompt, route: route);
      if (resolvedPrompt.stream) {
        await _logTrace(
          category: 'responses',
          route: route,
          message: 'Dispatching streaming request to Gemini gateway',
          details: _requestContextPayload(prompt: resolvedPrompt),
        );
        var previousText = '';
        var previousReasoningText = '';
        var previousToolCallCount = 0;
        var previousToolCallArguments = const <String>[];
        final stream = await _executeStreamRequest(
          resolvedPrompt,
          route: route,
          retryTracker: retryTracker,
          mapper: (payload, includePrelude) {
            final events = OpenAiResponseMapper.toResponsesStreamEvents(
              requestId: resolvedPrompt.requestId,
              model: resolvedPrompt.model,
              payload: payload,
              includePrelude: includePrelude,
              previousText: previousText,
              previousReasoningText: previousReasoningText,
              previousToolCallCount: previousToolCallCount,
              previousToolCallArguments: previousToolCallArguments,
            );
            previousText = OpenAiResponseMapper.currentText(payload);
            previousReasoningText = OpenAiResponseMapper.currentReasoningText(payload);
            previousToolCallCount = OpenAiResponseMapper.currentToolCallCount(payload);
            previousToolCallArguments = OpenAiResponseMapper.currentToolCallArguments(payload);
            return events;
          },
          doneEvent: () => '',
        );
        return Response.ok(stream, headers: _sseHeaders());
      }

      final payload = await _executeNonStreamRequest(resolvedPrompt, retryTracker: retryTracker);
      await _logResponsePreview(
        category: 'responses',
        route: route,
        payload: payload,
        details: _requestContextPayload(prompt: resolvedPrompt),
      );
      await _logRetryOutcome(
        category: 'responses',
        route: route,
        request: resolvedPrompt,
        tracker: retryTracker,
        succeeded: true,
      );
      _emitRequestRetriedAnalytics(
        request: resolvedPrompt,
        route: route,
        tracker: retryTracker,
        succeeded: true,
      );
      return _jsonResponse(
        OpenAiResponseMapper.toResponsesObject(
          requestId: resolvedPrompt.requestId,
          model: resolvedPrompt.model,
          payload: payload,
        ),
      );
    } on _RequestBodyTooLargeException catch (error, stackTrace) {
      await _logFailure(
        category: 'responses',
        route: route,
        message: error.message,
        stackTrace: stackTrace,
      );
      return _errorResponse(413, 'request_too_large', error.message);
    } on FormatException catch (error, stackTrace) {
      await _logFailure(
        category: 'responses',
        route: route,
        message: error.message,
        stackTrace: stackTrace,
      );
      return _errorResponse(400, 'invalid_request_error', error.message);
    } on GeminiGatewayException catch (error, stackTrace) {
      if (prompt != null) {
        _emitRequestFailedAnalytics(request: prompt, route: route, error: error);
        _emitRequestRetriedAnalytics(
          request: prompt,
          route: route,
          tracker: retryTracker,
          succeeded: false,
          error: error,
        );
        await _logRetryOutcome(
          category: 'responses',
          route: route,
          request: prompt,
          tracker: retryTracker,
          succeeded: false,
          error: error,
        );
      }
      await _logFailure(
        category: 'responses',
        route: route,
        message: error.message,
        stackTrace: stackTrace,
        details: _failureContextPayload(prompt: prompt, error: error),
      );
      return _gatewayErrorResponse(error);
    } catch (error, stackTrace) {
      final gatewayError = GeminiGatewayException(
        kind: GeminiGatewayFailureKind.unknown,
        message: error.toString(),
        statusCode: 500,
      );
      if (prompt != null) {
        _emitRequestFailedAnalytics(request: prompt, route: route, error: gatewayError);
        _emitRequestRetriedAnalytics(
          request: prompt,
          route: route,
          tracker: retryTracker,
          succeeded: false,
          error: gatewayError,
        );
        await _logRetryOutcome(
          category: 'responses',
          route: route,
          request: prompt,
          tracker: retryTracker,
          succeeded: false,
          error: gatewayError,
        );
      }
      await _logFailure(
        category: 'responses',
        route: route,
        message: error.toString(),
        stackTrace: stackTrace,
        details: _failureContextPayload(prompt: prompt, error: gatewayError),
      );
      return _errorResponse(500, 'proxy_error', error.toString());
    }
  }

  Future<Map<String, Object?>> _executeNonStreamRequest(
    UnifiedPromptRequest request, {
    _RequestRetryTracker? retryTracker,
  }) async {
    final route = _routeForSource(request.source);
    final triedIds = <String>{};
    GeminiGatewayException? lastError;
    while (true) {
      final account = _pool.select(request.model, excludedIds: triedIds);
      if (account == null) {
        throw lastError ??
            GeminiGatewayException(
              kind: GeminiGatewayFailureKind.unknown,
              message: 'No healthy account is available for `${request.model}`.',
              statusCode: 503,
            );
      }

      triedIds.add(account.id);
      _pool.markUsed(account);
      await _publishAccounts();

      try {
        final maskedAccountEmail = LogSanitizer.maskEmail(account.email);
        final accountLabel = LogSanitizer.sanitizeText(account.label).trim();
        final accountLabelSuffix = accountLabel.isNotEmpty && accountLabel != maskedAccountEmail
            ? ' ($accountLabel)'
            : '';
        await _logTrace(
          category: request.source,
          route: route,
          message: 'Using account `$maskedAccountEmail`$accountLabelSuffix for `${request.model}`',
          details: _requestContextPayload(prompt: request),
        );
        final payload = await _client.generateContent(
          account: account,
          request: request,
          onRetry: (event) {
            retryTracker?.recordUpstreamRetry(event);
            unawaited(
              _logRetryAttempt(
                category: request.source,
                route: route,
                request: request,
                tracker: retryTracker,
                event: event,
              ),
            );
          },
        );
        _requestCount += 1;
        if (_pool.markSuccess(account)) {
          await _publishAccounts();
        }
        _publishStatus();
        _emitRequestSucceededAnalytics(request: request, route: route);
        return payload;
      } on GeminiGatewayException catch (error) {
        lastError = error;
        _registerFailure(account, request.model, error);
        if (!_shouldRetry(error.kind)) {
          rethrow;
        }
        retryTracker?.recordAccountFailover(error);
        await _logAccountFailover(
          category: request.source,
          route: route,
          request: request,
          tracker: retryTracker,
          error: error,
        );
      } catch (error, stackTrace) {
        await _logFailure(
          category: request.source,
          route: _routeForSource(request.source),
          message: error.toString(),
          stackTrace: stackTrace,
          details: _failureContextPayload(prompt: request),
        );
        rethrow;
      }
    }
  }

  Future<Stream<List<int>>> _executeStreamRequest(
    UnifiedPromptRequest request, {
    required String route,
    _RequestRetryTracker? retryTracker,
    required List<Map<String, Object?>> Function(Map<String, Object?> payload, bool includePrelude)
    mapper,
    required String Function() doneEvent,
  }) async {
    final triedIds = <String>{};
    GeminiGatewayException? lastError;
    while (true) {
      final account = _pool.select(request.model, excludedIds: triedIds);
      if (account == null) {
        throw lastError ??
            GeminiGatewayException(
              kind: GeminiGatewayFailureKind.unknown,
              message: 'No healthy account is available for `${request.model}`.',
              statusCode: 503,
            );
      }
      triedIds.add(account.id);
      _pool.markUsed(account);
      await _publishAccounts();

      try {
        final upstream = await _client.generateContentStream(
          account: account,
          request: request,
          onRetry: (event) {
            retryTracker?.recordUpstreamRetry(event);
            unawaited(
              _logRetryAttempt(
                category: request.source,
                route: route,
                request: request,
                tracker: retryTracker,
                event: event,
              ),
            );
          },
        );
        final stream = () async* {
          var includePrelude = true;
          Map<String, Object?> lastPayload = const <String, Object?>{};
          var emittedEventCount = 0;
          var completed = false;
          var failed = false;
          try {
            await for (final payload in upstream) {
              lastPayload = payload;
              for (final event in mapper(payload, includePrelude)) {
                includePrelude = false;
                emittedEventCount += 1;
                yield utf8.encode(encodeSseEvent(event));
              }
            }
            for (final event in mapper({...lastPayload, 'final_chunk': true}, includePrelude)) {
              emittedEventCount += 1;
              yield utf8.encode(encodeSseEvent(event));
            }
            final done = doneEvent();
            if (done.isNotEmpty) {
              emittedEventCount += 1;
              yield utf8.encode(done);
            }
            completed = true;
            _requestCount += 1;
            if (_pool.markSuccess(account)) {
              await _publishAccounts();
            }
            _publishStatus();
            _emitRequestSucceededAnalytics(request: request, route: route);
            await _logRetryOutcome(
              category: request.source,
              route: route,
              request: request,
              tracker: retryTracker,
              succeeded: true,
            );
            _emitRequestRetriedAnalytics(
              request: request,
              route: route,
              tracker: retryTracker,
              succeeded: true,
            );
          } on GeminiGatewayException catch (error, stackTrace) {
            failed = true;
            _registerFailure(account, request.model, error);
            _emitRequestFailedAnalytics(request: request, route: route, error: error);
            _emitRequestRetriedAnalytics(
              request: request,
              route: route,
              tracker: retryTracker,
              succeeded: false,
              error: error,
            );
            await _logRetryOutcome(
              category: request.source,
              route: route,
              request: request,
              tracker: retryTracker,
              succeeded: false,
              error: error,
            );
            await _logFailure(
              category: request.source,
              route: route,
              message: error.message,
              stackTrace: stackTrace,
              details: _failureContextPayload(prompt: request, error: error),
            );
            for (final event in _streamErrorEvents(route: route, request: request, error: error)) {
              yield utf8.encode(event);
            }
          } catch (error, stackTrace) {
            failed = true;
            final gatewayError = GeminiGatewayException(
              kind: GeminiGatewayFailureKind.unknown,
              message: error.toString(),
              statusCode: 500,
            );
            _registerFailure(account, request.model, gatewayError);
            _emitRequestFailedAnalytics(request: request, route: route, error: gatewayError);
            _emitRequestRetriedAnalytics(
              request: request,
              route: route,
              tracker: retryTracker,
              succeeded: false,
              error: gatewayError,
            );
            await _logRetryOutcome(
              category: request.source,
              route: route,
              request: request,
              tracker: retryTracker,
              succeeded: false,
              error: gatewayError,
            );
            await _logFailure(
              category: request.source,
              route: route,
              message: gatewayError.message,
              stackTrace: stackTrace,
              details: _failureContextPayload(prompt: request, error: gatewayError),
            );
            for (final event in _streamErrorEvents(
              route: route,
              request: request,
              error: gatewayError,
            )) {
              yield utf8.encode(event);
            }
          } finally {
            if (!completed && !failed) {
              await _logStreamClientAbort(
                category: request.source,
                route: route,
                model: request.model,
                emittedEventCount: emittedEventCount,
                payload: lastPayload,
                details: _requestContextPayload(prompt: request),
              );
            }
            if ((completed || failed) && lastPayload.isNotEmpty) {
              await _logResponsePreview(
                category: request.source,
                route: route,
                payload: lastPayload,
                details: _requestContextPayload(prompt: request),
              );
            }
          }
        }();
        return stream;
      } on GeminiGatewayException catch (error) {
        lastError = error;
        _registerFailure(account, request.model, error);
        if (!_shouldRetry(error.kind)) {
          rethrow;
        }
        retryTracker?.recordAccountFailover(error);
        await _logAccountFailover(
          category: request.source,
          route: route,
          request: request,
          tracker: retryTracker,
          error: error,
        );
      }
    }
  }

  void _registerFailure(
    ProxyRuntimeAccount account,
    String requestedModel,
    GeminiGatewayException error,
  ) {
    switch (error.kind) {
      case GeminiGatewayFailureKind.auth:
        _pool.markAuthFailure(account, cooldown: error.retryAfter);
        break;
      case GeminiGatewayFailureKind.quota:
        if (_settings?['mark_429_as_unhealthy'] == true) {
          _pool.markQuotaFailure(
            account,
            quotaSnapshot: error.quotaSnapshot,
            cooldown: error.retryAfter,
          );
        } else {
          account.errorCount += 1;
          account.lastQuotaSnapshot = error.quotaSnapshot ?? account.lastQuotaSnapshot;
        }
        break;
      case GeminiGatewayFailureKind.capacity:
        _pool.markCapacityFailure(account, cooldown: error.retryAfter);
        break;
      case GeminiGatewayFailureKind.unsupportedModel:
        _pool.markUnsupportedModel(account, requestedModel);
        break;
      case GeminiGatewayFailureKind.invalidRequest:
      case GeminiGatewayFailureKind.unknown:
        account.errorCount += 1;
        break;
    }
    _publishAccounts();
  }

  bool _shouldRetry(GeminiGatewayFailureKind kind) {
    return kind == GeminiGatewayFailureKind.auth ||
        kind == GeminiGatewayFailureKind.quota ||
        kind == GeminiGatewayFailureKind.capacity ||
        kind == GeminiGatewayFailureKind.unsupportedModel;
  }

  Response? _authorizeRequest(Request request) {
    if (_settings == null) {
      return _errorResponse(503, 'service_unavailable', 'Proxy is not configured yet.');
    }
    if (_settings?['api_key_required'] == false) {
      return null;
    }
    final expectedKey = _settings?['api_key'] as String? ?? '';
    final authorization = request.headers['authorization'] ?? '';
    if (authorization != 'Bearer $expectedKey') {
      return _errorResponse(401, 'invalid_api_key', 'Missing or invalid Bearer token.');
    }
    return null;
  }

  Future<Map<String, Object?>?> _readJson(Request request) async {
    try {
      final body = await _readRequestBody(request);
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded.cast<String, Object?>();
      }
      return null;
    } on _RequestBodyTooLargeException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<String> _readRequestBody(Request request) async {
    final declaredLength = request.contentLength;
    if (declaredLength != null && declaredLength > _maxRequestBodyBytes) {
      throw const _RequestBodyTooLargeException();
    }

    final chunks = <int>[];
    await for (final chunk in request.read()) {
      chunks.addAll(chunk);
      if (chunks.length > _maxRequestBodyBytes) {
        throw const _RequestBodyTooLargeException();
      }
    }

    return utf8.decode(chunks);
  }

  Future<void> _logRequest(String category, Request request, Map<String, Object?> body) async {
    final verbosity = (_settings?['logging_verbosity'] as String?) ?? 'normal';
    if (verbosity == 'quiet') {
      return;
    }
    final masked = jsonEncode(LogSanitizer.sanitizeJsonValue(body));
    _sendPort.send({
      'type': 'log',
      'payload': {
        'id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'info',
        'category': category,
        'route': request.requestedUri.path,
        'message': LogSanitizer.sanitizeText('Request received'),
        'masked_payload': masked,
        'raw_payload': verbosity == 'verbose' && _unsafeRawLoggingEnabled ? jsonEncode(body) : null,
      },
    });
  }

  Future<void> _logFailure({
    required String category,
    required String route,
    required String message,
    required StackTrace stackTrace,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    final verbosity = (_settings?['logging_verbosity'] as String?) ?? 'normal';
    _sendPort.send({
      'type': 'log',
      'payload': {
        'id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'error',
        'category': category,
        'route': route,
        'message': LogSanitizer.sanitizeText(message),
        'masked_payload': details.isEmpty ? null : jsonEncode(details),
        'raw_payload': verbosity == 'verbose' && _unsafeRawLoggingEnabled
            ? stackTrace.toString()
            : null,
      },
    });
  }

  Future<void> _logTrace({
    required String category,
    required String route,
    required String message,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    final verbosity = (_settings?['logging_verbosity'] as String?) ?? 'normal';
    if (verbosity == 'quiet') {
      return;
    }
    _sendPort.send({
      'type': 'log',
      'payload': {
        'id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'info',
        'category': category,
        'route': route,
        'message': LogSanitizer.sanitizeText(message),
        'masked_payload': details.isEmpty ? null : jsonEncode(details),
        'raw_payload': null,
      },
    });
  }

  Future<void> _logPromptSummary(UnifiedPromptRequest prompt, {required String route}) async {
    final verbosity = (_settings?['logging_verbosity'] as String?) ?? 'normal';
    if (verbosity == 'quiet') {
      return;
    }

    _sendPort.send({
      'type': 'log',
      'payload': {
        'id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'info',
        'category': prompt.source,
        'route': route,
        'message': 'Parsed request',
        'masked_payload': jsonEncode({
          ..._requestContextPayload(prompt: prompt),
          'turns': prompt.turns.length,
          'tools': prompt.tools.length,
          'has_system_instruction': prompt.systemInstruction != null,
          'requested_max_output_tokens': prompt.maxOutputTokens,
          'effective_max_output_tokens': prompt.maxOutputTokens ?? defaultGeminiMaxOutputTokens,
          'stop_sequences': prompt.stopSequences,
          'json_mode': prompt.jsonMode,
        }),
        'raw_payload': null,
      },
    });
  }

  Future<void> _logResponsePreview({
    required String category,
    required String route,
    required Map<String, Object?> payload,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    final verbosity = (_settings?['logging_verbosity'] as String?) ?? 'normal';
    if (verbosity == 'quiet') {
      return;
    }

    final maskedSummary = <String, Object?>{...details, ..._responseSummaryPayload(payload)};
    final maskedPayload = maskedSummary.isEmpty ? null : jsonEncode(maskedSummary);

    _sendPort.send({
      'type': 'log',
      'payload': {
        'id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'info',
        'category': category,
        'route': route,
        'message': 'Response completed',
        'masked_payload': maskedPayload,
        'raw_payload': verbosity == 'verbose' && _unsafeRawLoggingEnabled
            ? jsonEncode(payload)
            : null,
      },
    });
  }

  Future<void> _logStreamClientAbort({
    required String category,
    required String route,
    required String model,
    required int emittedEventCount,
    required Map<String, Object?> payload,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    final verbosity = (_settings?['logging_verbosity'] as String?) ?? 'normal';
    final maskedPayload = jsonEncode({
      ...details,
      'model': model,
      'stream_started': payload.isNotEmpty,
      'events_emitted': emittedEventCount,
      ..._responseSummaryPayload(payload),
    });
    final rawPayload = verbosity == 'verbose' && _unsafeRawLoggingEnabled && payload.isNotEmpty
        ? jsonEncode(payload)
        : null;
    _sendPort.send({
      'type': 'log',
      'payload': {
        'id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'warning',
        'category': category,
        'route': route,
        'message': 'Streaming response aborted by client',
        'masked_payload': maskedPayload,
        'raw_payload': rawPayload,
      },
    });
  }

  Future<void> _logRetryAttempt({
    required String category,
    required String route,
    required UnifiedPromptRequest request,
    required GeminiRetryEvent event,
    _RequestRetryTracker? tracker,
  }) async {
    final verbosity = (_settings?['logging_verbosity'] as String?) ?? 'normal';
    if (verbosity != 'verbose' || tracker == null) {
      return;
    }

    _sendPort.send({
      'type': 'log',
      'payload': {
        'id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'info',
        'category': category,
        'route': route,
        'message': 'Retry scheduled',
        'masked_payload': jsonEncode(tracker.toAttemptPayload(request: request, event: event)),
        'raw_payload': null,
      },
    });
  }

  Future<void> _logAccountFailover({
    required String category,
    required String route,
    required UnifiedPromptRequest request,
    required GeminiGatewayException error,
    _RequestRetryTracker? tracker,
  }) async {
    final verbosity = (_settings?['logging_verbosity'] as String?) ?? 'normal';
    if (verbosity != 'verbose' || tracker == null) {
      return;
    }

    _sendPort.send({
      'type': 'log',
      'payload': {
        'id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'info',
        'category': category,
        'route': route,
        'message': 'Retrying with another account',
        'masked_payload': jsonEncode(
          tracker.toAccountFailoverPayload(request: request, error: error),
        ),
        'raw_payload': null,
      },
    });
  }

  Future<void> _logRetryOutcome({
    required String category,
    required String route,
    required UnifiedPromptRequest request,
    required bool succeeded,
    GeminiGatewayException? error,
    _RequestRetryTracker? tracker,
  }) async {
    if (tracker == null || !tracker.hasRetries) {
      return;
    }

    _sendPort.send({
      'type': 'log',
      'payload': {
        'id': _uuid.v4(),
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'warning',
        'category': category,
        'route': route,
        'message': succeeded ? 'Request succeeded after retries' : 'Request failed after retries',
        'masked_payload': jsonEncode(
          tracker.toOutcomePayload(
            request: request,
            outcome: succeeded ? 'succeeded' : 'failed',
            error: error,
          ),
        ),
        'raw_payload': null,
      },
    });
  }

  Map<String, Object?> _requestContextPayload({UnifiedPromptRequest? prompt}) {
    if (prompt == null) {
      return const <String, Object?>{};
    }

    return {'request_id': prompt.requestId, 'model': prompt.model, 'stream': prompt.stream};
  }

  Map<String, Object?> _failureContextPayload({
    UnifiedPromptRequest? prompt,
    GeminiGatewayException? error,
  }) {
    return {
      ..._requestContextPayload(prompt: prompt),
      if (error != null) ..._gatewayErrorContext(error),
    };
  }

  Map<String, Object?> _gatewayErrorContext(GeminiGatewayException error) {
    return {
      'error_kind': error.kind.name,
      'status_code': error.statusCode,
      if (error.detail != null) 'error_detail': error.detail!.name,
      if (error.upstreamReason?.trim().isNotEmpty == true)
        'upstream_reason': error.upstreamReason!.trim(),
      if (error.retryAfter != null) 'retry_after_ms': error.retryAfter!.inMilliseconds,
      if (error.actionUrl?.trim().isNotEmpty == true) 'has_action_url': true,
      if (error.quotaSnapshot?.trim().isNotEmpty == true) 'has_quota_snapshot': true,
    };
  }

  Map<String, Object?> _responseSummaryPayload(Map<String, Object?> payload) {
    final preview = OpenAiResponseMapper.currentText(payload);
    final reasoningText = OpenAiResponseMapper.currentReasoningText(payload);
    final finishReason = OpenAiResponseMapper.currentFinishReason(payload);
    final toolCallCount = OpenAiResponseMapper.currentToolCallCount(payload);
    final traceId = OpenAiResponseMapper.currentTraceId(payload);
    final upstreamResponseId = OpenAiResponseMapper.currentUpstreamResponseId(payload);
    final modelVersion = OpenAiResponseMapper.currentModelVersion(payload);
    final promptTokens = OpenAiResponseMapper.currentPromptTokenCount(payload);
    final completionTokens = OpenAiResponseMapper.currentCompletionTokenCount(payload);
    final totalTokens = OpenAiResponseMapper.currentTotalTokenCount(payload);
    final cachedTokens = OpenAiResponseMapper.currentCachedTokenCount(payload);
    final reasoningTokens = OpenAiResponseMapper.currentReasoningTokenCount(payload);
    return {
      'finish_reason': finishReason,
      ...?_optionalMapEntry('trace_id', traceId),
      ...?_optionalMapEntry('upstream_response_id', upstreamResponseId),
      ...?_optionalMapEntry('upstream_model_version', modelVersion),
      ...?_optionalMapEntry('prompt_tokens', promptTokens),
      ...?_optionalMapEntry('completion_tokens', completionTokens),
      ...?_optionalMapEntry('total_tokens', totalTokens),
      ...?_optionalMapEntry('cached_tokens', cachedTokens),
      ...?_optionalMapEntry('reasoning_tokens', reasoningTokens),
      if (preview.isNotEmpty) 'output_text_chars': preview.length,
      if (reasoningText.isNotEmpty) 'reasoning_text_chars': reasoningText.length,
      if (toolCallCount > 0) 'tool_call_count': toolCallCount,
    };
  }

  Map<String, Object?>? _optionalMapEntry(String key, Object? value) {
    if (value == null) {
      return null;
    }
    return {key: value};
  }

  bool get _unsafeRawLoggingEnabled => _settings?['unsafe_raw_logging_enabled'] == true;

  Response _jsonResponse(
    Map<String, Object?> body, {
    int status = 200,
    Map<String, String>? headers,
  }) {
    return Response(
      status,
      headers: {'content-type': 'application/json', ...?headers},
      body: jsonEncode(body),
    );
  }

  Response _errorResponse(int status, String code, String message, {Map<String, String>? headers}) {
    return _jsonResponse(
      {
        'error': {'message': message, 'type': code, 'code': code},
      },
      status: status,
      headers: headers,
    );
  }

  Response _gatewayErrorResponse(GeminiGatewayException error) {
    final headers = <String, String>{};
    if (_retryAfterHeaderValue(error.retryAfter) case final retryAfterHeader?) {
      headers[HttpHeaders.retryAfterHeader] = retryAfterHeader;
    }
    return _errorResponse(
      _statusForFailure(error.kind),
      'proxy_error',
      error.message,
      headers: headers,
    );
  }

  Map<String, String> _sseHeaders() {
    return {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache',
      'connection': 'keep-alive',
    };
  }

  String? _retryAfterHeaderValue(Duration? retryAfter) {
    if (retryAfter == null || retryAfter <= Duration.zero) {
      return null;
    }
    return retryAfter.inSeconds <= 0 ? '1' : retryAfter.inSeconds.ceil().toString();
  }

  int _statusForFailure(GeminiGatewayFailureKind kind) {
    switch (kind) {
      case GeminiGatewayFailureKind.auth:
        return 401;
      case GeminiGatewayFailureKind.quota:
        return 429;
      case GeminiGatewayFailureKind.capacity:
        return 503;
      case GeminiGatewayFailureKind.unsupportedModel:
      case GeminiGatewayFailureKind.invalidRequest:
        return 400;
      case GeminiGatewayFailureKind.unknown:
        return 500;
    }
  }

  Iterable<String> _streamErrorEvents({
    required String route,
    required UnifiedPromptRequest request,
    required GeminiGatewayException error,
  }) sync* {
    final errorBody = {
      'message': error.message,
      'type': 'proxy_error',
      'code': 'proxy_error',
      'status': _statusForFailure(error.kind),
    };

    if (route == '/v1/responses') {
      yield encodeSseEvent({
        'type': 'response.failed',
        'response': {
          'id': 'resp_${request.requestId}',
          'object': 'response',
          'status': 'failed',
          'model': request.model,
        },
        'error': errorBody,
      });
      return;
    }

    yield encodeSseEvent({'error': errorBody});
    yield encodeSseEvent('[DONE]');
  }

  Future<void> _publishAccounts() async {
    _sendPort.send({
      'type': 'accounts_runtime_updated',
      'payload': [for (final account in _pool.accounts) account.toProfile().toDatabaseMap()],
    });
  }

  void _emitRequestSucceededAnalytics({
    required UnifiedPromptRequest request,
    required String route,
  }) {
    _sendPort.send({
      'type': 'analytics',
      'payload': {
        'kind': 'proxy_request_succeeded',
        'route': route,
        'model': request.model,
        'stream': request.stream,
      },
    });
  }

  void _emitRequestFailedAnalytics({
    required UnifiedPromptRequest request,
    required String route,
    required GeminiGatewayException error,
  }) {
    _sendPort.send({
      'type': 'analytics',
      'payload': {
        'kind': 'proxy_request_failed',
        'route': route,
        'model': request.model,
        'stream': request.stream,
        'error_kind': error.kind.name,
        'status_code': error.statusCode,
        ..._gatewayErrorContext(error),
      },
    });
    _emitCompatibilityIssueAnalytics(request: request, route: route, error: error);
  }

  void _emitRequestRetriedAnalytics({
    required UnifiedPromptRequest request,
    required String route,
    required bool succeeded,
    GeminiGatewayException? error,
    _RequestRetryTracker? tracker,
  }) {
    if (tracker == null || !tracker.hasRetries) {
      return;
    }

    _sendPort.send({
      'type': 'analytics',
      'payload': {
        'kind': 'proxy_request_retried',
        'route': route,
        'model': request.model,
        'stream': request.stream,
        ...tracker.toAnalyticsPayload(outcome: succeeded ? 'succeeded' : 'failed', error: error),
        if (error != null) ..._gatewayErrorContext(error),
      },
    });
  }

  void _emitCompatibilityIssueAnalytics({
    required UnifiedPromptRequest request,
    required String route,
    required GeminiGatewayException error,
  }) {
    final issueKind = _compatibilityIssueKind(error);
    if (issueKind == null) {
      return;
    }

    _sendPort.send({
      'type': 'analytics',
      'payload': {
        'kind': 'upstream_compatibility_issue',
        'issue_kind': issueKind,
        'route': route,
        'model': request.model,
        'stream': request.stream,
        'error_kind': error.kind.name,
        'status_code': error.statusCode,
        ..._gatewayErrorContext(error),
      },
    });
  }

  String? _compatibilityIssueKind(GeminiGatewayException error) {
    if (error.kind == GeminiGatewayFailureKind.unsupportedModel) {
      return 'unsupported_model';
    }

    if (error.kind == GeminiGatewayFailureKind.invalidRequest) {
      return switch (error.detail) {
        GeminiGatewayFailureDetail.projectIdMissing => 'project_id_missing',
        GeminiGatewayFailureDetail.projectConfiguration => 'project_configuration',
        GeminiGatewayFailureDetail.reasoningConfigUnsupported => 'reasoning_config_unsupported',
        _ => null,
      };
    }

    if (error.kind == GeminiGatewayFailureKind.auth) {
      return switch (error.detail) {
        GeminiGatewayFailureDetail.accountVerificationRequired => 'account_verification_required',
        GeminiGatewayFailureDetail.projectIdMissing => 'project_id_missing',
        GeminiGatewayFailureDetail.projectConfiguration => 'project_configuration',
        _ => null,
      };
    }

    if (error.message.toLowerCase().contains('no healthy account is available')) {
      return 'no_healthy_account_available';
    }

    return null;
  }

  String _routeForSource(String source) {
    return source == 'responses' ? '/v1/responses' : '/v1/chat/completions';
  }

  int _healthyAccountCount() {
    return _pool.accounts.where((account) => account.enabled && !account.isCoolingDown).length;
  }

  bool _shouldRestartServerForConfigurationChange(
    Map<String, Object?>? previousSettings,
    Map<String, Object?>? nextSettings,
  ) {
    if (previousSettings == null || nextSettings == null) {
      return false;
    }

    final previousHost = _effectiveBindHost(previousSettings);
    final nextHost = _effectiveBindHost(nextSettings);
    final previousPort = previousSettings['port'] as int? ?? 3000;
    final nextPort = nextSettings['port'] as int? ?? 3000;
    return previousHost != nextHost || previousPort != nextPort;
  }

  String _effectiveBindHost(Map<String, Object?> settings) {
    final allowLan = settings['allow_lan'] == true;
    if (allowLan) {
      return '0.0.0.0';
    }
    return settings['host'] as String? ?? '127.0.0.1';
  }

  String? resolveCorsOrigin(String? origin) {
    return resolveProxyCorsOrigin(
      origin: origin,
      allowLan: _allowLan,
      configuredHost: _configuredHost,
    );
  }

  Map<String, String> corsHeaders(
    String? allowedOrigin, {
    String? requestedHeaders,
    String? requestedPrivateNetwork,
  }) {
    return buildProxyCorsHeaders(
      allowedOrigin: allowedOrigin,
      requestedHeaders: requestedHeaders,
      requestedPrivateNetwork: requestedPrivateNetwork,
    );
  }

  void _publishStatus() {
    _sendPort.send({
      'type': 'status',
      'payload': {
        'ready': _settings != null,
        'running': _server != null,
        'bound_host': _server?.address.address ?? (_settings?['host'] as String? ?? '127.0.0.1'),
        'port': _server?.port ?? (_settings?['port'] as int? ?? 3000),
        'started_at': _startedAt?.toIso8601String(),
        'request_count': _requestCount,
        'active_accounts': _pool.accounts.where((account) => account.enabled).length,
        'healthy_accounts': _healthyAccountCount(),
        'last_error': _lastRuntimeError,
      },
    });
  }
}

Middleware _errorMiddleware(_ProxyIsolateHost host) {
  return (innerHandler) {
    return (request) async {
      try {
        return await innerHandler(request);
      } catch (error, stackTrace) {
        await host._logFailure(
          category: 'proxy.unhandled',
          route: request.requestedUri.path,
          message: error.toString(),
          stackTrace: stackTrace,
        );
        return host._errorResponse(500, 'proxy_error', error.toString());
      }
    };
  };
}

Middleware _corsMiddleware(_ProxyIsolateHost host) {
  return (innerHandler) {
    return (request) async {
      final allowedOrigin = host.resolveCorsOrigin(request.headers['origin']);
      final requestedHeaders = request.headers['access-control-request-headers'];
      final requestedPrivateNetwork = request.headers['access-control-request-private-network'];
      if (request.headers.containsKey('origin') && allowedOrigin == null) {
        return Response.forbidden(
          jsonEncode({
            'error': {
              'message': 'This origin is not allowed to access the proxy.',
              'type': 'forbidden_origin',
              'code': 'forbidden_origin',
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.method == 'OPTIONS') {
        return Response.ok(
          '',
          headers: host.corsHeaders(
            allowedOrigin,
            requestedHeaders: requestedHeaders,
            requestedPrivateNetwork: requestedPrivateNetwork,
          ),
        );
      }

      final response = await innerHandler(request);
      if (allowedOrigin == null) {
        return response;
      }
      return response.change(
        headers: {
          ...response.headers,
          ...host.corsHeaders(
            allowedOrigin,
            requestedHeaders: requestedHeaders,
            requestedPrivateNetwork: requestedPrivateNetwork,
          ),
        },
      );
    };
  };
}

class _RequestRetryTracker {
  _RequestRetryTracker({required this.requestId, required this.model, required this.stream});

  factory _RequestRetryTracker.fromRequest(UnifiedPromptRequest request) {
    return _RequestRetryTracker(
      requestId: request.requestId,
      model: request.model,
      stream: request.stream,
    );
  }

  final String requestId;
  final String model;
  final bool stream;

  int upstreamRetryCount = 0;
  int accountFailoverCount = 0;
  Duration totalRetryDelay = Duration.zero;
  final Set<String> _retryKinds = <String>{};

  bool get hasRetries => retryCount > 0;
  int get retryCount => upstreamRetryCount + accountFailoverCount;

  void recordUpstreamRetry(GeminiRetryEvent event) {
    upstreamRetryCount += 1;
    totalRetryDelay += event.delay;
    _retryKinds.add(event.error.kind.name);
  }

  void recordAccountFailover(GeminiGatewayException error) {
    accountFailoverCount += 1;
    _retryKinds.add(error.kind.name);
  }

  Map<String, Object?> toAttemptPayload({
    required UnifiedPromptRequest request,
    required GeminiRetryEvent event,
  }) {
    return {
      'request_id': requestId,
      'model': request.model,
      'stream': request.stream,
      'retry_source': 'upstream',
      'retry_attempt': event.attempt,
      'max_retries': event.maxRetries,
      'delay_ms': event.delay.inMilliseconds,
      'error_kind': event.error.kind.name,
      'status_code': event.error.statusCode,
      ..._errorContext(event.error),
    };
  }

  Map<String, Object?> toAccountFailoverPayload({
    required UnifiedPromptRequest request,
    required GeminiGatewayException error,
  }) {
    return {
      'request_id': requestId,
      'model': request.model,
      'stream': request.stream,
      'retry_source': 'account_failover',
      'account_failover_count': accountFailoverCount,
      'error_kind': error.kind.name,
      'status_code': error.statusCode,
      ..._errorContext(error),
    };
  }

  Map<String, Object?> toOutcomePayload({
    required UnifiedPromptRequest request,
    required String outcome,
    GeminiGatewayException? error,
  }) {
    return {
      'request_id': requestId,
      'model': request.model,
      'stream': request.stream,
      'outcome': outcome,
      'retry_count': retryCount,
      'upstream_retry_count': upstreamRetryCount,
      'account_failover_count': accountFailoverCount,
      if (_retryKinds.isNotEmpty) 'retry_kinds': _retryKinds.toList(growable: false),
      if (totalRetryDelay > Duration.zero) 'retry_delay_ms': totalRetryDelay.inMilliseconds,
      if (error != null) 'final_error_kind': error.kind.name,
      if (error != null) 'final_status_code': error.statusCode,
      if (error != null) ..._prefixedErrorContext('final_', error),
    };
  }

  Map<String, Object?> toAnalyticsPayload({
    required String outcome,
    GeminiGatewayException? error,
  }) {
    return {
      'outcome': outcome,
      'retry_count': retryCount,
      'upstream_retry_count': upstreamRetryCount,
      'account_failover_count': accountFailoverCount,
      if (_retryKinds.isNotEmpty) 'retry_kinds': _retryKinds.join(','),
      if (totalRetryDelay > Duration.zero) 'retry_delay_ms': totalRetryDelay.inMilliseconds,
      if (error != null) 'status_code': error.statusCode,
      if (error != null) ..._errorContext(error),
    };
  }

  static Map<String, Object?> _errorContext(GeminiGatewayException error) {
    return {
      if (error.detail != null) 'error_detail': error.detail!.name,
      if (error.upstreamReason?.trim().isNotEmpty == true)
        'upstream_reason': error.upstreamReason!.trim(),
      if (error.retryAfter != null) 'retry_after_ms': error.retryAfter!.inMilliseconds,
      if (error.actionUrl?.trim().isNotEmpty == true) 'has_action_url': true,
    };
  }

  static Map<String, Object?> _prefixedErrorContext(String prefix, GeminiGatewayException error) {
    return {
      if (error.detail != null) '${prefix}error_detail': error.detail!.name,
      if (error.upstreamReason?.trim().isNotEmpty == true)
        '${prefix}upstream_reason': error.upstreamReason!.trim(),
      if (error.retryAfter != null) '${prefix}retry_after_ms': error.retryAfter!.inMilliseconds,
      if (error.actionUrl?.trim().isNotEmpty == true) '${prefix}has_action_url': true,
    };
  }
}

class _RequestBodyTooLargeException implements Exception {
  const _RequestBodyTooLargeException();

  String get message =>
      'Request body is too large. The current limit is ${_maxRequestBodyBytes ~/ (1024 * 1024)} MB.';

  @override
  String toString() => message;
}
