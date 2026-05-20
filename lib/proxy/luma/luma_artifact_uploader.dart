import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../data/models/account_profile.dart';
import '../gemini/gemini_code_assist_client.dart'
    show GeminiGatewayException, GeminiGatewayFailureKind, GeminiGatewayFailureSource;
import 'luma_realm_client.dart';
import 'luma_realm_models.dart';
import 'luma_session.dart';

/// Wraps the three-step artifact creation dance:
/// `POST /artifacts` → `PUT presigned_url` → `POST /artifacts/{id}/complete`.
class LumaArtifactUploader {
  LumaArtifactUploader({required LumaRealmClient client, http.Client? httpClient})
    : _client = client,
      _http = httpClient ?? http.Client();

  final LumaRealmClient _client;
  final http.Client _http;

  /// Uploads [bytes] (size > 0) into [realmId] using [contentType].
  /// Returns the completed artifact record (without the presigned URL).
  Future<LumaArtifact> upload({
    required LumaSession session,
    required String realmId,
    required Uint8List bytes,
    required String contentType,
    required String name,
    int? width,
    int? height,
  }) async {
    if (bytes.isEmpty) {
      throw GeminiGatewayException(
        provider: AccountProvider.luma,
        kind: GeminiGatewayFailureKind.invalidRequest,
        message: 'Cannot upload an empty artifact to Luma.',
        statusCode: 400,
      );
    }

    final reservation = await _client.reserveArtifact(
      session,
      realmId: realmId,
      contentType: contentType,
      name: name,
      width: width,
      height: height,
    );

    final presignedUrl = reservation.presignedUrl!;
    final putResponse = await _http
        .put(Uri.parse(presignedUrl), headers: {'content-type': contentType}, body: bytes)
        .timeout(const Duration(minutes: 5));

    if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
      throw GeminiGatewayException(
        provider: AccountProvider.luma,
        kind: GeminiGatewayFailureKind.serviceUnavailable,
        message:
            'S3 PUT for artifact ${reservation.id} failed with HTTP ${putResponse.statusCode}.',
        statusCode: putResponse.statusCode,
        source: GeminiGatewayFailureSource.transport,
      );
    }

    return _client.completeArtifact(session, realmId: realmId, artifactId: reservation.id);
  }

  void close() {
    _http.close();
  }
}
