import 'dart:async';
import 'dart:io';

import '../../l10n/kick_localizations.dart';
import '../../proxy/gemini/gemini_code_assist_client.dart';

String formatUserFacingError(KickLocalizations l10n, Object error) {
  if (error is GeminiGatewayException) {
    return _formatGatewayError(l10n, error);
  }

  if (error is StateError) {
    return formatUserFacingMessage(l10n, error.message.toString());
  }

  if (error is TimeoutException) {
    return formatUserFacingMessage(l10n, error.message?.toString() ?? error.toString());
  }

  if (error is SocketException) {
    return l10n.errorNetworkUnavailable;
  }

  if (error is HttpException) {
    return l10n.errorGoogleServiceUnavailable;
  }

  if (error is FormatException) {
    return l10n.errorInvalidServiceResponse;
  }

  return formatUserFacingMessage(l10n, error.toString());
}

String formatUserFacingMessage(KickLocalizations l10n, String rawMessage) {
  final message = rawMessage.trim();
  if (message.isEmpty) {
    return l10n.errorUnknown;
  }

  final unwrappedMessage = _unwrapGeminiGatewayException(message);
  if (unwrappedMessage != null) {
    return formatUserFacingMessage(l10n, unwrappedMessage);
  }

  final lower = message.toLowerCase();
  if (lower.contains('oauth tokens for this account were not found')) {
    return l10n.errorOauthTokensMissing;
  }
  if (lower.contains('account not found')) {
    return l10n.errorAccountNotFound;
  }
  if (_looksLikePortInUseError(lower)) {
    return l10n.errorPortAlreadyInUse;
  }
  if (lower.contains('google oauth timed out')) {
    return l10n.errorGoogleAuthTimedOut;
  }
  if (_looksLikeGoogleAccountVerificationError(lower)) {
    return l10n.errorGoogleAccountVerificationRequired;
  }
  if (_looksLikeTermsOfServiceViolationError(lower)) {
    return l10n.errorGoogleTermsOfServiceViolation;
  }
  if (_looksLikeMissingProjectIdError(lower)) {
    return l10n.errorGoogleProjectIdMissing;
  }
  if (_looksLikeGoogleProjectAccessError(lower)) {
    return l10n.errorGoogleProjectAccessDenied;
  }
  if (_looksLikeReasoningConfigError(lower)) {
    return l10n.errorReasoningConfigRejected;
  }
  if (lower.contains('permission')) {
    return l10n.errorPermissionDenied;
  }
  if (_looksLikeQuotaError(lower)) {
    final retryHint = _retryHintFromMessage(l10n, message);
    if (retryHint != null) {
      if (_looksLikeQuotaExhaustedError(lower)) {
        return l10n.errorQuotaExhaustedRetry(retryHint);
      }
      return l10n.errorGoogleRateLimitedRetry(retryHint);
    }
    if (_looksLikeIndefiniteQuotaExhaustedError(lower)) {
      return l10n.errorQuotaExhaustedNoResetHint;
    }
    if (_looksLikeQuotaExhaustedError(lower)) {
      return l10n.errorQuotaExhausted;
    }
    return l10n.errorGoogleRateLimitedLater;
  }
  if (_looksLikeAuthError(lower)) {
    return l10n.errorAuthExpired;
  }
  if (_looksLikeNetworkError(lower)) {
    return l10n.errorNetworkUnavailable;
  }
  if (lower.contains('capacity')) {
    return l10n.errorGoogleCapacity;
  }
  if (lower.contains('service unavailable') || lower.contains('unavailable')) {
    return l10n.errorGoogleServiceUnavailable;
  }
  if (lower.contains('unsupported model') || lower.contains('model not found')) {
    return l10n.errorUnsupportedModel;
  }
  if (lower.contains('request body must be valid json')) {
    return l10n.errorInvalidJson;
  }
  if (lower.contains('unexpected gemini response shape')) {
    return l10n.errorUnexpectedResponse;
  }

  return _stripStackTrace(l10n, message);
}

String _formatGatewayError(KickLocalizations l10n, GeminiGatewayException error) {
  switch (error.kind) {
    case GeminiGatewayFailureKind.auth:
      switch (error.detail) {
        case GeminiGatewayFailureDetail.accountVerificationRequired:
          return l10n.errorGoogleAccountVerificationRequired;
        case GeminiGatewayFailureDetail.termsOfServiceViolation:
          return l10n.errorGoogleTermsOfServiceViolation;
        case GeminiGatewayFailureDetail.projectIdMissing:
          return l10n.errorGoogleProjectIdMissing;
        case GeminiGatewayFailureDetail.projectConfiguration:
          return _formatProjectConfigurationError(l10n, error.upstreamReason);
        case GeminiGatewayFailureDetail.quotaExhausted:
        case GeminiGatewayFailureDetail.indefiniteQuotaExhausted:
        case GeminiGatewayFailureDetail.rateLimited:
        case GeminiGatewayFailureDetail.reasoningConfigUnsupported:
        case GeminiGatewayFailureDetail.noHealthyAccountAvailable:
        case null:
          return l10n.errorAuthExpired;
      }
    case GeminiGatewayFailureKind.quota:
      if (error.detail == GeminiGatewayFailureDetail.indefiniteQuotaExhausted) {
        return l10n.errorQuotaExhaustedNoResetHint;
      }
      if (error.detail == GeminiGatewayFailureDetail.quotaExhausted) {
        if (error.retryAfter != null) {
          return l10n.errorQuotaExhaustedRetry(_formatDuration(l10n, error.retryAfter!));
        }
        return l10n.errorQuotaExhausted;
      }
      if (error.retryAfter != null) {
        return l10n.errorGoogleRateLimitedRetry(_formatDuration(l10n, error.retryAfter!));
      }
      return l10n.errorGoogleRateLimitedLater;
    case GeminiGatewayFailureKind.capacity:
      return l10n.errorGoogleCapacity;
    case GeminiGatewayFailureKind.serviceUnavailable:
      return l10n.errorGoogleServiceUnavailable;
    case GeminiGatewayFailureKind.unsupportedModel:
      return l10n.errorUnsupportedModel;
    case GeminiGatewayFailureKind.invalidRequest:
      if (error.detail == GeminiGatewayFailureDetail.projectIdMissing) {
        return l10n.errorGoogleProjectIdMissing;
      }
      if (error.detail == GeminiGatewayFailureDetail.reasoningConfigUnsupported) {
        return l10n.errorReasoningConfigRejected;
      }
      if (error.detail == GeminiGatewayFailureDetail.projectConfiguration) {
        return _formatProjectConfigurationError(l10n, error.upstreamReason);
      }
      return l10n.errorInvalidRequestRejected;
    case GeminiGatewayFailureKind.unknown:
      return formatUserFacingMessage(l10n, error.message);
  }
}

String _formatProjectConfigurationError(KickLocalizations l10n, String? upstreamReason) {
  return switch (upstreamReason?.trim().toUpperCase()) {
    'SERVICE_DISABLED' => l10n.errorGoogleProjectApiDisabled,
    'CONSUMER_INVALID' => l10n.errorGoogleProjectInvalid,
    _ => l10n.errorGoogleProjectAccessDenied,
  };
}

bool _looksLikeQuotaError(String message) {
  return message.contains('resource has been exhausted') ||
      message.contains('quota') ||
      message.contains('rate limit') ||
      message.contains('too many requests');
}

bool _looksLikeQuotaExhaustedError(String message) {
  return message.contains('quota exhausted') ||
      message.contains('exhausted your capacity on this model') ||
      message.contains('resource has been exhausted');
}

bool _looksLikeTermsOfServiceViolationError(String message) {
  return message.contains('tos_violation') ||
      message.contains('violation of terms of service') ||
      message.contains('disabled in this account for violation of terms of service');
}

bool _looksLikeIndefiniteQuotaExhaustedError(String message) {
  return message.contains('resource_exhausted') &&
      message.contains('resource has been exhausted') &&
      !message.contains('retry in') &&
      !message.contains('reset after');
}

bool _looksLikeAuthError(String message) {
  return message.contains('unauthenticated') ||
      message.contains('invalid_grant') ||
      message.contains('validation_required') ||
      message.contains('missing or invalid bearer token');
}

bool _looksLikeGoogleAccountVerificationError(String message) {
  return message.contains('verify your account') ||
      (message.contains('validation_required') && message.contains('cloudcode'));
}

bool _looksLikeMissingProjectIdError(String message) {
  return message.contains('could not discover a valid google cloud project id') ||
      message.contains('configure project_id explicitly') ||
      message.contains('configure project id explicitly') ||
      message.contains('no gemini oauth credentials were loaded') ||
      message.contains('project id is invalid');
}

bool _looksLikeGoogleProjectAccessError(String message) {
  return (message.contains('permission denied') || message.contains('forbidden')) &&
          (message.contains('googleapis') ||
              message.contains('cloudcode') ||
              message.contains('project') ||
              message.contains('consumer')) ||
      message.contains('api has not been used') ||
      message.contains('access not configured') ||
      message.contains('service disabled') ||
      message.contains('project id');
}

bool _looksLikeReasoningConfigError(String message) {
  return message.contains('thinking_budget') ||
      message.contains('thinking level') ||
      message.contains('thinking_level') ||
      message.contains('reasoning effort');
}

bool _looksLikeNetworkError(String message) {
  return message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('timed out') ||
      message.contains('network error while contacting');
}

bool _looksLikePortInUseError(String message) {
  return message.contains('address already in use') ||
      message.contains('only one usage') ||
      message.contains('shared flag to bind()') ||
      message.contains('binding multiple times on the same') ||
      message.contains('failed to create server socket');
}

String? _unwrapGeminiGatewayException(String message) {
  final match = RegExp(r'^GeminiGatewayException\([^,]+,\s*[^,]+,\s*(.+)\)$').firstMatch(message);
  return match?.group(1)?.trim();
}

String? _retryHintFromMessage(KickLocalizations l10n, String message) {
  final duration = _durationFromMessage(message);
  if (duration == null) {
    return null;
  }

  return _formatDuration(l10n, duration);
}

String _formatDuration(KickLocalizations l10n, Duration duration) {
  if (duration.inSeconds <= 0) {
    return l10n.durationFewSeconds;
  }
  if (duration.inMinutes == 0) {
    return l10n.durationSeconds(duration.inSeconds);
  }
  if (duration.inHours == 0) {
    final seconds = duration.inSeconds % 60;
    if (seconds == 0) {
      return l10n.durationMinutes(duration.inMinutes);
    }
    return l10n.durationMinutesSeconds(duration.inMinutes, seconds);
  }
  final minutes = duration.inMinutes % 60;
  if (minutes == 0) {
    return l10n.durationHours(duration.inHours);
  }
  return l10n.durationHoursMinutes(duration.inHours, minutes);
}

String _stripStackTrace(KickLocalizations l10n, String message) {
  final lines = message
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList(growable: false);
  if (lines.isEmpty) {
    return l10n.errorUnknown;
  }

  return lines.first;
}

Duration? _durationFromMessage(String message) {
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

Duration? _parseFlexibleDuration(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }

  final matches = RegExp(
    r'([0-9]+(?:\.[0-9]+)?)\s*(ms|milliseconds?|s|sec(?:onds?)?|m|mins?|minutes?|h|hr|hrs|hours?|d|days?)\b',
    caseSensitive: false,
  ).allMatches(raw.toLowerCase());

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
    return null;
  }

  return Duration(milliseconds: totalMilliseconds.round());
}
