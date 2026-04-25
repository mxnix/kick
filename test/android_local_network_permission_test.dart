import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/platform/android_local_network_permission.dart';
import 'package:kick/data/models/app_settings.dart';

void main() {
  test('requires Android local network permission for LAN mode', () {
    final settings = AppSettings.defaults(apiKey: 'key').copyWith(allowLan: true);

    expect(requiresAndroidLocalNetworkPermission(settings), isTrue);
  });

  test('does not require Android local network permission for loopback hosts', () {
    final defaults = AppSettings.defaults(apiKey: 'key');

    expect(requiresAndroidLocalNetworkPermission(defaults.copyWith(host: '127.0.0.1')), isFalse);
    expect(requiresAndroidLocalNetworkPermission(defaults.copyWith(host: 'localhost')), isFalse);
    expect(requiresAndroidLocalNetworkPermission(defaults.copyWith(host: '::1')), isFalse);
  });

  test('requires Android local network permission for non-loopback bind hosts', () {
    final defaults = AppSettings.defaults(apiKey: 'key');

    expect(requiresAndroidLocalNetworkPermission(defaults.copyWith(host: '192.168.1.20')), isTrue);
  });
}
