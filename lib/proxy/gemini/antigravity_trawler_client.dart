import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'gemini_auth_constants.dart';

/// Exception thrown when a Trawler fetch operation fails.
class TrawlerException implements Exception {
  const TrawlerException({required this.statusCode, required this.message, this.isTimeout = false});

  final int statusCode;
  final String message;
  final bool isTimeout;

  @override
  String toString() => 'TrawlerException($statusCode, $message, timeout=$isTimeout)';
}

/// Client for fetching URL content via the Antigravity Trawler cache endpoint.
class AntigravityTrawlerClient {
  AntigravityTrawlerClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
    String? baseEndpoint,
    String? apiVersion,
  }) : _http = httpClient ?? http.Client(),
       _baseEndpoint = baseEndpoint ?? geminiCodeAssistEndpoint,
       _apiVersion = apiVersion ?? geminiCodeAssistApiVersion;

  final http.Client _http;
  final Duration timeout;
  final String _baseEndpoint;
  final String _apiVersion;

  /// Fetches URL content from the Trawler cache endpoint.
  ///
  /// Returns the HTML content body on success.
  /// Throws [TrawlerException] on failure (404, timeout, upstream error).
  Future<String> fetchUrl({
    required String url,
    required String accessToken,
    required String projectId,
    bool liveFetch = false,
  }) async {
    final requestUri = Uri.parse('$_baseEndpoint/$_apiVersion:fetchFromTrawlerCache');
    final body = jsonEncode({'url': url, 'liveFetch': liveFetch});

    final http.Response response;
    try {
      response = await _http
          .post(
            requestUri,
            headers: {
              HttpHeaders.authorizationHeader: 'Bearer $accessToken',
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.acceptHeader: 'application/json',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const TrawlerException(statusCode: 408, message: 'Request timeout', isTimeout: true);
    }

    if (response.statusCode == 200) {
      final Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        return response.body;
      }
      if (decoded is Map<String, dynamic>) {
        final content =
            decoded['content'] as String? ??
            decoded['htmlContent'] as String? ??
            decoded['body'] as String? ??
            response.body;
        return content;
      }
      return response.body;
    }

    if (response.statusCode == 404) {
      throw const TrawlerException(statusCode: 404, message: 'URL content not available in cache');
    }

    throw TrawlerException(
      statusCode: response.statusCode,
      message: 'Upstream failure: HTTP ${response.statusCode}',
    );
  }

  void dispose() {
    _http.close();
  }
}
