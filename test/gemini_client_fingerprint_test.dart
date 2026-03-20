import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kick/proxy/gemini/gemini_auth_constants.dart';
import 'package:kick/proxy/gemini/gemini_client_fingerprint.dart';

void main() {
  String expectedPlatform() {
    if (Platform.isWindows) {
      return 'win32';
    }
    if (Platform.isMacOS) {
      return 'darwin';
    }
    return Platform.operatingSystem.trim().isEmpty ? 'unknown' : Platform.operatingSystem;
  }

  String expectedArchitecture() {
    final abi = Abi.current().toString();
    final separatorIndex = abi.indexOf('_');
    if (separatorIndex == -1 || separatorIndex == abi.length - 1) {
      return abi;
    }
    return abi.substring(separatorIndex + 1);
  }

  test('builds the default Gemini CLI user agent with a terminal surface', () {
    expect(
      buildGeminiCliUserAgent('gemini-2.5-pro'),
      '$geminiCodeAssistUserAgentPrefix/$geminiCodeAssistCliVersion/gemini-2.5-pro '
      '(${expectedPlatform()}; ${expectedArchitecture()}; $geminiCodeAssistUserAgentSurface) '
      '$geminiCodeAssistNodeJsUserAgentSuffix',
    );
  });

  test('uses the provided surface in the Gemini CLI user agent', () {
    expect(
      buildGeminiCliUserAgent('gemini-2.5-pro', surface: 'vscode'),
      contains('; vscode) $geminiCodeAssistNodeJsUserAgentSuffix'),
    );
  });

  test('supports dynamic Gemini CLI prefixes from client names', () {
    expect(
      buildGeminiCliUserAgent('gemini-2.5-pro', clientName: 'a2a-server', surface: 'vscode'),
      startsWith('GeminiCLI-a2a-server/$geminiCodeAssistCliVersion/gemini-2.5-pro '),
    );
    expect(
      buildGeminiCliUserAgent('gemini-2.5-pro', clientName: 'acp-zed', surface: 'zed'),
      startsWith('GeminiCLI-acp-zed/$geminiCodeAssistCliVersion/gemini-2.5-pro '),
    );
  });

  test('keeps explicit Gemini CLI prefixes unchanged', () {
    expect(
      buildGeminiCliUserAgent(
        'gemini-2.5-pro',
        clientPrefix: 'GeminiCLI-acp-intellijidea',
        surface: 'jetbrains',
      ),
      startsWith('GeminiCLI-acp-intellijidea/$geminiCodeAssistCliVersion/gemini-2.5-pro '),
    );
  });

  test('includes privileged user id alongside existing auth headers', () {
    final headers = buildGeminiCodeAssistHeaders(
      accessToken: 'access-token',
      model: 'gemini-2.5-pro',
      privilegedUserId: 'install-123',
    );

    expect(headers[HttpHeaders.authorizationHeader], 'Bearer access-token');
    expect(headers[HttpHeaders.contentTypeHeader], 'application/json');
    expect(headers[HttpHeaders.acceptHeader], 'application/json');
    expect(headers['x-goog-api-client'], geminiCodeAssistGoogApiClientHeader);
    expect(headers['x-gemini-api-privileged-user-id'], 'install-123');
  });
}
