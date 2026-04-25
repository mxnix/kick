import 'dart:io';

import 'package:flutter/services.dart';

import '../../data/models/app_settings.dart';

const androidLocalNetworkPermissionDeniedMessage =
    'Local network permission is required to use LAN access on Android 17 or later.';

class AndroidLocalNetworkPermission {
  static const _channel = MethodChannel('kick/android_runtime');

  static Future<bool> ensureGranted() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      return await _channel.invokeMethod<bool>('ensureLocalNetworkPermission') ?? true;
    } on MissingPluginException {
      return true;
    }
  }
}

bool requiresAndroidLocalNetworkPermission(AppSettings settings) {
  if (settings.allowLan) {
    return true;
  }

  return !_isLoopbackBindHost(settings.host);
}

bool _isLoopbackBindHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == 'localhost' ||
      normalized == '::1' ||
      normalized == '[::1]' ||
      normalized == '0:0:0:0:0:0:0:1' ||
      normalized.startsWith('127.');
}
