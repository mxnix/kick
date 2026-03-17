import 'package:flutter_test/flutter_test.dart';
import 'package:kick/core/platform/windows_desktop_runtime.dart';

void main() {
  test('detects hidden startup argument', () {
    final options = WindowsLaunchOptions.fromArguments(const [
      '--foo',
      windowsLaunchToTrayArgument,
    ]);

    expect(options.startHidden, isTrue);
  });

  test('ignores unrelated startup arguments', () {
    final options = WindowsLaunchOptions.fromArguments(const ['--foo', '--bar']);

    expect(options.startHidden, isFalse);
  });
}
