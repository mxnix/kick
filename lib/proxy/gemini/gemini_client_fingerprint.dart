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
      '$geminiCodeAssistNodeJsUserAgentSuffix';
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
  required String privilegedUserId,
  String tokenType = 'Bearer',
  String accept = 'application/json',
  String? surface,
  String? clientName,
  String? clientPrefix,
}) {
  return {
    HttpHeaders.authorizationHeader: '$tokenType $accessToken',
    HttpHeaders.contentTypeHeader: 'application/json',
    HttpHeaders.userAgentHeader: buildGeminiCliUserAgent(
      model,
      surface: surface,
      clientName: clientName,
      clientPrefix: clientPrefix,
    ),
    HttpHeaders.acceptHeader: accept,
    'x-goog-api-client': geminiCodeAssistGoogApiClientHeader,
    'x-gemini-api-privileged-user-id': privilegedUserId,
  };
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
