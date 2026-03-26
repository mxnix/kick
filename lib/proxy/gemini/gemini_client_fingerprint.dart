import 'dart:ffi';
import 'dart:io';

import 'gemini_auth_constants.dart';

Map<String, String> buildCodeAssistClientMetadata(String projectId) {
  return {
    'ideName': geminiCodeAssistIdeName,
    'pluginType': geminiCodeAssistPluginType,
    'ideVersion': geminiCodeAssistCliVersion,
    'platform': codeAssistClientMetadataPlatform(),
    'updateChannel': geminiCodeAssistUpdateChannel,
    'duetProject': projectId,
  };
}

String buildGeminiCliUserAgent(
  String model, {
  String? surface,
  String? clientName,
  String? clientPrefix,
}) {
  final resolvedModel = model.trim().isEmpty ? 'unknown' : model.trim();
  final resolvedSurface = _normalizeUserAgentValue(
    surface,
    fallback: geminiCodeAssistUserAgentSurface,
  );
  final resolvedPrefix = buildGeminiCliUserAgentPrefix(
    clientName: clientName,
    clientPrefix: clientPrefix,
  );
  return '$resolvedPrefix/$geminiCodeAssistCliVersion/$resolvedModel '
      '(${nodeStylePlatform()}; ${nodeStyleArchitecture()}; $resolvedSurface) '
      'google-api-nodejs-client/$geminiCodeAssistGoogleApiNodeClientVersion';
}

String buildGeminiCliUserAgentPrefix({String? clientName, String? clientPrefix}) {
  final normalizedClientPrefix = _normalizeUserAgentValue(clientPrefix);
  if (normalizedClientPrefix != null) {
    return normalizedClientPrefix;
  }

  final normalizedClientName = _normalizeUserAgentValue(clientName);
  if (normalizedClientName == null) {
    return geminiCodeAssistUserAgentPrefix;
  }
  if (normalizedClientName == geminiCodeAssistUserAgentPrefix ||
      normalizedClientName.startsWith('$geminiCodeAssistUserAgentPrefix-')) {
    return normalizedClientName;
  }
  return '$geminiCodeAssistUserAgentPrefix-$normalizedClientName';
}

Map<String, String> buildGeminiCodeAssistHeaders({
  required String accessToken,
  required String model,
  String? privilegedUserId,
  String tokenType = 'Bearer',
  String accept = 'application/json',
  String? surface,
  String? clientName,
  String? clientPrefix,
  bool? includePrivilegedUserId,
}) {
  final resolvedPrivilegedUserId = privilegedUserId?.trim();
  final shouldIncludePrivilegedUserId =
      includePrivilegedUserId ?? shouldSendGeminiPrivilegedUserId();
  return {
    HttpHeaders.authorizationHeader: '$tokenType $accessToken',
    HttpHeaders.contentTypeHeader: 'application/json',
    HttpHeaders.userAgentHeader: buildGeminiCliUserAgent(
      model,
      surface: surface ?? determineGeminiCliSurface(),
      clientName: clientName,
      clientPrefix: clientPrefix,
    ),
    HttpHeaders.acceptHeader: accept,
    'x-goog-api-client': geminiCodeAssistGoogApiClientHeader,
    if (shouldIncludePrivilegedUserId &&
        resolvedPrivilegedUserId != null &&
        resolvedPrivilegedUserId.isNotEmpty)
      'x-gemini-api-privileged-user-id': resolvedPrivilegedUserId,
  };
}

bool shouldSendGeminiPrivilegedUserId({Map<String, String>? environment}) {
  final rawValue = (environment ?? Platform.environment)['KICK_GEMINI_INCLUDE_PRIVILEGED_USER_ID']
      ?.trim();
  if (rawValue == null || rawValue.isEmpty) {
    return false;
  }

  switch (rawValue.toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
    case 'on':
      return true;
    default:
      return false;
  }
}

String determineGeminiCliSurface({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final customSurface =
      _normalizeUserAgentValue(env['GEMINI_CLI_SURFACE']) ??
      _normalizeUserAgentValue(env['SURFACE']);
  if (customSurface != null) {
    return customSurface;
  }

  if (env.containsKey('ANTIGRAVITY_CLI_ALIAS')) {
    return 'antigravity';
  }
  if (env.containsKey('__COG_BASHRC_SOURCED')) {
    return 'devin';
  }
  if (env.containsKey('REPLIT_USER')) {
    return 'replit';
  }
  if (env.containsKey('CURSOR_TRACE_ID')) {
    return 'cursor';
  }
  if (env.containsKey('CODESPACES')) {
    return 'codespaces';
  }
  if (env.containsKey('EDITOR_IN_CLOUD_SHELL') || env.containsKey('CLOUD_SHELL')) {
    return 'cloudshell';
  }
  if (env['TERM_PRODUCT'] == 'Trae') {
    return 'trae';
  }
  if (env.containsKey('MONOSPACE_ENV')) {
    return 'firebasestudio';
  }
  if (env['POSITRON'] == '1') {
    return 'positron';
  }
  if (env['TERM_PROGRAM'] == 'sublime') {
    return 'sublimetext';
  }
  if (env.containsKey('ZED_SESSION_ID') || env['TERM_PROGRAM'] == 'Zed') {
    return 'zed';
  }
  if (env.containsKey('XCODE_VERSION_ACTUAL')) {
    return 'xcode';
  }

  final terminalEmulator = env['TERMINAL_EMULATOR']?.toLowerCase();
  if (terminalEmulator?.contains('jetbrains') == true) {
    return 'jetbrains';
  }
  if (env['TERM_PROGRAM'] == 'vscode') {
    return 'vscode';
  }
  if (env.containsKey('GITHUB_SHA')) {
    return 'GitHub';
  }

  return geminiCodeAssistUserAgentSurface;
}

String codeAssistClientMetadataPlatform() {
  final platform = nodeStylePlatform();
  final architecture = nodeStyleArchitecture();

  if (platform == 'darwin' && architecture == 'x64') {
    return 'DARWIN_AMD64';
  }
  if (platform == 'darwin' && architecture == 'arm64') {
    return 'DARWIN_ARM64';
  }
  if (platform == 'linux' && architecture == 'x64') {
    return 'LINUX_AMD64';
  }
  if (platform == 'linux' && architecture == 'arm64') {
    return 'LINUX_ARM64';
  }
  if (platform == 'win32' && architecture == 'x64') {
    return 'WINDOWS_AMD64';
  }
  return geminiCodeAssistPlatformUnspecified;
}

String nodeStylePlatform() {
  if (Platform.isWindows) {
    return 'win32';
  }
  if (Platform.isMacOS) {
    return 'darwin';
  }
  return Platform.operatingSystem.trim().isEmpty ? 'unknown' : Platform.operatingSystem;
}

String nodeStyleArchitecture() {
  final abi = Abi.current().toString();
  final separatorIndex = abi.indexOf('_');
  if (separatorIndex == -1 || separatorIndex == abi.length - 1) {
    return abi;
  }
  return abi.substring(separatorIndex + 1);
}

String? _normalizeUserAgentValue(String? value, {String? fallback}) {
  final normalized = value?.trim();
  if (normalized != null && normalized.isNotEmpty) {
    return normalized;
  }
  return fallback;
}
