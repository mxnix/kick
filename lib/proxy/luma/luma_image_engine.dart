import 'dart:async';

import 'package:http/http.dart' as http;

import '../../data/models/account_profile.dart';
import '../gemini/gemini_code_assist_client.dart'
    show GeminiGatewayException, GeminiGatewayFailureKind, GeminiGatewayFailureSource;
import 'luma_realm_client.dart';
import 'luma_realm_models.dart';
import 'luma_session.dart';

/// Maps OpenAI model names to Luma action types for image generation.
const List<String> lumaPublicImageModels = [
  'nano-banana-pro',
  'nano-banana-2',
  'gpt-image-2',
  'gpt-image-1.5',
  'seedream',
  'uni-1.1',
  'uni-image-1.1',
];

const Map<String, String> lumaImageModelActions = {
  'nano-banana-pro': 'create_image_nano_banana_pro',
  'nano-banana-2': 'create_image_nano_banana_2',
  'gpt-image-2': 'create_image_gpt_image_2',
  'gpt-image-1.5': 'create_image_gpt_image_1_5',
  'seedream': 'create_image_seedream',
  'uni-1': 'create_image_uni_1',
  'uni-1.1': 'create_image_uni_1',
  'uni-image-1.1': 'create_image_uni_1',
  'luma/nano-banana-pro': 'create_image_nano_banana_pro',
  'luma/nano-banana-2': 'create_image_nano_banana_2',
  'luma/gpt-image-2': 'create_image_gpt_image_2',
  'luma/gpt-image-1.5': 'create_image_gpt_image_1_5',
  'luma/seedream': 'create_image_seedream',
  'luma/uni-1': 'create_image_uni_1',
  'luma/uni-1.1': 'create_image_uni_1',
  'luma/uni-image-1.1': 'create_image_uni_1',
};

/// Default model when none is specified.
const String lumaDefaultImageModel = 'nano-banana-pro';

/// Result of a successful image generation.
class LumaImageResult {
  const LumaImageResult({
    required this.url,
    required this.artifactId,
    required this.model,
    required this.creditsUsed,
    this.revisedPrompt,
  });

  final String url;
  final String artifactId;
  final String model;
  final double creditsUsed;
  final String? revisedPrompt;
}

/// Orchestrates a single image generation request end-to-end:
/// submit action, wait for the CDN to make the artifact available, return
/// the signed URL.
class LumaImageEngine {
  LumaImageEngine({
    LumaRealmClient? client,
    http.Client? httpClient,
    Duration completionTimeout = const Duration(minutes: 5),
  }) : _client = client ?? LumaRealmClient(),
       _httpClient = httpClient ?? http.Client(),
       _completionTimeout = completionTimeout;

  final LumaRealmClient _client;
  final http.Client _httpClient;
  final Duration _completionTimeout;

  /// Generates an image and returns the signed CDN URL.
  ///
  /// [session] is the pre-loaded Luma session (cookies + realm).
  /// [referenceArtifactIds] are optional input artifact ids previously uploaded
  /// via [LumaArtifactUploader.upload]. They are forwarded as Luma's
  /// `references` field. [primarySourceArtifactId] selects the source image for
  /// `modify_image_*` actions.
  Future<LumaImageResult> generate({
    required LumaSession session,
    required String prompt,
    String? model,
    String? size,
    String? resolution,
    String? quality,
    String? responseFormat,
    int n = 1,
    List<String> referenceArtifactIds = const <String>[],
    String? primarySourceArtifactId,
  }) async {
    final effectiveModel =
        (model?.trim().isNotEmpty == true ? model!.trim() : lumaDefaultImageModel).toLowerCase();
    final sourceArtifactId = primarySourceArtifactId?.trim();
    final hasModifySource = sourceArtifactId != null && sourceArtifactId.isNotEmpty;
    final actionType = _resolveActionType(effectiveModel, modify: hasModifySource);
    if (actionType == null) {
      throw GeminiGatewayException(
        provider: AccountProvider.luma,
        kind: GeminiGatewayFailureKind.unsupportedModel,
        message:
            'Unknown Luma image model: $effectiveModel. '
            'Supported: ${lumaImageModelActions.keys.where((k) => !k.contains("/")).join(", ")}',
        statusCode: 400,
      );
    }

    if (!session.hasSession) {
      throw GeminiGatewayException(
        provider: AccountProvider.luma,
        kind: GeminiGatewayFailureKind.auth,
        message: 'Luma session not found. Reconnect the account.',
        statusCode: 401,
      );
    }

    final realmId = session.realmId;
    if (realmId == null || realmId.isEmpty) {
      throw GeminiGatewayException(
        provider: AccountProvider.luma,
        kind: GeminiGatewayFailureKind.invalidRequest,
        message: 'Luma account has no realm configured. Reconnect the account.',
        statusCode: 400,
      );
    }

    // Build fields
    final fields = _buildFields(
      actionType: actionType,
      prompt: prompt,
      size: size,
      resolution: resolution,
      quality: quality,
      primarySourceArtifactId: primarySourceArtifactId,
      referenceArtifactIds: referenceArtifactIds,
    );

    // Submit action
    final outputId = generateLumaArtifactId();
    final submission = await _client.submitAction(
      session,
      realmId: realmId,
      type: actionType,
      fields: fields,
      optimisticOutputIds: [outputId],
    );

    final expectedArtifactId = submission.allArtifactIds.isNotEmpty
        ? submission.allArtifactIds.first
        : outputId;

    // Resolve the signed CDN URL by polling `/downloads` until the server
    // is ready to issue one. Luma starts the action asynchronously, and the
    // browser app waits on its tldraw-multiplayer WebSocket for completion.
    // We bypass the WS protocol (it requires the client to push canvas
    // state) and instead retry `/downloads` directly: the endpoint returns
    // 404 "No downloadable artifacts found" while the action is still
    // running, then a signed CloudFront URL once the artifact lands.
    final signedUrl = await _waitForDownloadUrl(
      session: session,
      realmId: realmId,
      artifactId: expectedArtifactId,
    );

    return LumaImageResult(
      url: signedUrl,
      artifactId: expectedArtifactId,
      model: effectiveModel,
      creditsUsed: submission.estimatedCredits,
    );
  }

  Future<String> _waitForDownloadUrl({
    required LumaSession session,
    required String realmId,
    required String artifactId,
  }) async {
    final deadline = DateTime.now().add(_completionTimeout);
    var delay = const Duration(seconds: 2);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final files = await _client.requestDownloads(
          session,
          realmId: realmId,
          artifactIds: [artifactId],
        );
        if (files.isNotEmpty && files.first.url.isNotEmpty) {
          return files.first.url;
        }
      } on GeminiGatewayException catch (error) {
        // 404 means "not ready yet". Anything else (auth/quota/etc.) bubbles up.
        if (error.statusCode != 404) {
          rethrow;
        }
      }
      await Future<void>.delayed(delay);
      // Cap exponential backoff at 8s to keep the worst-case latency low.
      if (delay < const Duration(seconds: 8)) {
        delay *= 2;
      }
    }
    throw GeminiGatewayException(
      provider: AccountProvider.luma,
      kind: GeminiGatewayFailureKind.serviceUnavailable,
      message:
          'Luma did not finish generating artifact $artifactId within ${_completionTimeout.inSeconds}s.',
      statusCode: 504,
      source: GeminiGatewayFailureSource.transport,
    );
  }

  Map<String, Object?> _buildFields({
    required String actionType,
    required String prompt,
    String? size,
    String? resolution,
    String? quality,
    String? primarySourceArtifactId,
    List<String> referenceArtifactIds = const <String>[],
  }) {
    final fields = <String, Object?>{'prompt': prompt};
    final isModifyAction = actionType.startsWith('modify_image');
    final parsed = _parseSize(size);
    if (!isModifyAction) {
      fields['aspect_ratio'] = parsed.aspectRatio;
    }
    if (_actionSupportsResolution(actionType)) {
      fields['resolution'] =
          _normalizeLumaResolution(resolution, actionType: actionType) ?? parsed.resolution;
    }
    if (actionType.contains('gpt_image')) {
      fields['quality'] = quality?.trim().isNotEmpty == true ? quality!.trim() : 'medium';
      fields['output_format'] = 'png';
    }
    final references = referenceArtifactIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (isModifyAction) {
      final source = primarySourceArtifactId?.trim();
      if (source != null && source.isNotEmpty) {
        fields['source'] = source;
      }
      final extras = references.where((id) => id != fields['source']).toList(growable: false);
      if (extras.isNotEmpty) {
        fields['references'] = extras;
      }
    } else if (references.isNotEmpty) {
      fields['references'] = references;
    }
    return fields;
  }

  String? _resolveActionType(String model, {required bool modify}) {
    final base = lumaImageModelActions[model];
    if (base == null) {
      return null;
    }
    if (!modify) {
      return base;
    }
    // Translate `create_image_*` → `modify_image_*`. Both surfaces share the
    // same suffix in the Vespa REST API.
    return base.replaceFirst('create_image_', 'modify_image_');
  }

  /// Downloads the bytes referenced by [url]. Returns the raw payload so
  /// callers can re-encode it (e.g. to base64 for an OpenAI response).
  Future<List<int>> downloadBytes(String url) async {
    final response = await _httpClient.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GeminiGatewayException(
        provider: AccountProvider.luma,
        kind: GeminiGatewayFailureKind.serviceUnavailable,
        message: 'Luma CDN download failed for $url with HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
        source: GeminiGatewayFailureSource.transport,
      );
    }
    return response.bodyBytes;
  }

  void close() {
    _client.close();
    _httpClient.close();
  }
}

bool _actionSupportsResolution(String actionType) {
  return actionType.contains('nano_banana') ||
      actionType == 'create_image_gpt_image_2' ||
      actionType == 'modify_image_gpt_image_2' ||
      actionType == 'create_image_seedream';
}

String? _normalizeLumaResolution(String? value, {required String actionType}) {
  final normalized = value?.trim().toUpperCase();
  if (normalized == '512' && actionType.contains('nano_banana_2')) {
    return normalized;
  }
  return switch (normalized) {
    '1K' || '2K' || '4K' => normalized,
    _ => null,
  };
}

class _ParsedSize {
  const _ParsedSize({required this.aspectRatio, required this.resolution});
  final String aspectRatio;
  final String resolution;
}

_ParsedSize _parseSize(String? size) {
  if (size == null || size.trim().isEmpty) {
    return const _ParsedSize(aspectRatio: '16:9', resolution: '2K');
  }
  final trimmed = size.trim().toLowerCase();
  final parts = trimmed.split('x');
  if (parts.length == 2) {
    final w = int.tryParse(parts[0]);
    final h = int.tryParse(parts[1]);
    if (w != null && h != null && w > 0 && h > 0) {
      return _ParsedSize(
        aspectRatio: _closestAspectRatio(w, h),
        resolution: _closestResolution(w, h),
      );
    }
  }
  if (trimmed.contains(':')) {
    return _ParsedSize(aspectRatio: trimmed, resolution: '2K');
  }
  return const _ParsedSize(aspectRatio: '16:9', resolution: '2K');
}

String _closestAspectRatio(int w, int h) {
  final ratio = w / h;
  const ratios = <String, double>{
    '1:1': 1.0,
    '4:3': 4 / 3,
    '3:2': 3 / 2,
    '16:9': 16 / 9,
    '21:9': 21 / 9,
    '3:4': 3 / 4,
    '2:3': 2 / 3,
    '9:16': 9 / 16,
  };
  var closest = '16:9';
  var minDiff = double.infinity;
  ratios.forEach((name, value) {
    final diff = (ratio - value).abs();
    if (diff < minDiff) {
      minDiff = diff;
      closest = name;
    }
  });
  return closest;
}

String _closestResolution(int w, int h) {
  final maxDim = w > h ? w : h;
  if (maxDim >= 3840) return '4K';
  if (maxDim >= 1920) return '2K';
  return '1K';
}
