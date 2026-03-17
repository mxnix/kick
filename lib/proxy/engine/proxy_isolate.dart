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

    final body = await _readJson(request);
    if (body == null) {
      return _errorResponse(400, 'invalid_request_error', 'Request body must be valid JSON.');
    }
    final requestId = _uuid.v4().replaceAll('-', '');
    UnifiedPromptRequest? prompt;

    try {
      final resolvedPrompt = prompt = OpenAiRequestParser.parseChatRequest(
        body,
        requestId: requestId,
      );
      if (!_catalog.contains(resolvedPrompt.model)) {
        return _errorResponse(
          400,
          'model_not_found',
          'Model `${resolvedPrompt.model}` is not available in KiCk.',
        );
      }

      await _logRequest('chat.completions', request, body);
      await _logPromptSummary(resolvedPrompt, route: request.requestedUri.path);
      if (resolvedPrompt.stream) {
        await _logTrace(
          category: 'chat.completions',
          route: request.requestedUri.path,
          message: 'Dispatching streaming request to Gemini gateway',
        );
        var previousText = '';
        var previousReasoningText = '';
        var previousToolCallCount = 0;
        final stream = await _executeStreamRequest(
          resolvedPrompt,
          route: '/v1/chat/completions',
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
        route: request.requestedUri.path,
        message: 'Dispatching request to Gemini gateway',
      );
      final payload = await _executeNonStreamRequest(resolvedPrompt);
      await _logTrace(
        category: 'chat.completions',
        route: request.requestedUri.path,
        message: 'Gemini gateway returned a payload',
      );
      final responseBody = OpenAiResponseMapper.toChatCompletion(
        requestId: resolvedPrompt.requestId,
        model: resolvedPrompt.model,
        payload: payload,
      );
      await _logTrace(
        category: 'chat.completions',
        route: request.requestedUri.path,
        message: 'Mapped Gemini payload to OpenAI chat completion',
      );
      await _logResponsePreview(
        category: 'chat.completions',
        route: request.requestedUri.path,
        payload: payload,
      );
      return _jsonResponse(responseBody);
    } on _RequestBodyTooLargeException catch (error, stackTrace) {
      await _logFailure(
        category: 'chat.completions',
        route: request.requestedUri.path,
        message: error.message,
        stackTrace: stackTrace,
      );
      return _errorResponse(413, 'request_too_large', error.message);
    } on FormatException catch (error, stackTrace) {
      await _logFailure(
        category: 'chat.completions',
        route: request.requestedUri.path,
        message: error.message,
        stackTrace: stackTrace,
      );
      return _errorResponse(400, 'invalid_request_error', error.message);
    } on GeminiGatewayException catch (error, stackTrace) {
      if (prompt != null) {
        _emitRequestFailedAnalytics(
          request: prompt,
          route: request.requestedUri.path,
          error: error,
        );
      }
      await _logFailure(
        category: 'chat.completions',
        route: request.requestedUri.path,
        message: error.message,
        stackTrace: stackTrace,
      );
      return _gatewayErrorResponse(error);
    } catch (error, stackTrace) {
      if (prompt != null) {
        _emitRequestFailedAnalytics(
          request: prompt,
          route: request.requestedUri.path,
          error: GeminiGatewayException(
            kind: GeminiGatewayFailureKind.unknown,
            message: error.toString(),
            statusCode: 500,
          ),
        );
      }
      await _logFailure(
        category: 'chat.completions',
        route: request.requestedUri.path,
        message: error.toString(),
        stackTrace: stackTrace,
      );
      return _errorResponse(500, 'proxy_error', error.toString());
    }
  }

  Future<Response> _handleResponses(Request request) async {
    final authResult = _authorizeRequest(request);
    if (authResult != null) {
      return authResult;
    }

    final body = await _readJson(request);
    if (body == null) {
      return _errorResponse(400, 'invalid_request_error', 'Request body must be valid JSON.');
    }
    final requestId = _uuid.v4().replaceAll('-', '');
    UnifiedPromptRequest? prompt;

    try {
      final resolvedPrompt = prompt = OpenAiRequestParser.parseResponsesRequest(
        body,
        requestId: requestId,
      );
      if (!_catalog.contains(resolvedPrompt.model)) {
        return _errorResponse(
          400,
          'model_not_found',
          'Model `${resolvedPrompt.model}` is not available in KiCk.',
        );
      }

      await _logRequest('responses', request, body);
      await _logPromptSummary(resolvedPrompt, route: request.requestedUri.path);
      if (resolvedPrompt.stream) {
        await _logTrace(
          category: 'responses',
          route: request.requestedUri.path,
          message: 'Dispatching streaming request to Gemini gateway',
        );
        var previousText = '';
        var previousReasoningText = '';
        var previousToolCallCount = 0;
        var previousToolCallArguments = const <String>[];
        final stream = await _executeStreamRequest(
          resolvedPrompt,
          route: '/v1/responses',
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

      final payload = await _executeNonStreamRequest(resolvedPrompt);
      await _logResponsePreview(
        category: 'responses',
        route: request.requestedUri.path,
        payload: payload,
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
        route: request.requestedUri.path,
        message: error.message,
        stackTrace: stackTrace,
      );
      return _errorResponse(413, 'request_too_large', error.message);
    } on FormatException catch (error, stackTrace) {
      await _logFailure(
        category: 'responses',
        route: request.requestedUri.path,
        message: error.message,
        stackTrace: stackTrace,
      );
      return _errorResponse(400, 'invalid_request_error', error.message);
    } on GeminiGatewayException catch (error, stackTrace) {
      if (prompt != null) {
        _emitRequestFailedAnalytics(
          request: prompt,
          route: request.requestedUri.path,
          error: error,
        );
      }
      await _logFailure(
        category: 'responses',
        route: request.requestedUri.path,
        message: error.message,
        stackTrace: stackTrace,
      );
      return _gatewayErrorResponse(error);
    } catch (error, stackTrace) {
      if (prompt != null) {
        _emitRequestFailedAnalytics(
          request: prompt,
          route: request.requestedUri.path,
          error: GeminiGatewayException(
            kind: GeminiGatewayFailureKind.unknown,
            message: error.toString(),
            statusCode: 500,
          ),
        );
      }
      await _logFailure(
        category: 'responses',
        route: request.requestedUri.path,
        message: error.toString(),
        stackTrace: stackTrace,
      );
      return _errorResponse(500, 'proxy_error', error.toString());
    }
  }

  Future<Map<String, Object?>> _executeNonStreamRequest(UnifiedPromptRequest request) async {
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
        final route = _routeForSource(request.source);
        await _logTrace(
          category: request.source,
          route: route,
          message: 'Using account `${account.email}` for `${request.model}`',
        );
        final payload = await _client.generateContent(account: account, request: request);
        _requestCount += 1;
        _publishStatus();
        _emitRequestSucceededAnalytics(request: request, route: route);
        return payload;
      } on GeminiGatewayException catch (error) {
        lastError = error;
        _registerFailure(account, request.model, error);
        if (!_shouldRetry(error.kind)) {
          rethrow;
        }
      } catch (error, stackTrace) {
        await _logFailure(
          category: request.source,
          route: _routeForSource(request.source),
          message: error.toString(),
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }
  }

  Future<Stream<List<int>>> _executeStreamRequest(
    UnifiedPromptRequest request, {
    required String route,
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
        final upstream = await _client.generateContentStream(account: account, request: request);
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
            _publishStatus();
            _emitRequestSucceededAnalytics(request: request, route: route);
          } on GeminiGatewayException catch (error, stackTrace) {
            failed = true;
            _registerFailure(account, request.model, error);
            _emitRequestFailedAnalytics(request: request, route: route, error: error);
            await _logFailure(
              category: request.source,
              route: route,
              message: error.message,
              stackTrace: stackTrace,
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
            await _logFailure(
              category: request.source,
              route: route,
              message: gatewayError.message,
              stackTrace: stackTrace,
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
              );
            }
            if ((completed || failed) && lastPayload.isNotEmpty) {
              await _logResponsePreview(
                category: request.source,
                route: route,
                payload: lastPayload,
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
        'message': 'Request received',
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
        'message': message,
        'masked_payload': null,
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
        'message': message,
        'masked_payload': null,
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
          'model': prompt.model,
          'stream': prompt.stream,
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
  }) async {
    final verbosity = (_settings?['logging_verbosity'] as String?) ?? 'normal';
    if (verbosity == 'quiet') {
      return;
    }

    final maskedPayload = jsonEncode(_responseSummaryPayload(payload));

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
  }) async {
    final verbosity = (_settings?['logging_verbosity'] as String?) ?? 'normal';
    final maskedPayload = jsonEncode({
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

  Map<String, Object?> _responseSummaryPayload(Map<String, Object?> payload) {
    final preview = OpenAiResponseMapper.currentText(payload);
    final reasoningText = OpenAiResponseMapper.currentReasoningText(payload);
    final finishReason = _extractPayloadFinishReason(payload);
    final toolCallCount = OpenAiResponseMapper.currentToolCallCount(payload);
    final finishReasonEntry = finishReason == null
        ? const <String, Object?>{}
        : <String, Object?>{'finish_reason': finishReason};
    return {
      ...finishReasonEntry,
      if (preview.isNotEmpty) 'output_text_chars': preview.length,
      if (reasoningText.isNotEmpty) 'reasoning_text_chars': reasoningText.length,
      if (toolCallCount > 0) 'tool_call_count': toolCallCount,
    };
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
      },
    });
  }

  String _routeForSource(String source) {
    return source == 'responses' ? '/v1/responses' : '/v1/chat/completions';
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

  String? _extractPayloadFinishReason(Map<String, Object?> payload) {
    final response = ((payload['response'] as Map?) ?? payload).cast<String, Object?>();
    final candidates = (response['candidates'] as List?) ?? const [];
    if (candidates.isEmpty || candidates.first is! Map) {
      return null;
    }
    final candidate = (candidates.first as Map).cast<String, Object?>();
    final finishReason = candidate['finishReason'] as String?;
    return switch (finishReason) {
      'MAX_TOKENS' => 'length',
      'SAFETY' || 'RECITATION' => 'content_filter',
      'STOP' => 'stop',
      _ => finishReason?.toLowerCase(),
    };
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

class _RequestBodyTooLargeException implements Exception {
  const _RequestBodyTooLargeException();

  String get message =>
      'Request body is too large. The current limit is ${_maxRequestBodyBytes ~/ (1024 * 1024)} MB.';

  @override
  String toString() => message;
}
