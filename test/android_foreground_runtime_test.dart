import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/platform/android_foreground_runtime.dart';

void main() {
  test('treats a closed notification permission dialog as expected', () {
    expect(
      isExpectedAndroidNotificationPermissionCancellation(
        PlatformException(
          code: 'a',
          message: 'The permission request dialog was closed or the request was cancelled.',
        ),
      ),
      isTrue,
    );
  });

  test('does not suppress unrelated platform exceptions', () {
    expect(
      isExpectedAndroidNotificationPermissionCancellation(
        PlatformException(code: 'network_error', message: 'Something else failed.'),
      ),
      isFalse,
    );
  });
}
